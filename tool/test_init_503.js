// 测试野花脚本 init 阶段在 503 时的 fallback 行为
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const script = fs.readFileSync(path.join(__dirname, 'yehua_source.js'), 'utf8');

const urls = [];
const initResult = { event: null, data: null };

const ctx = vm.createContext({
  lx: {
    request: function(url, options, callback) {
      if (typeof options === 'function') { callback = options; options = {}; }
      console.log('[lx.request] url=' + url);
      console.log('[lx.request] options=' + JSON.stringify(options));
      urls.push(url);
      // 模拟 503 响应
      callback(null, { statusCode: 503, body: '<html>503</html>' }, '<html>503</html>');
      return () => {};
    },
    on: function(name, handler) {
      console.log('[lx.on] registering: ' + name);
      if (!ctx.__handlers) ctx.__handlers = {};
      if (!ctx.__handlers[name]) ctx.__handlers[name] = [];
      ctx.__handlers[name].push(handler);
    },
    send: function(event, data) {
      console.log('[lx.send] event=' + event);
      console.log('[lx.send] data=' + JSON.stringify(data, null, 2));
      initResult.event = event;
      initResult.data = data;
      return true;
    },
    EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
    version: '2.0.0',
    env: 'desktop',
    currentScriptInfo: { version: '1.0.0' },
    utils: {
      buffer: {
        from: function(d, e) { return { toString: function() { return d; } }; },
        bufToString: function(b, e) { return b && b.toString ? b.toString() : String(b); }
      },
      crypto: { md5: function(s) { return 'md5_' + s; } }
    }
  },
  console: console,
  setTimeout: function(fn, ms) { setImmediate(fn); return 1; },
  clearTimeout: function() {},
  atob: function(s) { return Buffer.from(s, 'base64').toString('binary'); },
  btoa: function(s) { return Buffer.from(s, 'binary').toString('base64'); }
});
ctx.window = ctx;
ctx.process = { env: {} };
ctx.navigator = { userAgent: 'Mozilla/5.0' };

try { vm.runInContext(script, ctx); } catch (e) {
  console.log('Error:', e.message);
}

console.log('\n=== All URLs requested during init ===');
urls.forEach((u, i) => console.log('  ' + i + ': ' + u));

console.log('\n=== Init result ===');
console.log('event:', initResult.event);
console.log('data:', JSON.stringify(initResult.data, null, 2));

// 现在测试 musicUrl handler
if (ctx.__handlers && ctx.__handlers.request && ctx.__handlers.request.length > 0) {
  console.log('\n=== Testing musicUrl handler ===');
  urls.length = 0; // 清空

  const result = ctx.__handlers.request[0]({
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
  });

  if (result && typeof result.then === 'function') {
    result.then(r => {
      console.log('musicUrl result:', JSON.stringify(r));
      console.log('musicUrl URLs requested:');
      urls.forEach((u, i) => console.log('  ' + i + ': ' + u));
    }).catch(e => {
      console.log('musicUrl error:', e.message);
      console.log('musicUrl URLs requested:');
      urls.forEach((u, i) => console.log('  ' + i + ': ' + u));
    });
  } else {
    console.log('musicUrl sync result:', result);
    console.log('musicUrl URLs requested:');
    urls.forEach((u, i) => console.log('  ' + i + ': ' + u));
  }
}
