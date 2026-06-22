// 测试野花音源脚本 (URL: http://flower.tempmusics.tk/v1/...)
// 重点验证：inited 事件 + musicUrl 播放链接获取
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const script = fs.readFileSync(path.join(__dirname, 'yehua_source.js'), 'utf8');

let initResolve;
const initPromise = new Promise(res => { initResolve = res; });

// 真实响应数据 (m 字段会跟 md5(rawScript.trim()) 比较，设为空跳过)
const REAL_INIT_RESPONSE = JSON.stringify({
  code: 0,
  s: 'kw|128k&wy|128k&mg|128k&tx|128k&kg|128k',
  m: ''
});

const ctx = vm.createContext({
  lx: {
    request: function(url, options, cb) {
      if (typeof options === 'function') { cb = options; options = {}; }
      console.log('[lx.request] ' + url);
      if (url.indexOf('urlinfo') !== -1) {
        setTimeout(() => {
          const parsedBody = JSON.parse(REAL_INIT_RESPONSE);
          cb(null, { statusCode: 200, body: parsedBody, headers: {} }, parsedBody);
        }, 50);
      } else if (url.indexOf('/url/') !== -1) {
        // musicUrl 请求 - 模拟成功响应
        // 脚本里 S(G.body.data)，所以需要 code=0 + data 嵌套
        const urlBody = {
          code: 0,
          data: {
            url: 'http://music.126.net/song/media/outer/url?id=123.mp3',
            type: '128k',
            br: 128
          }
        };
        setTimeout(() => {
          cb(null, { statusCode: 200, body: urlBody, headers: {} }, urlBody);
        }, 50);
      } else {
        setTimeout(() => {
          cb(null, { statusCode: 404, body: 'not found', headers: {} }, 'not found');
        }, 50);
      }
    },
    on: function(event, cb) {
      console.log('[lx.on] event=' + event);
      ctx.__handlers__ = ctx.__handlers__ || {};
      ctx.__handlers__[event] = cb;
    },
    send: function(event, data) {
      console.log('[lx.send] event=' + event);
      if (event === 'inited') {
        console.log('[lx.send] inited data=', JSON.stringify(data));
        initResolve(data);
      } else if (event === 'updateAlert') {
        console.log('[lx.send] updateAlert data=', JSON.stringify(data));
      }
    },
    EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
    version: '2.0.0', env: 'desktop',
    currentScriptInfo: { rawScript: '', version: '1.0.0', name: 'test' },
    utils: {
      buffer: {
        from: function(s, enc) {
          let str = '';
          if (typeof s === 'string') {
            if (enc === 'hex') {
              for (let i = 0; i < s.length; i += 2) str += String.fromCharCode(parseInt(s.substr(i, 2), 16));
            } else if (enc === 'base64') {
              str = Buffer.from(s, 'base64').toString('binary');
            } else {
              str = s;
            }
          }
          return {
            _str: str, _isBuffer: true, length: str.length,
            toString: function(e) { return this._str; }
          };
        },
        bufToString: function(buffer, enc) {
          if (buffer && buffer.toString) return buffer.toString(enc);
          return String(buffer);
        }
      },
      crypto: {
        md5: function(s) { return 'md5_' + s.length; }
      }
    }
  }
});
ctx.window = ctx; ctx.process = { env: { NODE_ENV: 'production' } };
ctx.navigator = { userAgent: 'test' };
ctx.console = console;
ctx.atob = s => Buffer.from(s, 'base64').toString('binary');
ctx.btoa = s => Buffer.from(s, 'binary').toString('base64');

console.log('=== 野花音源测试 (Node.js) ===\n');
console.log('--- 1. 执行脚本 ---');
try {
  vm.runInContext(script, ctx);
  console.log('脚本执行完成 (同步部分)\n');
} catch (e) {
  console.error('脚本执行错误:', e.message);
  process.exit(1);
}

initPromise.then((data) => {
  console.log('\n--- 2. inited 事件 ---');
  console.log('Sources:', JSON.stringify(data, null, 2));

  if (!ctx.__handlers__ || !ctx.__handlers__.request) {
    console.log('没有 request handler，测试结束');
    process.exit(0);
  }

  // 直接测试 musicUrl (野花音源不实现 search)
  console.log('\n--- 3. 测试 musicUrl (source=kw) ---');
  const cb = ctx.__handlers__.request;
  cb({
    source: 'kw', action: 'musicUrl',
    info: {
      type: '128k',
      musicInfo: {
        songmid: '123456',
        name: '测试歌曲',
        singer: '测试歌手',
        source: 'kw'
      }
    }
  }).then(result => {
    console.log('musicUrl result:', JSON.stringify(result, null, 2));
    if (result && (result.url || (result.data && result.data.url))) {
      console.log('\n✓ musicUrl 测试通过！');
    } else {
      console.log('\n✗ musicUrl 测试失败：未返回 url');
    }
    setTimeout(() => process.exit(0), 500);
  }).catch(e => {
    console.error('musicUrl 错误:', e.message);
    process.exit(1);
  });
});

setTimeout(() => {
  console.error('\n--- 5秒超时 ---');
  process.exit(1);
}, 5000);
