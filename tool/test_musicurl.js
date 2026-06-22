// 测试野花脚本 musicUrl handler 实际构造的 URL
const fs = require('fs');
const path = require('path');

// 模拟桌面版环境
const requests = [];
const events = {};

const fakeLx = {
  version: '2.0.0',
  env: 'desktop',
  EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
  request: function(url, options, callback) {
    if (typeof options === 'function') { callback = options; options = {}; }
    console.log('[FAKE lx.request] url=' + url);
    console.log('[FAKE lx.request] options=' + JSON.stringify(options));
    requests.push({ url, options, callback });
    // 模拟成功响应
    callback(null, { statusCode: 200, body: { code: 0, data: { url: 'http://example.com/music.mp3', type: '128k', br: 128 } } }, { code: 0, data: { url: 'http://example.com/music.mp3' } });
    return () => {};
  },
  send: function(eventName, data) {
    console.log('[FAKE lx.send] event=' + eventName);
    if (eventName === 'inited') {
      console.log('[FAKE lx.send] inited data sources=' + JSON.stringify(data?.sources ? Object.keys(data.sources) : 'null'));
    }
    return true;
  },
  on: function(eventName, handler) {
    console.log('[FAKE lx.on] registering handler for: ' + eventName);
    if (!events[eventName]) events[eventName] = [];
    events[eventName].push(handler);
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
            str = Buffer.from(data, 'base64').toString('binary');
          } else { str = data; }
        } else if (data && typeof data.length === 'number') {
          for (var i = 0; i < data.length; i++) str += String.fromCharCode(typeof data[i] === 'number' ? data[i] : 0);
        }
        return {
          _str: str, _isBuffer: true, length: str.length,
          toString: function(enc) {
            if (enc === 'hex') { var hex = ''; for (var i = 0; i < this._str.length; i++) { var h = this._str.charCodeAt(i).toString(16); hex += h.length === 1 ? '0' + h : h; } return hex; }
            if (enc === 'base64') return Buffer.from(this._str, 'binary').toString('base64');
            return this._str;
          }
        };
      },
      bufToString: function(buffer, encoding) { return buffer && buffer.toString ? buffer.toString(encoding) : String(buffer); }
    },
    crypto: { md5: function(str) { return 'mock_md5_' + str; } }
  },
  currentScriptInfo: { id: 'test', name: '野花测试', version: '1.0.0', author: 'test', description: '', homepage: '', rawScript: '' }
};

globalThis.lx = fakeLx;
globalThis.window = globalThis;
globalThis.process = { env: { NODE_ENV: 'production' } };
globalThis.navigator = { userAgent: 'Mozilla/5.0' };
globalThis.setTimeout = function(fn, ms) { setImmediate(fn); return 1; };
globalThis.clearTimeout = function() {};
globalThis.atob = s => Buffer.from(s, 'base64').toString('binary');
globalThis.btoa = s => Buffer.from(s, 'binary').toString('base64');

// 执行脚本
const script = fs.readFileSync(path.join(__dirname, 'yehua_source.js'), 'utf8');
try {
  eval(script);
} catch (e) {
  console.log('脚本执行错误:', e.message);
}

// 等待 inited
setTimeout(() => {
  console.log('\n=== 测试 musicUrl handler ===');
  console.log('注册的事件:', Object.keys(events));
  console.log('request handlers 数量:', events['request']?.length || 0);

  if (events['request'] && events['request'].length > 0) {
    // 模拟 tx 平台的 musicUrl 请求
    const params = {
      action: 'musicUrl',
      source: 'tx',
      info: {
        type: '128k',
        musicInfo: {
          songmid: '003aAYrm3GE0Ac',
          hash: '003aAYrm3GE0Ac',
          name: '稻香',
          singer: '周杰伦',
          source: 'tx',
          interval: '03:43',
          _interval: 223,
          type: '128k',
          albumName: '魔杰座',
          album: '魔杰座',
          picUrl: 'https://y.gtimg.cn/music/photo_new/T002R500x500M000002Neh8l0uciQZ.jpg',
          img: 'https://y.gtimg.cn/music/photo_new/T002R500x500M000002Neh8l0uciQZ.jpg'
        }
      }
    };

    console.log('\n--- 调用 handler ---');
    requests.length = 0; // 清空之前的请求记录

    const result = events['request'][0](params);
    if (result && typeof result.then === 'function') {
      result.then(r => {
        console.log('\n--- handler 返回结果 ---');
        console.log('result:', JSON.stringify(r));
        console.log('\n--- handler 发出的 HTTP 请求 ---');
        requests.forEach((req, i) => {
          console.log(`  请求 ${i}: url=${req.url}`);
          console.log(`  请求 ${i}: method=${req.options?.method || 'GET'}`);
          console.log(`  请求 ${i}: headers=${JSON.stringify(req.options?.headers || {})}`);
        });
      }).catch(e => {
        console.log('handler error:', e.message);
        console.log('\n--- handler 发出的 HTTP 请求 ---');
        requests.forEach((req, i) => {
          console.log(`  请求 ${i}: url=${req.url}`);
          console.log(`  请求 ${i}: method=${req.options?.method || 'GET'}`);
          console.log(`  请求 ${i}: headers=${JSON.stringify(req.options?.headers || {})}`);
        });
      });
    } else {
      console.log('handler 同步返回:', result);
    }
  }
}, 100);
