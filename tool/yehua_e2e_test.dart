// 端到端测试：野花音源完整流程 (inited -> musicUrl)
// 验证 CustomSourceEngine 能否让野花音源脚本正常工作
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_js/flutter_js.dart';

void main() async {
  print('=== 野花音源 Flutter 端到端测试 ===\n');

  // 0) 绕过测试环境的 HTTP 拦截
  HttpOverrides.global = null;

  // 1) 读源脚本
  final scriptFile = File('tool/yehua_source.js');
  if (!scriptFile.existsSync()) {
    print('错误: 找不到 tool/yehua_source.js');
    exit(1);
  }
  final script = scriptFile.readAsStringSync();
  print('源脚本长度: ${script.length} 字符\n');

  // 2) 创建 JS runtime
  final runtime = getJavascriptRuntime();

  // 3) 注入基础环境 + lx 全局对象
  _setupBaseEnv(runtime);
  _setupLx(runtime);

  // 4) 注入 currentScriptInfo
  runtime.evaluate(r'''
    globalThis.lx.currentScriptInfo = {
      id: 'yehua_test',
      name: '野花测试',
      version: '1.0.0',
      author: 'test',
      description: '野花音源端到端测试',
      homepage: '',
      rawScript: ''
    };
  ''');

  // 5) 监听 inited 事件
  final initCompleter = Completer<Map<String, dynamic>>();
  runtime.onMessage('lx_send', (dynamic args) {
    try {
      final data = (args is String)
          ? json.decode(args) as Map<String, dynamic>
          : args as Map<String, dynamic>;
      print('  [lx_send] event=${data['event']}');
      if (data['event'] == 'inited') {
        initCompleter.complete(data['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      print('  [lx_send 解析错误] $e');
    }
  });

  runtime.onMessage('console_log', (dynamic args) {
    print('  [JS log] $args');
  });
  runtime.onMessage('console_error', (dynamic args) {
    print('  [JS error] $args');
  });
  runtime.onMessage('set_timeout', (dynamic args) {
    // ignore
  });
  runtime.onMessage('clear_timeout', (dynamic args) {
    // ignore
  });

  // 6) 执行源脚本
  print('--- 1) 执行源脚本 ---');
  final wrapper = '(function() { try { ${script.replaceAll('\\n', '\\n')} } catch(e) { sendMessage("console_error", "Script error: " + e.message); } })();';
  final result = runtime.evaluate(wrapper);
  if (result.isError) {
    print('脚本执行错误: ${result.stringResult}');
    exit(1);
  }
  print('脚本执行完成 (同步部分)');

  // 7) 等待 inited 事件
  print('\n--- 2) 等待 inited 事件 (最多 30 秒) ---');
  Map<String, dynamic>? initedData;
  try {
    initedData = await initCompleter.future.timeout(const Duration(seconds: 30));
    print('✓ 收到 inited 事件');
    if (initedData != null) {
      final sources = initedData['sources'] as Map<String, dynamic>?;
      if (sources != null) {
        print('  支持的音源: ${sources.keys.join(', ')}');
        for (final entry in sources.entries) {
          final info = entry.value as Map<String, dynamic>;
          print('    ${entry.key}: actions=${info['actions']}, qualitys=${info['qualitys']}');
        }
      }
    }
  } on TimeoutException {
    print('✗ 30 秒内未收到 inited 事件');
    runtime.dispose();
    exit(1);
  }

  // 8) 测试 musicUrl
  print('\n--- 3) 测试 musicUrl (source=kw, songmid=123456) ---');
  final musicUrlResult = await _callRequest(runtime, {
    'source': 'kw',
    'action': 'musicUrl',
    'info': {
      'type': '128k',
      'musicInfo': {
        'songmid': '123456',
        'name': '测试歌曲',
        'singer': '测试歌手',
        'source': 'kw',
        'interval': '03:50',
        'album': '测试专辑',
        'img': '',
        'albumName': '测试专辑',
        'picUrl': '',
        'hash': '123456',
      }
    }
  });

  if (musicUrlResult == null) {
    print('✗ musicUrl 返回 null');
    runtime.dispose();
    exit(1);
  }

  print('musicUrl 返回: ${json.encode(musicUrlResult)}');
  final url = musicUrlResult['url'] as String?;
  if (url == null || url.isEmpty) {
    print('✗ musicUrl 未返回 url 字段');
    runtime.dispose();
    exit(1);
  }

  print('\n✓ musicUrl 测试通过！');
  print('  url: $url');

  runtime.dispose();
  print('\n=== 测试结束 ===');
}

void _setupBaseEnv(JavascriptRuntime runtime) {
  runtime.evaluate('''
    globalThis.window = globalThis;
    globalThis.process = { env: { NODE_ENV: 'production' } };
    globalThis.navigator = { userAgent: 'Mozilla/5.0' };
    globalThis.console = {
      log: function() {
        var msg = Array.prototype.slice.call(arguments).map(function(v) {
          try { return typeof v === 'object' ? JSON.stringify(v) : String(v); } catch(e) { return "[Object]"; }
        }).join(' ');
        sendMessage('console_log', msg);
      },
      error: function() {
        var msg = Array.prototype.slice.call(arguments).map(function(v) {
          try { return typeof v === 'object' ? JSON.stringify(v) : String(v); } catch(e) { return "[Object]"; }
        }).join(' ');
        sendMessage('console_error', msg);
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
      sendMessage('clear_timeout', id);
    };
  ''');
  print('  基础环境注入完成');
}

void _setupLx(JavascriptRuntime runtime) {
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

  // 桥接 lx.request - 真实 HTTP 请求
  runtime.onMessage('lx_request', (dynamic args) async {
    try {
      final data = (args is String)
          ? json.decode(args) as Map<String, dynamic>
          : args as Map<String, dynamic>;
      final url = data['url'] as String;
      final options = data['options'] as Map<String, dynamic>?;
      final callbackId = data['callbackId'] as String;
      print('  [lx_request] url=$url');
      if (options?['headers'] != null) {
        print('  [lx_request] headers=${options!['headers']}');
      }

      final client = HttpClient();
      try {
        final req = await client.openUrl('GET', Uri.parse(url));
        final headers = options?['headers'] as Map<String, dynamic>?;
        if (headers != null) {
          headers.forEach((k, v) {
            try { req.headers.set(k, v.toString()); } catch (_) {}
          });
        }
        final response = await req.close().timeout(const Duration(seconds: 15));
        final rawBody = await response.transform(utf8.decoder).join();
        print('  [lx_request] 响应 status=${response.statusCode}, body 长度=${rawBody.length}');

        // 自动 JSON 解析
        dynamic body = rawBody;
        final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
        if (contentType.contains('application/json') || (rawBody is String && rawBody.trim().startsWith('{'))) {
          try { body = json.decode(rawBody); }
          catch (_) { body = rawBody; }
        }

        _executeCallback(runtime, callbackId, null, {
          'statusCode': response.statusCode,
          'body': body,
          'headers': {},
        }, body);
      } catch (e) {
        print('  [lx_request] 错误: $e');
        _executeCallback(runtime, callbackId, e.toString(), null, null);
      } finally {
        client.close();
      }
    } catch (e) {
      print('  [lx_request 解析错误] $e');
    }
  });

  // 注入 lx 全局对象
  runtime.evaluate(r'''
    globalThis.lx = {
      version: '2.0.0',
      env: 'desktop',
      EVENT_NAMES: {
        request: 'request',
        inited: 'inited',
        updateAlert: 'updateAlert'
      },
      request: function(url, options, callback) {
        if (typeof options === 'function') { callback = options; options = {}; }
        if (typeof globalThis._pendingRequests === 'undefined') {
          globalThis._pendingRequests = 0;
        }
        var requestInternal = function(cb) {
          var callbackId = 'cb_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
          globalThis._callbacks[callbackId] = function(err, res, body) {
            if (res && res.body && options.binary) {
              res.body = globalThis.lx.utils.buffer.from(res.body, 'base64');
            }
            try { cb(err, res, body || (res ? res.body : null)); }
            finally { globalThis._pendingRequests--; }
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
              } else {
                try { str = unescape(encodeURIComponent(data)); } catch (e) { str = data; }
              }
            } else if (data && typeof data.length === 'number') {
              for (var i = 0; i < data.length; i++) {
                var c = data[i];
                str += String.fromCharCode(typeof c === 'number' ? c : 0);
              }
            }
            var b = {
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
                if (enc === 'utf8' || enc === 'utf-8' || !enc) {
                  try { return decodeURIComponent(escape(this._str)); } catch (e) { return this._str; }
                }
                return this._str;
              }
            };
            return b;
          },
          bufToString: function(buffer, encoding) { return (buffer && buffer.toString) ? buffer.toString(encoding) : buffer; }
        },
        crypto: {
          md5: function(str) {
            if (globalThis._md5) return globalThis._md5(str);
            return '';
          }
        }
      },
      currentScriptInfo: {}
    };
    globalThis._md5 = function(string) {
      // 简单的 mock MD5 (返回空字符串)
      // 野花音源脚本对 m 字段判断有 rawScript.trim() 不相等会 throw，
      // 真实服务时需要正确实现
      return '';
    };
  ''');
  print('  lx 注入完成');
}

void _executeCallback(JavascriptRuntime runtime, String callbackId, String? err, Map<String, dynamic>? res, dynamic body) {
  final args = [err, res, body];
  final argsJson = json.encode(args);
  final varName = 'temp_args_${DateTime.now().millisecondsSinceEpoch}_${callbackId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
  runtime.evaluate('globalThis.$varName = $argsJson;');
  runtime.evaluate('''
    (function() {
      var cb = globalThis._callbacks['$callbackId'];
      if (cb) {
        cb.apply(null, globalThis.$varName);
        delete globalThis._callbacks['$callbackId'];
      }
      delete globalThis.$varName;
    })()
  ''');
  // flush microtask
  for (int i = 0; i < 32; i++) {
    final check = runtime.evaluate('(globalThis._pendingRequests || 0)');
    final pending = check.rawResult;
    if (pending is int && pending <= 0) {
      for (int j = 0; j < 3; j++) runtime.evaluate('void 0;');
      break;
    }
    runtime.evaluate('void 0;');
  }
}

Future<Map<String, dynamic>?> _callRequest(JavascriptRuntime runtime, Map<String, dynamic> params) async {
  final Completer<Map<String, dynamic>?> completer = Completer();
  final reqId = 'req_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';
  final paramsJson = json.encode(params);
  final varName = 'temp_params_${reqId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
  runtime.evaluate('globalThis.$varName = $paramsJson;');

  runtime.onMessage('lx_response', (dynamic args) {
    try {
      final data = (args is String)
          ? json.decode(args) as Map<String, dynamic>
          : args as Map<String, dynamic>;
      if (data['reqId'] == reqId) {
        if (data['error'] != null) {
          print('  [lx_response] 错误: ${data['error']}');
          if (!completer.isCompleted) completer.complete(null);
        } else {
          if (!completer.isCompleted) completer.complete(data['data'] as Map<String, dynamic>);
        }
      }
    } catch (e) { /* ignore */ }
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
  runtime.evaluate(script);

  // flush microtask
  for (int i = 0; i < 32; i++) {
    final check = runtime.evaluate('(globalThis._pendingRequests || 0)');
    final pending = check.rawResult;
    if (pending is int && pending <= 0) {
      for (int j = 0; j < 3; j++) runtime.evaluate('void 0;');
      break;
    }
    runtime.evaluate('void 0;');
  }

  return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
    print('  请求超时 (30秒)');
    return null;
  });
}
