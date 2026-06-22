import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:pointycastle/export.dart' as pc;
import '../domain/custom_source.dart';
import '../../player/domain/music_item.dart';

Map<String, dynamic> _decodeMap(String s) => json.decode(s) as Map<String, dynamic>;
dynamic _decodeDynamic(String s) => json.decode(s);

class CustomSourceEngine {
  JavascriptRuntime? _runtime;
  final Dio _dio = Dio();
  CustomSource? _currentSource;
  bool _initialized = false;
  final _uuid = const Uuid();
  final StreamController<Map<String, dynamic>> _eventController = StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, Completer<dynamic>> _pendingRequests = {};
  final Map<String, String> _requestUrls = {}; // 调试：记录 callbackId -> url
  Completer<void>? _initCompleter;

  CustomSourceEngine() {
    // 延迟初始化，避免在构造函数中阻塞 UI 线程
    // _initRuntime(); 
  }

  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  Future<void> _ensureInitialized() async {
    if (_initialized && _runtime != null) return;
    
    // 给 UI 线程一个机会去渲染（如显示加载动画）
    await Future.delayed(Duration.zero);

    try {
      _runtime = getJavascriptRuntime();
      _setupBaseEnvironment();
      _initialized = true;
    } catch (e) {
      _initialized = false;
    }
  }

  void _setupBaseEnvironment() {
    if (_runtime == null) return;

    // 保存原始的 sendMessage 函数，用于在加载脚本时缓冲消息，避免 iOS 平台通道死锁
    _runtime!.evaluate('globalThis._originalSendMessage = globalThis.sendMessage;');

    // 1. Console & Environment 桥接
    _runtime!.evaluate('''
      // 关键修复：flutter_js 的 JSC 端 _sendMessage 内部会 jsonDecode(message)，
      // 如果 message 不是合法 JSON，整个 _sendMessage 会抛 native 异常。
      // 必须用 JSON.stringify 包装所有 sendMessage 的 message 参数。
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
      
      globalThis.window = globalThis;
      globalThis.process = { env: { NODE_ENV: 'production' } };
      globalThis.navigator = { userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' };
      
      // 关键修复：使用数字 id (Date.now() + counter) 而不是字符串，
      // 这样脚本里 `clearTimeout(id)` 能用相等的 id 准确取消回调。
      // 字符串 id 在某些边界情况下（如 setTimeout 内部把 id 存到 Set/Map
      // 时）会失配。
      globalThis._timeoutCounter = 0;
      globalThis.setTimeout = function(fn, ms) {
        globalThis._timeoutCounter = (globalThis._timeoutCounter || 0) + 1;
        var id = Date.now() + globalThis._timeoutCounter;
        globalThis._callbacks['timeout_' + id] = fn;
        sendMessage('set_timeout', JSON.stringify({ id: id, ms: ms || 0 }));
        return id;
      };

      globalThis.clearTimeout = function(id) {
        // 同时清掉 _callbacks 里的字符串 key 与 Dart 端的 Future
        if (globalThis._callbacks) delete globalThis._callbacks['timeout_' + id];
        sendMessage('clear_timeout', id);
      };

      (function() {
        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        globalThis.atob = globalThis.atob || function(input) {
          var str = String(input).replace(/[=]+\$/, '');
          for (var bc = 0, bs, buffer, idx = 0, output = ''; buffer = str.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
            buffer = chars.indexOf(buffer);
          }
          return output;
        };
        globalThis.btoa = globalThis.btoa || function(input) {
          var str = String(input);
          for (var block, charCode, idx = 0, map = chars, output = ''; str.charAt(idx | 0) || (map = '=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
            charCode = str.charCodeAt(idx += 3 / 4);
            if (charCode > 0xFF) throw new Error("'btoa' failed");
            block = block << 8 | charCode;
          }
          return output;
        };
      })();
    ''');

    _runtime!.onMessage('set_timeout', (dynamic args) {
      final data = json.decode(args);
      final id = data['id'];
      final ms = data['ms'] as int;
      Future.delayed(Duration(milliseconds: ms), () {
        if (_runtime != null) {
          // 修复：id 是数字，必须拼成 'timeout_'+id 字符串 key 才能正确
          // 取到 _callbacks 里的回调。clearTimeout 已经把 callback 删了，
          // 所以这里再次 delete 是 no-op，安全。
          _runtime!.evaluate('if(globalThis._callbacks["timeout_$id"]) { globalThis._callbacks["timeout_$id"](); delete globalThis._callbacks["timeout_$id"]; }');
          // 推动 microtask 队列（例如 setTimeout 回调里再 await lx.request）
          _flushMicrotasks(maxIterations: 4);
        }
      });
    });
    _runtime!.onMessage('clear_timeout', (dynamic id) {
      // 同步清掉 JS 端 callbacks（防止 timeout 触发时重复调用）
      if (_runtime != null) {
        _runtime!.evaluate('if(globalThis._callbacks) delete globalThis._callbacks["timeout_$id"];');
      }
    });
    _runtime!.onMessage('console_log', (msg) {
      _eventController.add({'type': 'log', 'message': msg});
    });
    _runtime!.onMessage('console_error', (msg) {
      _eventController.add({'type': 'error', 'message': msg});
    });

    // 2. HTTP 桥接 (lx.request)
    _runtime!.onMessage('lx_request', (dynamic args) async {
      Map<String, dynamic> data;
      try {
        if (args is String) {
          final String argsStr = args;
          data = argsStr.length > 10000 
            ? await compute<String, Map<String, dynamic>>(_decodeMap, argsStr)
            : json.decode(argsStr) as Map<String, dynamic>;
        } else {
          data = args;
        }
      } catch (e) {
        return;
      }

      final String callbackId = data['callbackId'];
      final String url = data['url'];
      final Map<String, dynamic> options = data['options'] ?? {};
      _requestUrls[callbackId] = url; // 记录 URL 用于调试

      try {
        final isBinary = options['binary'] == true;
        
        // 提取并处理 params (Query Parameters)
        Map<String, dynamic>? queryParams;
        if (options['params'] != null && options['params'] is Map) {
          queryParams = Map<String, dynamic>.from(options['params']);
        }

        final response = await _makeHttpRequest(
          url, 
          options, 
          isBinary: isBinary, 
          queryParams: queryParams
        );
        
        dynamic body;
        if (isBinary) {
          body = base64Encode(response.data as List<int>);
        } else {
          body = response.data;
          // 优化 JSON 自动解析逻辑
          final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
          if (options['json'] == true || contentType.contains('application/json') || (body is String && body.trim().startsWith('{'))) {
            if (body is String && body.isNotEmpty) {
              final String bodyStr = body;
              try {
                if (bodyStr.length > 50000) {
                  final dynamic decoded = await compute<String, dynamic>(_decodeDynamic, bodyStr);
                  body = decoded;
                } else {
                  body = json.decode(bodyStr);
                }
              } catch (e) {
                // 忽略解析错误，保持原始字符串
              }
            }
          }
        }

        final Map<String, String> flatHeaders = {};
        response.headers.forEach((name, values) {
          flatHeaders[name.toLowerCase()] = values.join(', ');
        });

        _executeJsCallback(callbackId, [
          null,
          {
            'statusCode': response.statusCode,
            'body': body,
            'headers': flatHeaders
          },
          body // 桌面版支持第三个参数直接传 body
        ], url: url);
      } catch (e) {
        _executeJsCallback(callbackId, [e.toString(), null, null], url: url);
      }
    });

    _runtime!.onMessage('lx_send', (dynamic args) async {
      Map<String, dynamic> data;
      try {
        if (args is String) {
          final String argsStr = args;
          data = argsStr.length > 10000 
            ? await compute<String, Map<String, dynamic>>(_decodeMap, argsStr)
            : json.decode(argsStr) as Map<String, dynamic>;
        } else {
          data = args;
        }
      } catch (e) {
        return;
      }

      final String? event = data['event'];
      if (event == 'inited') {
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.complete();
        }
      }
      _eventController.add({'type': 'event', 'event': event, 'data': data['data']});
    });

    _runtime!.onMessage('lx_response', (dynamic args) async {
      try {
        Map<String, dynamic> data;
        if (args is String) {
          final String argsStr = args;
          data = argsStr.length > 10000
            ? await compute<String, Map<String, dynamic>>(_decodeMap, argsStr)
            : json.decode(argsStr) as Map<String, dynamic>;
        } else {
          data = args;
        }

        final String? reqId = data['reqId'];
        final dynamic result = data['data'];
        final String? error = data['error'];

        if (reqId != null && _pendingRequests.containsKey(reqId)) {
          final completer = _pendingRequests.remove(reqId);
          if (error != null) {
            completer?.completeError(error);
          } else {
            completer?.complete(result);
          }
        }
      } catch (e) {
        // 解析错误，忽略
      }
      // 让后续可能的 microtask (例如 lx.send 或 console) 跑掉
      _flushMicrotasks();
    });

    // 3. Crypto 桥接 (lx.utils.crypto)
    _runtime!.onMessage('lx_crypto', (dynamic args) {
      final Map<String, dynamic> data = (args is String) ? json.decode(args) : args;
      final String method = data['method'];
      final dynamic input = data['input'];

      try {
        if (method == 'md5') {
          return md5.convert(utf8.encode(input.toString())).toString();
        }
        if (method == 'aesEncrypt') {
          final dynamic inputData = data['input'];
          List<int> inputBytes;
          if (inputData is String) {
            // 如果是合法的 Base64 则解码，否则按 UTF8 编码
            try {
              inputBytes = (inputData.length % 4 == 0 && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(inputData))
                ? base64Decode(inputData)
                : utf8.encode(inputData);
            } catch (_) {
              inputBytes = utf8.encode(inputData);
            }
          } else {
            inputBytes = utf8.encode(inputData.toString());
          }
          
          final String mode = data['mode'] ?? 'aes-128-cbc';
          final String keyText = data['key'] ?? '';
          final String ivText = data['iv'] ?? '';

          final key = encrypt_lib.Key.fromUtf8(keyText.padRight(16, '\x00').substring(0, 16));
          final iv = encrypt_lib.IV.fromUtf8(ivText.padRight(16, '\x00').substring(0, 16));
          
          final aesMode = mode.toLowerCase().contains('cbc') 
              ? encrypt_lib.AESMode.cbc 
              : encrypt_lib.AESMode.ecb;

          final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: aesMode));
          // 桌面版返回的是 Buffer，这里对应 Base64
          final encrypted = encrypter.encryptBytes(inputBytes, iv: iv);
          return encrypted.base64;
        }
        if (method == 'rsaEncrypt') {
          final dynamic inputData = data['input'];
          final List<int> inputBytes = (inputData is String && inputData.length % 4 == 0)
              ? base64Decode(inputData)
              : utf8.encode(inputData.toString());
          
          final String publicKey = data['key'] ?? '';
          final parser = encrypt_lib.RSAKeyParser();
          final pc.RSAPublicKey key = parser.parse(publicKey) as pc.RSAPublicKey;
          
          // 对齐桌面版：真正的 RSA_NO_PADDING 实现。
          // 输入必须是 128 字节，直接进行模幂运算。
          List<int> paddedBytes = inputBytes;
          if (paddedBytes.length < 128) {
            paddedBytes = List<int>.filled(128 - paddedBytes.length, 0) + paddedBytes;
          } else if (paddedBytes.length > 128) {
            paddedBytes = paddedBytes.sublist(paddedBytes.length - 128);
          }
          
          // 使用 PointyCastle 进行模幂运算 (RSA_NO_PADDING)
          final engine = pc.RSAEngine()
            ..init(true, pc.PublicKeyParameter<pc.RSAPublicKey>(key));
          final encrypted = engine.process(Uint8List.fromList(paddedBytes));
          
          return base64Encode(encrypted);
        }
      } catch (e) {
        // crypto error, return empty
      }
      return '';
    });

    // 4. Zlib 桥接 (lx.utils.zlib)
    _runtime!.onMessage('lx_zlib', (dynamic args) {
      try {
        final Map<String, dynamic> data = (args is String) ? json.decode(args) : args;
        final String method = data['method'];
        final String inputBase64 = data['data'] ?? '';
        final List<int> inputBytes = base64Decode(inputBase64);

        if (method == 'inflate') {
          final inflated = ZLibCodec().decode(inputBytes);
          return base64Encode(inflated);
        }
        if (method == 'deflate') {
          final deflated = ZLibCodec().encode(inputBytes);
          return base64Encode(deflated);
        }
      } catch (e) {
        // zlib error, return empty
      }
      return '';
    });

    // 4. 事件回调桥接已在前面定义，此处移除冗余

    // 5. 初始化核心 JS 环境
    _runtime!.evaluate(r'''
      var globalThis = globalThis || window || {};
      
      (function() {
        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        globalThis.btoa = globalThis.btoa || function(input) {
          var str = String(input);
          for (var block, charCode, idx = 0, map = chars, output = ''; str.charAt(idx | 0) || (map = '=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
            charCode = str.charCodeAt(idx += 3 / 4);
            if (charCode > 0xFF) throw new Error("'btoa' failed");
            block = block << 8 | charCode;
          }
          return output;
        };
        globalThis.atob = globalThis.atob || function(input) {
          var str = String(input).replace(/[=]+$/, '');
          for (var bc = 0, bs, buffer, idx = 0, output = ''; buffer = str.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
            buffer = chars.indexOf(buffer);
          }
          return output;
        };
      })();

      (function() {
        function md5(string) {
          function md5_Cycle(x, k) {
            var a = x[0], b = x[1], c = x[2], d = x[3];
            a = ff(a, b, c, d, k[0], 7, -680876936);
            d = ff(d, a, b, c, k[1], 12, -389564586);
            c = ff(c, d, a, b, k[2], 17, 606105819);
            b = ff(b, c, d, a, k[3], 22, -1044525330);
            a = ff(a, b, c, d, k[4], 7, -176418897);
            d = ff(d, a, b, c, k[5], 12, 1200080426);
            c = ff(c, d, a, b, k[6], 17, -1473231341);
            b = ff(b, c, d, a, k[7], 22, -45705983);
            a = ff(a, b, c, d, k[8], 7, 1770035416);
            d = ff(d, a, b, c, k[9], 12, -1958414417);
            c = ff(c, d, a, b, k[10], 17, -42063);
            b = ff(b, c, d, a, k[11], 22, -1990404162);
            a = ff(a, b, c, d, k[12], 7, 1804603682);
            d = ff(d, a, b, c, k[13], 12, -40341101);
            c = ff(c, d, a, b, k[14], 17, -1502002290);
            b = ff(b, c, d, a, k[15], 22, 1236535329);
            a = gg(a, b, c, d, k[1], 5, -165796510);
            d = gg(d, a, b, c, k[6], 9, -1069501632);
            c = gg(c, d, a, b, k[11], 14, 643717713);
            b = gg(b, c, d, a, k[0], 20, -373897302);
            a = gg(a, b, c, d, k[5], 5, -701558691);
            d = gg(d, a, b, c, k[10], 9, 38016083);
            c = gg(c, d, a, b, k[15], 14, -660478335);
            b = gg(b, c, d, a, k[4], 20, -405537848);
            a = gg(a, b, c, d, k[9], 5, 568446438);
            d = gg(d, a, b, c, k[14], 9, -1019803690);
            c = gg(c, d, a, b, k[3], 14, -187363961);
            b = gg(b, c, d, a, k[8], 20, 1163531501);
            a = gg(a, b, c, d, k[13], 5, -1444681467);
            d = gg(d, a, b, c, k[2], 9, -51403784);
            c = gg(c, d, a, b, k[7], 14, 1735328473);
            b = gg(b, c, d, a, k[12], 20, -1926607734);
            a = hh(a, b, c, d, k[5], 4, -378558);
            d = hh(d, a, b, c, k[8], 11, -2022574463);
            c = hh(c, d, a, b, k[11], 16, 1839030562);
            b = hh(b, c, d, a, k[14], 23, -35309556);
            a = hh(a, b, c, d, k[1], 4, -1530992060);
            d = hh(d, a, b, c, k[4], 11, 1272893353);
            c = hh(c, d, a, b, k[7], 16, -155497632);
            b = hh(b, c, d, a, k[10], 23, -1094730640);
            a = hh(a, b, c, d, k[13], 4, 681279174);
            d = hh(d, a, b, c, k[0], 11, -358537222);
            c = hh(c, d, a, b, k[3], 16, -722521979);
            b = hh(b, c, d, a, k[6], 23, 76029189);
            a = hh(a, b, c, d, k[9], 4, -640364487);
            d = hh(d, a, b, c, k[12], 11, -421815835);
            c = hh(c, d, a, b, k[15], 16, 530742520);
            b = hh(b, c, d, a, k[2], 23, -995338651);
            a = ii(a, b, c, d, k[0], 6, -198630844);
            d = ii(d, a, b, c, k[7], 10, 1126891415);
            c = ii(c, d, a, b, k[14], 15, -1416354905);
            b = ii(b, c, d, a, k[5], 21, -57434055);
            a = ii(a, b, c, d, k[12], 6, 1700485571);
            d = ii(d, a, b, c, k[3], 10, -1894986606);
            c = ii(c, d, a, b, k[10], 15, -1051523);
            b = ii(b, c, d, a, k[1], 21, -2054922799);
            a = ii(a, b, c, d, k[8], 6, 1873313359);
            d = ii(d, a, b, c, k[15], 10, -30611744);
            c = ii(c, d, a, b, k[6], 15, -1560198380);
            b = ii(b, c, d, a, k[13], 21, 1309151649);
            a = ii(a, b, c, d, k[4], 6, -145523070);
            d = ii(d, a, b, c, k[11], 10, -1120210379);
            c = ii(c, d, a, b, k[2], 15, 718787280);
            b = ii(b, c, d, a, k[9], 21, -343485551);
            state[0] = a + state[0] | 0;
            state[1] = b + state[1] | 0;
            state[2] = c + state[2] | 0;
            state[3] = d + state[3] | 0;
          }
          function ff(a, b, c, d, x, s, t) { a = a + (b & c | ~b & d) + x + t | 0; return (a << s | a >>> 32 - s) + b | 0; }
          function gg(a, b, c, d, x, s, t) { a = a + (b & d | c & ~d) + x + t | 0; return (a << s | a >>> 32 - s) + b | 0; }
          function hh(a, b, c, d, x, s, t) { a = a + (b ^ c ^ d) + x + t | 0; return (a << s | a >>> 32 - s) + b | 0; }
          function ii(a, b, c, d, x, s, t) { a = a + (c ^ (b | ~d)) + x + t | 0; return (a << s | a >>> 32 - s) + b | 0; }
          var n = string.length, state = [1732584193, -271733879, -1732584194, 271733878], i;
          var words = [];
          for (i = 0; i < n; i++) words[i >> 2] |= string.charCodeAt(i) << (i % 4 << 3);
          words[n >> 2] |= 0x80 << (n % 4 << 3);
          words[(n + 8 >> 6 << 4) + 14] = n << 3;
          for (i = 0; i < words.length; i += 16) md5_Cycle(state, words.slice(i, i + 16));
          var hex = "";
          for (i = 0; i < 4; i++) {
            var val = state[i];
            for (var j = 0; j < 4; j++) {
              var b = (val >> (j * 8)) & 0xFF;
              hex += (b < 16 ? "0" : "") + b.toString(16);
            }
          }
          return hex;
        }
        globalThis._md5 = md5;
      })();

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
          if (options.form && !options.body) options.body = options.form; 

          // 记录请求 URL 以便调试
          if (url.indexOf('http') !== 0 && globalThis.lx.currentScriptInfo && globalThis.lx.currentScriptInfo.baseUrl) {
             // 某些脚本可能使用相对路径（虽然少见）
          }

          if (typeof globalThis._pendingRequests === 'undefined') {
            globalThis._pendingRequests = 0;
          }

          var requestInternal = function(cb) {
              var callbackId = 'cb_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
              globalThis._callbacks[callbackId] = function(err, res, body) {
                if (res && res.body && options.binary) {
                  res.body = globalThis.lx.utils.buffer.from(res.body, 'base64');
                }
                if (err) console.error('[JS Debug] Request Error: ' + url + ' -> ' + (err.message || err));
                else if (res) console.log('[JS Debug] Request Success: ' + url + ' [' + res.statusCode + ']');

                // 回调处理兼容：某些旧脚本可能只期望 (body) 或 (res, body)
                // 桌面版 preload.js 实现是 (err, res, body)
                try { 
                  if (typeof callback === 'function') {
                    if (callback.length === 1) callback(body || (res ? res.body : null));
                    else if (callback.length === 2) callback(res, body || (res ? res.body : null));
                    else callback(err, res, body || (res ? res.body : null));
                  }
                  cb(err, res, body || (res ? res.body : null)); 
                }
                finally { globalThis._pendingRequests--; }
              };
              globalThis._pendingRequests++;
              sendMessage('lx_request', JSON.stringify({ url: url, options: options, callbackId: callbackId }));
              return function() { /* abort not implemented */ };
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
          console.log('JS Debug: lx.on called for event: ' + eventName);
          if (!globalThis._eventHandlers) globalThis._eventHandlers = {};
          if (!globalThis._eventHandlers[eventName]) globalThis._eventHandlers[eventName] = [];
          globalThis._eventHandlers[eventName].push(handler);
        },
        utils: {
          buffer: {
            from: function(data, encoding) {
              if (data && data._isBuffer) return data;
              var str = '';
              if (typeof data === 'string') {
                if (encoding === 'hex') {
                  for (var i = 0; i < data.length; i += 2) str += String.fromCharCode(parseInt(data.substr(i, 2), 16));
                } else if (encoding === 'base64') {
                  str = globalThis.atob(data);
                } else {
                  try {
                    str = unescape(encodeURIComponent(data));
                  } catch (e) {
                    str = data;
                  }
                }
              } else if (data && typeof data.length === 'number') {
                for (var i = 0; i < data.length; i++) {
                  var c = data[i];
                  str += String.fromCharCode(typeof c === 'number' ? c : 0);
                }
              }
              
              var b = {
                _str: str,
                _isBuffer: true,
                length: str.length,
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
                    try {
                      return decodeURIComponent(escape(this._str));
                    } catch (e) {
                      return this._str;
                    }
                  }
                  return this._str;
                },
                slice: function(s, e) { return globalThis.lx.utils.buffer.from(this._str.slice(s, e)); },
                equals: function(other) { return other && other._str === this._str; },
                toJSON: function() { return this.toString('base64'); }
              };
              // 添加索引访问支持
              for (var i = 0; i < str.length; i++) {
                (function(idx) {
                  Object.defineProperty(b, idx, {
                    get: function() { return str.charCodeAt(idx); },
                    enumerable: true,
                    configurable: true
                  });
                })(i);
              }
              return b;
            },
            alloc: function(size, fill) {
              var str = '';
              var fillChar = "\0";
              if (fill !== undefined) {
                if (typeof fill === 'string') fillChar = fill[0] || "\0";
                else if (typeof fill === 'number') fillChar = String.fromCharCode(fill);
              }
              for (var i = 0; i < size; i++) str += fillChar;
              return globalThis.lx.utils.buffer.from(str);
            },
            concat: function(list, totalLength) {
              if (!Array.isArray(list)) throw new TypeError('list must be an Array');
              var str = '';
              for (var i = 0; i < list.length; i++) {
                var item = list[i];
                if (typeof item === 'string') str += item;
                else if (item && (item._str !== undefined)) str += item._str;
              }
              if (totalLength !== undefined && str.length > totalLength) str = str.slice(0, totalLength);
              return globalThis.lx.utils.buffer.from(str);
            },
            bufToString: function(buffer, encoding) { return (buffer && buffer.toString) ? buffer.toString(encoding) : buffer; }
          },
          crypto: {
            md5: function(str) {
              if (globalThis._md5) return globalThis._md5(str);
              console.error('Crypto error: _md5 not found');
              return "";
            },
            aesEncrypt: function(data, mode, key, iv) {
              return sendMessage('lx_crypto', JSON.stringify({ method: 'aesEncrypt', input: data, mode: mode, key: key, iv: iv }));
            },
            rsaEncrypt: function(data, key) {
              return sendMessage('lx_crypto', JSON.stringify({ method: 'rsaEncrypt', input: data, key: key }));
            }
          }
        },
        env: 'desktop', version: '2.0.0',        currentScriptInfo: { rawScript: '' }
      };
      globalThis.lx.utils.zlib = {
        inflate: function(buf) { return sendMessage('lx_zlib', JSON.stringify({ method: 'inflate', data: buf.toString('base64') })); },
        deflate: function(data) { return sendMessage('lx_zlib', JSON.stringify({ method: 'deflate', data: data })); }
      };
      globalThis.lx.utils.crypto.randomBytes = function(size) {
        var bytes = [];
        for (var i = 0; i < size; i++) bytes.push(Math.floor(Math.random() * 256));
        return globalThis.lx.utils.buffer.from(bytes);
      };
      globalThis.Buffer = globalThis.lx.utils.buffer;
      globalThis._callbacks = {};
      globalThis._eventHandlers = { 'request': [] };
      globalThis._initComplete = false;
    ''');
  }

  void _executeJsCallback(String callbackId, List<dynamic> args, {String? url}) {
    // 使用变量注入机制传递参数，避免在 evaluate 时解析超长字符串导致主线程卡死
    final argsJson = json.encode(args);
    final varName = 'temp_args_${DateTime.now().millisecondsSinceEpoch}_${callbackId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';

    _runtime!.evaluate('globalThis.$varName = $argsJson;');

    _runtime!.evaluate('''
      (function() {
        var cb = globalThis._callbacks['$callbackId'];
        if (cb) {
          cb.apply(null, globalThis.$varName);
          delete globalThis._callbacks['$callbackId'];
        }
        delete globalThis.$varName;
      })()
    ''');

    // 关键修复：flutter_js 的 evaluate 不会自动 flush JS microtask 队列。
    // cb.apply 内部 resolve 了 await lx.request() 的 promise，但后续代码
    // (例如 sendMessage('lx_response', ...) 仍然在 microtask 队列里) 不会
    // 被自动执行。这里通过 evaluate 一个简单的循环让 QuickJS 跑 microtask，
    // 直到队列清空或达到最大轮询次数。
    _flushMicrotasks();
  }

  /// 反复 evaluate 极简表达式以触发 QuickJS 内部的 microtask flush。
  /// 必须在异步回调（如 _executeJsCallback / onMessage）末尾调用，
  /// 否则 await 链无法推进、`sendMessage('lx_response', ...)` 等消息
  /// 永远不会发出，导致 _callRequestEvent 15 秒超时。
  void _flushMicrotasks({int maxIterations = 64}) {
    if (_runtime == null) return;
    for (int i = 0; i < maxIterations; i++) {
      try {
        // 检查 JS 端维护的 pending request 计数器。
        // 只要还有未完成的 lx.request，就继续推 noop 让 QuickJS
        // 跑 microtask。
        final checkResult = _runtime!.evaluate(
          '(globalThis._pendingRequests || 0)',
        );
        final pending = checkResult.rawResult;
        if (pending is int && pending <= 0) {
          // 没有 pending request 了，再多 evaluate 几次让 microtask 队列跑空
          // (例如 lx_response 的 sendMessage 也是 microtask 调度)
          for (int j = 0; j < 3; j++) {
            _runtime!.evaluate('void 0;');
          }
          break;
        }

        // 推一个 noop 表达式，让 QuickJS 进入事件循环
        _runtime!.evaluate('void 0;');
      } catch (_) {
        break;
      }
    }
  }

  Future<bool> loadSource(CustomSource source) async {
    final stopwatch = Stopwatch()..start();
    // 1. 如果脚本内容没变且已初始化，直接返回成功，避免重复执行导致的变量冲突
    if (_initialized && _currentSource?.script == source.script) {
      return true;
    }

    // 2. 切换脚本或重新加载时，必须销毁旧引擎以彻底清理内存和全局变量声明
    if (_runtime != null) {
      _runtime!.dispose();
      _runtime = null;
      _initialized = false;
    }

    // 3. 重新初始化基础环境
    await _ensureInitialized();
    if (!_initialized || _runtime == null) return false;

    try {
      _currentSource = source;
      _initCompleter = Completer<void>();
      final scriptInfo = {
        'id': source.id,
        'name': source.name,
        'description': source.description,
        'version': source.version,
        'author': source.author,
        'homepage': source.homepage ?? '',
        'rawScript': '', // 占位
      };
      
      // 1. 先注入基础信息
      _runtime!.evaluate('globalThis.lx.currentScriptInfo = ${json.encode(scriptInfo)};');
      
      // 2. 尝试注入完整的 rawScript (使用特殊变量绕过某些解析限制)
      final encodedScript = json.encode(source.script);
      final rawScriptResult = _runtime!.evaluate('globalThis.lx.currentScriptInfo.rawScript = $encodedScript;');
      
      if (rawScriptResult.isError) {
        // rawScript injection failed (possibly too large)
      }
      
      // 3. 执行新脚本
      
      // 在 iOS / JSC 引擎上，如果在同步 evaluate 时触发 JS-to-Dart 的 sendMessage 回调，
      // 可能会由于 MethodChannel 在主线程同步阻塞导致死锁（JSC 试图回调，而 Dart UI 线程在等待 evaluate 结果）。
      // 因此我们在 evaluate 期间缓冲所有非同步的 sendMessage 调用（如 console.log, lx.send('inited')），
      // 等 evaluate 结束后再统一播放。这能彻底解决 iOS 上的死锁卡死问题。
      _runtime!.evaluate(r'''
        globalThis._frozenMessages = [];
        globalThis.sendMessage = function(channel, message) {
          if (channel === 'lx_crypto') {
            return globalThis._originalSendMessage(channel, message);
          }
          globalThis._frozenMessages.push({ channel: channel, message: message });
        };
      ''');

      final evalStopwatch = Stopwatch()..start();

      // 在 JS 端包裹一层 try-catch 以捕获同步执行期间的错误
      final wrapperScript = '(function() {\n'
          '  try {\n'
          '    console.log("JS Debug: Custom script execution STARTING...");\n'
          '    ' + source.script + '\n'
          '    console.log("JS Debug: Custom script executed SUCCESSFULY to the end.");\n'
          '  } catch (e) {\n'
          '    console.error("JS Debug: Script execution CRASHED: " + e.message + (e.stack ? "\\n" + e.stack : ""));\n'
          '  }\n'
          '})();';
      
      final result = _runtime!.evaluate(wrapperScript);
      evalStopwatch.stop();

      // 无论 evaluate 是否成功，都必须恢复原始的 sendMessage 并放行/重播缓冲的消息
      final thawResult = _runtime!.evaluate(r'''
        (function() {
          var msgs = globalThis._frozenMessages || [];
          globalThis.sendMessage = globalThis._originalSendMessage || globalThis.sendMessage;
          delete globalThis._frozenMessages;
          // 调试：打印缓冲的消息列表
          var summary = [];
          for (var i = 0; i < msgs.length; i++) {
            var ch = msgs[i].channel;
            var preview = String(msgs[i].message).substring(0, 120);
            summary.push(ch + ':' + preview);
          }
          console.log('[DEBUG thaw] frozen messages count=' + msgs.length + ' channels=' + JSON.stringify(summary));
          for (var i = 0; i < msgs.length; i++) {
            try {
              globalThis.sendMessage(msgs[i].channel, msgs[i].message);
            } catch(e) {
              console.error('[DEBUG thaw] replay error channel=' + msgs[i].channel + ' err=' + e.message);
            }
          }
          console.log('[DEBUG thaw] replay done');
          return 'thaw_ok';
        })()
      ''');

      if (result.isError) {
        return false;
      }

      // 5. 等待脚本内部完成 lx.send('inited')。
      // 关键修复：5 秒太短，复杂脚本需要更多时间做 token 拉取 / setTimeout
      // 初始化。同时在等待期间定期 flush microtask，确保脚本里 setTimeout
      // 链上的 lx.send('inited') 能被调度。
      final initTimeout = const Duration(seconds: 30);
      final deadline = DateTime.now().add(initTimeout);
      while (!_initCompleter!.isCompleted && DateTime.now().isBefore(deadline)) {
        // 轮询 flush microtask，让 setTimeout 链上的 lx.send('inited') 跑掉
        _flushMicrotasks(maxIterations: 4);
        try {
          await _initCompleter!.future.timeout(const Duration(milliseconds: 500));
          break;
        } catch (_) {
          // 500ms 内没完成就继续轮询
        }
      }
      if (_initCompleter!.isCompleted) {
        // JS init complete
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<dynamic> _callRequestEvent(Map<String, dynamic> params) async {
    final action = params['action'];

    await _ensureInitialized();
    if (_runtime == null || !_initialized) {
      _eventController.add({'type': 'error', 'message': '引擎未初始化或已销毁'});
      return null;
    }
    
    final String reqId = 'req_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 4)}';
    final paramsJson = json.encode(params);
    final varName = 'temp_params_${reqId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
    
    // 使用变量注入防止大 JSON 字符串在 evaluate 时导致卡顿
    _runtime!.evaluate('globalThis.$varName = $paramsJson;');

    final completer = Completer<dynamic>();
    _pendingRequests[reqId] = completer;

    final script = '''
      (async function() {
        try {
          var params = globalThis.$varName;
          delete globalThis.$varName;
          var action = params.action;
          var reqId = ${json.encode(reqId)};
          
          if (!globalThis._eventHandlers) {
             sendMessage('lx_response', JSON.stringify({ reqId: reqId, error: 'globalThis._eventHandlers is undefined!' }));
             return;
          }
          
          var handlers = globalThis._eventHandlers['request'] || [];
          if (handlers.length === 0) {
            var registeredEvents = Object.keys(globalThis._eventHandlers);
            console.error('[JS Error] No handlers for request! Action: ' + action);
            sendMessage('lx_response', JSON.stringify({ 
              reqId: reqId, 
              error: '未找到事件处理器. Action: ' + action + '. Registered events: ' + JSON.stringify(registeredEvents) 
            }));
            return;
          }
          
          var result = null;
          for (var i = 0; i < handlers.length; i++) {
            try {
              console.log('[JS Debug] Calling handler ' + i + ' for ' + action + ' with info: ' + JSON.stringify(params.info));
              var res = await handlers[i](params);
              console.log('[JS Debug] Handler ' + i + ' returned: ' + (res ? (typeof res === "string" ? res.substring(0, 50) : "object") : "null"));
              if (res) { result = res; break; }
            } catch (innerErr) {
              console.error('[JS Debug] Handler ' + i + ' error: ' + innerErr.message);
            }
          }
          sendMessage('lx_response', JSON.stringify({ reqId: reqId, data: result }));
        } catch (e) {
          console.error('[JS Debug] Runtime error during _callRequestEvent: ' + e.message);
          sendMessage('lx_response', JSON.stringify({ reqId: '$reqId', error: e.message }));
        }
      })();
    ''';

    final evalResult = _runtime!.evaluate(script);
    if (evalResult.isError) {
      final errMsg = 'JS调用异常: ${evalResult.stringResult}';
      _eventController.add({'type': 'error', 'message': errMsg});
      _pendingRequests.remove(reqId);
      return null;
    }

    // 关键修复：JS 端 evaluate 后的 (async function(){})() 立即返回，
    // 但 await handlers[i](params) 内部创建的 Promise 不会自动 resolve。
    // 立刻 flush microtask，让同步分支（无 HTTP 请求的 handler）能直接
    // 发出 lx_response，避免不必要的 15 秒等待。
    _flushMicrotasks();
    
    try {
      final result = await completer.future.timeout(const Duration(seconds: 15));
      return result;
    } on TimeoutException {
      _pendingRequests.remove(reqId);
      final errMsg = '请求超时(15s): ${params['action']}';
      _eventController.add({'type': 'error', 'message': errMsg});
      return null;
    } catch (e) {
      _pendingRequests.remove(reqId);
      _eventController.add({'type': 'error', 'message': '请求失败: $e'});
      return null;
    }
  }

  Future<List<MusicItem>> search(String keyword, {String? source, int page = 1, int limit = 20, String type = 'music'}) async {
    final platform = source ?? 'kw';
    final result = await _callRequestEvent({
      'action': 'search',
      'source': platform,
      'info': { 'keyword': keyword, 'page': page, 'limit': limit, 'type': type }
    });
    if (result == null || result['list'] == null) return [];
    
    final List list = result['list'];
    if (type == 'songlist') {
      return list.map((item) {
        final Map<String, dynamic> mapItem = item is Map ? Map<String, dynamic>.from(item) : {};
        return MusicItem(
          id: mapItem['id']?.toString() ?? _uuid.v4(),
          name: mapItem['name']?.toString() ?? '未知歌单',
          singer: mapItem['author']?.toString() ?? mapItem['creator']?.toString() ?? '未知作者',
          album: mapItem['play_count']?.toString() ?? '',
          duration: Duration.zero,
          source: _currentSource?.id ?? 'custom',
          platform: platform,
          artwork: mapItem['img']?.toString() ?? '',
          isPlayable: false,
          meta: mapItem,
        );
      }).toList();
    }

    return list.map((item) => _parseMusicItem(item, platform: platform)).toList();
  }

  Future<List<MusicItem>> getSongListDetail(String id, {int page = 1}) async {
    final result = await _callRequestEvent({
      'action': 'songListDetail',
      'info': { 'id': id, 'page': page }
    });
    if (result == null || result['list'] == null) return [];
    
    final List list = result['list'];
    // 歌单详情通常也是特定平台的
    return list.map((item) => _parseMusicItem(item, platform: result['source']?.toString() ?? 'kw')).toList();
  }

  Duration _parseDuration(dynamic interval) {
    if (interval == null) return Duration.zero;
    final String s = interval.toString();
    if (s.contains(':')) {
      final parts = s.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s_ = int.tryParse(parts[1]) ?? 0;
        return Duration(minutes: m, seconds: s_);
      }
    }
    return Duration(seconds: int.tryParse(s) ?? 0);
  }

  MusicItem _parseMusicItem(Map<String, dynamic> item, {String platform = 'kw'}) {
    return MusicItem(
      id: item['songmid']?.toString() ?? item['id']?.toString() ?? _uuid.v4(),
      name: item['name']?.toString() ?? '未知歌名',
      singer: item['singer']?.toString() ?? '未知歌手',
      album: item['album']?.toString() ?? '',
      duration: _parseDuration(item['interval']),
      source: _currentSource?.id ?? 'custom',
      platform: item['source']?.toString() ?? platform,
      artwork: item['img']?.toString() ?? '',
      songmid: item['songmid']?.toString(),
      hash: item['hash']?.toString(),
      meta: item, // 保存完整的原始数据，供后续 getMusicUrl 使用
    );
  }

  /// 仿桌面版 utils.ts 的 toOldMusicInfo：把 MusicItem 转成桌面版脚本
  /// 期望的旧格式 songInfo（包含 albumName / picUrl / types / _interval 等）。
  /// 桌面版脚本 (kg / tx / wy) 大多读 `songInfo.albumName` 和
  /// `songInfo.picUrl`，Flutter 版之前只输出 `album` / `img` 字段，
  /// 导致脚本拿不到正确值，getMusicUrl 返回 null。
  Map<String, dynamic> _toOldMusicInfo(MusicItem music, {String type = '128k'}) {
    final meta = Map<String, dynamic>.from(music.meta ?? const <String, dynamic>{});
    final String songmid = music.songmid ?? music.id;
    final String hash = (music.hash == null || music.hash!.isEmpty) ? songmid : music.hash!;
    final String interval = music.duration.inSeconds > 0
        ? '${(music.duration.inSeconds ~/ 60).toString().padLeft(2, '0')}:${(music.duration.inSeconds % 60).toString().padLeft(2, '0')}'
        : (meta['interval']?.toString() ?? '03:50');

    // 1) 先用 meta 填充脚本可能用到的扩展字段（qualitys / privilege / flac
    //    / strMediaMid / file / types 等）
    final Map<String, dynamic> info = <String, dynamic>{};
    for (final entry in meta.entries) {
      info[entry.key] = entry.value;
    }

    // 2) 覆盖最关键的标准字段，确保不会被 meta 里的脏数据替换
    info['songmid'] = songmid;
    info['hash'] = hash;
    info['name'] = music.name;
    info['singer'] = music.singer;
    info['source'] = music.platform;
    info['interval'] = interval;
    info['_interval'] = music.duration.inSeconds;
    info['type'] = type;
    info['qualitys'] = meta['qualitys'] ?? meta['types'] ?? [];
    info['privilege'] = meta['privilege'];

    // 兼容新旧两种字段名
    info['albumName'] = music.album.isNotEmpty
        ? music.album
        : (meta['albumName']?.toString() ?? meta['album']?.toString() ?? '');
    info['album'] = music.album.isNotEmpty
        ? music.album
        : (meta['album']?.toString() ?? '');
    info['albumId'] = meta['albumId']?.toString() ?? '';
    info['picUrl'] = music.artwork ?? meta['img']?.toString() ?? meta['picUrl']?.toString() ?? '';
    info['img'] = music.artwork ?? meta['img']?.toString() ?? '';

    return info;
  }

  Future<String?> getMusicUrl(MusicItem music) async {
    try {
      // 使用仿桌面版 toOldMusicInfo 的转换，补齐脚本期望的 albumName / picUrl
      // 等字段名，并保留 meta 中的 qualitys / privilege 等扩展数据。
      final musicInfo = _toOldMusicInfo(music);

      final result = await _callRequestEvent({
        'action': 'musicUrl',
        'source': music.platform,
        'info': {
          'type': '128k', // 默认音质
          'musicInfo': musicInfo,
        }
      });
      if (result == null) {
        return null;
      }

      // 兼容多种返回结构
      if (result is String) {
        return result;
      }

      // 桌面版常见结构: { url: "...", type: "..." } 或 { data: { url: "..." } }
      if (result['url'] != null) {
        final url = result['url'].toString();
        return url;
      }
      if (result['data'] != null && result['data'] is Map && result['data']['url'] != null) {
        final url = result['data']['url'].toString();
        return url;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getLyric(MusicItem music) async {
    try {
      final String songmid = music.songmid ?? music.id;
      final String hash = (music.hash == null || music.hash!.isEmpty) ? songmid : music.hash!;

      final Map<String, dynamic> musicInfo = {
        'songmid': songmid,
        'hash': hash,
        'name': music.name,
        'singer': music.singer,
        'album': music.album,
        'img': music.artwork,
        'source': music.platform,
      };

      if (music.meta != null) {
        musicInfo.addAll(music.meta!);
      }

      final result = await _callRequestEvent({
        'action': 'lyric',
        'source': music.platform,
        'info': {
          'musicInfo': musicInfo
        }
      });
      if (result == null) return null;
      if (result is String) return result;
      
      // 处理对象返回格式 { lyric: "...", tlyric: "..." }
      final lyric = result['lyric'] ?? result['lrc'];
      final tlyric = result['tlyric'];
      
      // 如果有翻译歌词，合并它们（LX Music 惯用做法）
      if (tlyric != null && tlyric.toString().isNotEmpty) {
        return '$lyric\n$tlyric';
      }
      
      return lyric?.toString();
    } catch (e) {
      return null;
    }
  }

  Future<Response> _makeHttpRequest(
    String url, 
    Map<String, dynamic> options, {
    bool isBinary = false,
    Map<String, dynamic>? queryParams,
  }) async {
    final method = (options['method'] as String?)?.toUpperCase() ?? 'GET';
    final headers = <String, dynamic>{};
    
    // 规范化 Headers 处理
    if (options['headers'] != null) {
      (options['headers'] as Map).forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }
    
    // 确保 User-Agent 存在
    bool hasUA = headers.keys.any((k) => k.toLowerCase() == 'user-agent');
    if (!hasUA) {
      headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    }

    dynamic body = options['body'];
    if (options['form'] != null) {
      body = options['form'];
      if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
      }
      if (body is Map) {
        // Dio 对于 x-www-form-urlencoded 接收 Map
        body = Map<String, dynamic>.from(body);
      }
    } else if (body != null && (body is Map || body is List)) {
      body = json.encode(body);
      if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
        headers['Content-Type'] = 'application/json';
      }
    }

    final dioOptions = Options(
      method: method,
      headers: headers,
      responseType: isBinary ? ResponseType.bytes : ResponseType.plain,
      validateStatus: (status) => true,
      receiveTimeout: Duration(milliseconds: options['timeout'] ?? 15000),
    );
    
    return _dio.request(
      url, 
      data: body, 
      queryParameters: queryParams,
      options: dioOptions
    );
  }

  void dispose() {
    _eventController.close();
    _runtime?.dispose();
    _runtime = null;
    _dio.close();
  }
}
