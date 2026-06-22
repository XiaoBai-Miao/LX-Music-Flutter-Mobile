// 端到端测试：加载野花音源，跑 init → musicUrl
// 验证修复是否生效
//
// 关键修复点：
// 1. flutter_js 的 JSC 端 _sendMessage 内部会 jsonDecode(message)，
//    所以 sendMessage 第二个参数必须是 JSON 字符串。
//    修复方法：所有 sendMessage 调用都用 JSON.stringify 包装。
// 2. 野花脚本 init 阶段会发真实 HTTP 请求，body 期望 {code: 0, body: {...}}
//    嵌套结构。真实服务器可能返回其它格式，需要在 lx_request handler 中
//    对 init URL (/urlinfo/) 模拟 fake body。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_js/flutter_js.dart';

void main() {
  test('野花音源 E2E', () async {
    // 用 test() 而不是 testWidgets()，避免 fakeAsync 拦截真实 HTTP 请求
    TestWidgetsFlutterBinding.ensureInitialized();
    // 关键：关掉 test 环境对 HttpClient 的拦截
    HttpOverrides.global = null;

    // 创建 runtime
    final runtime = getJavascriptRuntime();

    // 读源脚本
    final scriptFile = File('tool/yehua_source.js');
    expect(scriptFile.existsSync(), true, reason: '找不到 tool/yehua_source.js');
    final script = scriptFile.readAsStringSync();
    // ignore: avoid_print
    print('源脚本长度: ${script.length} 字符');

    // 注入 lx_send 监听
    bool initedReceived = false;
    String? initPayload;
    runtime.onMessage('lx_send', (dynamic args) {
      try {
        Map<String, dynamic> data;
        if (args is String) {
          data = json.decode(args) as Map<String, dynamic>;
        } else if (args is Map) {
          data = Map<String, dynamic>.from(args);
        } else {
          return;
        }
        if (data['event'] == 'inited' && !initedReceived) {
          initedReceived = true;
          initPayload = json.encode(data['data']);
        }
        // ignore: avoid_print
        print('  [lx_send] event=${data['event']}');
      } catch (e) {
        // ignore: avoid_print
        print('  [lx_send parse err] $e');
      }
    });

    runtime.onMessage('console_log', (dynamic args) {
      // ignore: avoid_print
      print('  [JS log] $args');
    });
    runtime.onMessage('console_error', (dynamic args) {
      // ignore: avoid_print
      print('  [JS error] $args');
    });

    runtime.onMessage('set_timeout', (dynamic args) {
      try {
        final data = args is String ? json.decode(args) : Map<String, dynamic>.from(args as Map);
        final id = data['id'];
        final ms = data['ms'] as int;
        Future.delayed(Duration(milliseconds: ms), () {
          runtime.evaluate('if(globalThis._callbacks["timeout_$id"]) { globalThis._callbacks["timeout_$id"](); delete globalThis._callbacks["timeout_$id"]; }');
          flushMicrotasks(runtime);
        });
      } catch (e) {
        // ignore: avoid_print
        print('  [set_timeout err] $e');
      }
    });

    // 注入基础环境
    runtime.evaluate('''
      globalThis.window = globalThis;
      globalThis.process = { env: { NODE_ENV: 'production' } };
      globalThis.navigator = { userAgent: 'Mozilla/5.0' };
      // console.log/error 用 JSON.stringify 包装 sendMessage 的 message 参数，
      // 因为 flutter_js JSC 端 _sendMessage 内部会 jsonDecode(message)。
      globalThis.console = {
        log: function() {
          var msg = Array.prototype.slice.call(arguments).map(function(v) {
            try { return typeof v === 'object' ? JSON.stringify(v) : String(v); } catch(e) { return "[Object]"; }
          }).join(' ');
          sendMessage('console_log', JSON.stringify(msg));
        },
        error: function() {
          var msg = Array.prototype.slice.call(arguments).map(function(v) {
            try { return typeof v === 'object' ? JSON.stringify(v) : String(v); } catch(e) { return "[Object]"; }
          }).join(' ');
          sendMessage('console_error', JSON.stringify(msg));
        }
      };
      globalThis._callbacks = {};
      globalThis._pendingRequests = 0;
      globalThis._timeoutCounter = 0;
      globalThis.setTimeout = function(fn, ms) {
        globalThis._timeoutCounter++;
        var id = Date.now() + globalThis._timeoutCounter;
        globalThis._callbacks['timeout_' + id] = fn;
        sendMessage('set_timeout', JSON.stringify({ id: id, ms: ms || 0 }));
        return id;
      };
      globalThis.clearTimeout = function(id) {
        if (globalThis._callbacks) delete globalThis._callbacks['timeout_' + id];
      };
    ''');

    // atob/btoa
    runtime.evaluate(r'''
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      globalThis.atob = function(input) {
        var str = String(input).replace(/[=]+$/, '');
        var output = '';
        for (var bc = 0, bs, buffer, idx = 0; buffer = str.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
          buffer = chars.indexOf(buffer);
        }
        return output;
      };
      globalThis.btoa = function(input) {
        var str = String(input);
        var map = chars, output = '';
        for (var block, charCode, idx = 0; str.charAt(idx | 0) || (map = '=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
          charCode = str.charCodeAt(idx += 3 / 4);
          if (charCode > 0xFF) throw new Error("'btoa' failed");
          block = block << 8 | charCode;
        }
        return output;
      };
    ''');

    // 桥接 lx.request
    runtime.onMessage('lx_request', (dynamic args) async {
      try {
        Map<String, dynamic> data;
        if (args is String) {
          data = json.decode(args) as Map<String, dynamic>;
        } else if (args is Map) {
          data = Map<String, dynamic>.from(args);
        } else {
          return;
        }
        final url = data['url'] as String;
        final options = data['options'];
        final callbackId = data['callbackId'] as String;
        // ignore: avoid_print
        print('  [lx_request] url=$url');

        final Map<String, dynamic> optionsMap = options is Map ? Map<String, dynamic>.from(options) : <String, dynamic>{};

        // 模拟生产代码，对 JSON body 自动 parse
        dynamic bodyResult = '';
        int statusCode = 200;

        // 关键：野花脚本 init 阶段调 urlinfo 接口，期望 body 形如
        // {code: 0, s: 'kw|128k&...', m: ''}。脚本 callback 收到的 res.body
        // 就是这个对象，res.body.code === 0 才不抛错，res.body.s.split('&')
        // 解析音源列表。
        // musicUrl 阶段调 /url/ 接口，期望 body 形如 {code: 0, data: {url: '...', type: '...', br: ...}}。
        if (url.contains('/urlinfo/')) {
          // ignore: avoid_print
          print('  [lx_request MOCK init]');
          bodyResult = {
            'code': 0,
            's': 'kw|128k&wy|128k&mg|128k&tx|128k&kg|128k',
            'm': ''
          };
          statusCode = 200;
        } else if (url.contains('/url/')) {
          // ignore: avoid_print
          print('  [lx_request MOCK musicUrl]');
          bodyResult = {
            'code': 0,
            'data': {
              'url': 'http://music.126.net/song/media/outer/url?id=123456.mp3',
              'type': '128k',
              'br': 128
            }
          };
          statusCode = 200;
        } else {
          try {
            final client = HttpClient();
            try {
              final req = await client.openUrl('GET', Uri.parse(url));
              final headers = optionsMap['headers'] is Map ? Map<String, dynamic>.from(optionsMap['headers']) : null;
              if (headers != null) {
                headers.forEach((k, v) {
                  try { req.headers.set(k, v.toString()); } catch (_) {}
                });
              }
              final response = await req.close();
              statusCode = response.statusCode;
              final rawBody = await response.transform(utf8.decoder).join();
              // ignore: avoid_print
              print('  [lx_request REAL] status=$statusCode, body length=${rawBody.length}');
              // 模拟生产代码的 JSON auto-parse
              final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
              if (contentType.contains('application/json') || rawBody.trim().startsWith('{')) {
                try { bodyResult = json.decode(rawBody); }
                catch (_) { bodyResult = rawBody; }
              } else {
                bodyResult = rawBody;
              }
            } finally {
              client.close();
            }
          } catch (e) {
            // ignore: avoid_print
            print('  [lx_request net err] $e');
            statusCode = 500;
            bodyResult = '';
          }
        }

        // ignore: avoid_print
        print('  [lx_request] status=$statusCode, body 类型=${bodyResult.runtimeType}');
        if (bodyResult is Map) {
          // ignore: avoid_print
          print('  [lx_request] body keys=${bodyResult.keys.toList()}');
        } else if (bodyResult is String && bodyResult.length < 200) {
          // ignore: avoid_print
          print('  [lx_request] body=$bodyResult');
        }

        _executeCallback(runtime, callbackId, null, {
          'statusCode': statusCode,
          'body': bodyResult,
          'headers': {},
        }, bodyResult is String ? bodyResult : json.encode(bodyResult));
      } catch (e) {
        // ignore: avoid_print
        print('  [lx_request 解析错误] $e');
      }
    });

    // 注入 lx 全局对象
    // 关键修复：lx.send 内部的所有 sendMessage 都用 JSON.stringify 包装
    runtime.evaluate(r'''
      globalThis.lx = {
        version: '2.0.0',
        env: 'desktop',
        EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
        request: function(url, options, callback) {
          if (typeof options === 'function') { callback = options; options = {}; }
          var requestInternal = function(cb) {
            var callbackId = 'cb_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            globalThis._callbacks[callbackId] = function(err, res, body) {
              sendMessage('console_log', JSON.stringify('[cb invoke] callbackId=' + callbackId));
              try { cb(err, res, body || (res ? res.body : null)); }
              finally { globalThis._pendingRequests--; }
              sendMessage('console_log', JSON.stringify('[cb done] callbackId=' + callbackId));
            };
            globalThis._pendingRequests++;
            sendMessage('lx_request', JSON.stringify({ url: url, options: options || {}, callbackId: callbackId }));
            return function() {};
          };
          if (typeof callback === 'function') return requestInternal(callback);
          else return new Promise(function(resolve, reject) {
            requestInternal(function(err, res, body) { if (err) reject(new Error(err)); else resolve(res); });
          });
        },
        send: function(eventName, data) {
          // 关键：必须用 JSON.stringify 包装，否则 JSC _sendMessage 内部
          // jsonDecode(message) 抛 FormatException，handler 永远不触发。
          sendMessage('lx_send', JSON.stringify({ event: eventName, data: data }));
          return true;
        },
        on: function(eventName, handler) {
          if (!globalThis._eventHandlers) globalThis._eventHandlers = {};
          if (!globalThis._eventHandlers[eventName]) globalThis._eventHandlers[eventName] = [];
          globalThis._eventHandlers[eventName].push(handler);
        },
        utils: {
          buffer: {
            from: function(data, encoding) {
              var str = '';
              if (typeof data === 'string') {
                if (encoding === 'hex') {
                  for (var i = 0; i < data.length; i += 2) str += String.fromCharCode(parseInt(data.substr(i, 2), 16));
                } else if (encoding === 'base64') {
                  str = globalThis.atob(data);
                } else { str = data; }
              } else if (data && typeof data.length === 'number') {
                for (var i = 0; i < data.length; i++) {
                  var c = data[i];
                  str += String.fromCharCode(typeof c === 'number' ? c : 0);
                }
              }
              return {
                _str: str, _isBuffer: true, length: str.length,
                toString: function(enc) {
                  if (enc === 'hex') {
                    var hex = '';
                    for (var i = 0; i < this._str.length; i++) {
                      var h = this._str.charCodeAt(i).toString(16);
                      hex += h.length === 1 ? '0' + h : h;
                    }
                    return hex;
                  }
                  if (enc === 'base64') return globalThis.btoa(this._str);
                  return this._str;
                }
              };
            },
            // 关键：野花脚本 musicUrl handler 内部调 utils.buffer.bufToString，
            // 必须注入此方法。
            bufToString: function(buffer, encoding) {
              return buffer && buffer.toString ? buffer.toString(encoding) : String(buffer);
            }
          },
          crypto: { md5: function(str) { return 'mock_md5_' + str; } }
        },
        currentScriptInfo: {
          id: 'test_yehua', name: '野花测试', version: '1.0.0',
          author: 'test', description: '', homepage: '', rawScript: ''
        }
      };
    ''');

    // 执行源脚本
    final wrapper = '(function() { try { $script } catch(e) { sendMessage("console_error", JSON.stringify("Script error: " + e.message + " " + (e.stack||""))); } })();';
    final result = runtime.evaluate(wrapper);
    // ignore: avoid_print
    print('脚本执行: isError=${result.isError}, stringResult=${result.stringResult}');
    expect(result.isError, false, reason: '脚本执行失败: ${result.stringResult}');

    // 用真实 wall clock 等待 inited
    final sw = Stopwatch()..start();
    while (!initedReceived && sw.elapsed < Duration(seconds: 15)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('inited=$initedReceived 耗时 ${sw.elapsedMilliseconds}ms');
    if (initPayload != null) {
      // ignore: avoid_print
      print('  sources payload: $initPayload');
    } else {
      // ignore: avoid_print
      print('  (未收到 inited)');
    }

    // 测 musicUrl（野花脚本不实现 search，直接测 musicUrl）
    if (initedReceived) {
      final urlResult = await _callRequest(runtime, {
        'action': 'musicUrl',
        'source': 'kw',
        'info': {
          'type': '128k',
          'musicInfo': {
            'songmid': '123456',
            'name': '测试歌曲',
            'singer': '测试歌手',
            'source': 'kw'
          }
        }
      });
      // ignore: avoid_print
      print('musicUrl 返回: $urlResult');
      if (urlResult != null && urlResult['url'] != null) {
        // ignore: avoid_print
        print('✓ 播放 URL: ${urlResult['url']}');
      }
    }

    runtime.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

void flushMicrotasks(JavascriptRuntime runtime, {int maxIterations = 64}) {
  for (int i = 0; i < maxIterations; i++) {
    try {
      // JSC 不需要手动 flush microtask，但 executePendingJob 是 no-op
      runtime.executePendingJob();
      final check = runtime.evaluate('(globalThis._pendingRequests || 0)');
      final pending = check.rawResult;
      if (pending is int && pending <= 0) {
        for (int j = 0; j < 8; j++) {
          runtime.executePendingJob();
          runtime.evaluate('void 0;');
        }
        return;
      }
      runtime.evaluate('void 0;');
    } catch (_) {
      return;
    }
  }
}

void _executeCallback(JavascriptRuntime runtime, String callbackId, String? err, Map<String, dynamic>? res, dynamic body) {
  // 关键：所有 sendMessage 调用都用 JSON.stringify 包装
  final args = [err, res, body];
  final argsJson = json.encode(args);
  final varName = 'temp_args_${DateTime.now().millisecondsSinceEpoch}_${callbackId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
  // ignore: avoid_print
  print('  [_executeCallback] callbackId=$callbackId, varName=$varName, argsJson.length=${argsJson.length}');
  runtime.evaluate('globalThis.$varName = $argsJson;');

  // dump 信息：所有 sendMessage 用 JSON.stringify 包装
  final dumpResult = runtime.evaluate('''
    (function() {
      try {
        sendMessage('console_log', JSON.stringify('[dump] H=' + JSON.stringify(globalThis.$varName)));
        return 'DUMP_OK';
      } catch (e) { return 'DUMP_ERR:' + e.message; }
    })()
  ''');
  // ignore: avoid_print
  print('  [dump result] isError=${dumpResult.isError}, stringResult=${dumpResult.stringResult}');

  // cb apply：所有 sendMessage 用 JSON.stringify 包装
  final evalResult = runtime.evaluate('''
    (function() {
      try {
        sendMessage('console_log', JSON.stringify('[cb apply] looking for ' + '$callbackId'));
        var cb = globalThis._callbacks['$callbackId'];
        sendMessage('console_log', JSON.stringify('[cb apply] cb type=' + typeof cb));
        if (cb) {
          sendMessage('console_log', JSON.stringify('[cb apply] calling cb.apply'));
          cb.apply(null, globalThis.$varName);
          sendMessage('console_log', JSON.stringify('[cb apply] cb returned'));
          delete globalThis._callbacks['$callbackId'];
        } else {
          sendMessage('console_error', JSON.stringify('[js] callback not found: ' + '$callbackId'));
        }
      } catch (e) {
        sendMessage('console_error', JSON.stringify('[js] cb threw: ' + e.message + ' stack=' + (e.stack || '')));
      }
      delete globalThis.$varName;
    })()
  ''');
  if (evalResult.isError) {
    // ignore: avoid_print
    print('  [cb eval error] ${evalResult.stringResult}');
  }
  flushMicrotasks(runtime);
}

Future<Map<String, dynamic>?> _callRequest(JavascriptRuntime runtime, Map<String, dynamic> params) async {
  final Completer<Map<String, dynamic>?> completer = Completer();
  final reqId = 'req_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';
  final paramsJson = json.encode(params);
  final varName = 'temp_params_${reqId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
  runtime.evaluate('globalThis.$varName = $paramsJson;');

  runtime.onMessage('lx_response', (dynamic args) {
    if (completer.isCompleted) return;
    try {
      Map<String, dynamic> data;
      if (args is String) {
        data = json.decode(args) as Map<String, dynamic>;
      } else if (args is Map) {
        data = Map<String, dynamic>.from(args);
      } else {
        completer.complete(null);
        return;
      }
      if (data['reqId'] == reqId) {
        if (data['error'] != null) {
          // ignore: avoid_print
          print('  [lx_response error] ${data['error']}');
          completer.complete(null);
        } else if (data['data'] is Map) {
          completer.complete(Map<String, dynamic>.from(data['data'] as Map));
        } else {
          completer.complete(null);
        }
      }
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
  });

  final script = '''
    (async function() {
      try {
        var params = globalThis.$varName;
        delete globalThis.$varName;
        var reqId = ${json.encode(reqId)};
        var handlers = globalThis._eventHandlers && globalThis._eventHandlers['request'] || [];
        if (handlers.length === 0) {
          sendMessage('lx_response', JSON.stringify({ reqId: reqId, error: 'no handlers' }));
          return;
        }
        var result = null;
        for (var i = 0; i < handlers.length; i++) {
          try {
            var res = await handlers[i](params);
            if (res) { result = res; break; }
          } catch (innerErr) {
            console.error('Handler error: ' + innerErr.message);
          }
        }
        sendMessage('lx_response', JSON.stringify({ reqId: reqId, data: result }));
      } catch (e) {
        sendMessage('lx_response', JSON.stringify({ reqId: reqId, error: e.message }));
      }
    })();
  ''';
  final r = runtime.evaluate(script);
  if (r.isError) {
    // ignore: avoid_print
    print('  evaluate 错误: ${r.stringResult}');
    return null;
  }

  flushMicrotasks(runtime);

  return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
    // ignore: avoid_print
    print('  请求超时 (30秒)');
    return null;
  });
}
