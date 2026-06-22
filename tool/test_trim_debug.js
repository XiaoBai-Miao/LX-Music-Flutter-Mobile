// 深度调试 init 阶段的 trim 错误
const fs = require('fs');
const vm = require('vm');
const script = fs.readFileSync(__dirname + '/yehua_source.js', 'utf8');

// 注入探针来追踪 trim 调用
const probe = `
;globalThis.__trim_calls__ = [];
;(function() {
  const origTrim = String.prototype.trim;
  String.prototype.trim = function() {
    const result = origTrim.call(this);
    if (this.length < 200) {
      globalThis.__trim_calls__.push(this.toString());
    }
    return result;
  };
})();
`;

const urls = [];
const ctx = vm.createContext({
  lx: {
    request: function(url, options, callback) {
      if (typeof options === 'function') { callback = options; options = {}; }
      console.log('[lx.request] url=' + url);
      urls.push(url);

      if (url.includes('/urlinfo/')) {
        const bodyStr = '{"code":0,"s":"kw|128k&wy|128k&mg|128k&tx|128k&kg|128k","m":"d644ca7556c03cec156b929f6bbb330d"}';
        const bodyObj = JSON.parse(bodyStr);
        const raw = Buffer.from(bodyStr);
        callback(null, {
          statusCode: 200,
          statusMessage: 'OK',
          headers: {'content-type':'application/octet-stream','content-length':'95'},
          bytes: 95,
          raw: raw,
          body: bodyObj
        }, bodyObj);
      } else {
        const bodyStr = '{"code":0,"data":{"url":"http://example.com/music.mp3"}}';
        const bodyObj = JSON.parse(bodyStr);
        callback(null, {statusCode:200,body:bodyObj}, bodyObj);
      }
      return () => {};
    },
    on: function(name, handler) {
      if (!ctx.__h) ctx.__h = {};
      if (!ctx.__h[name]) ctx.__h[name] = [];
      ctx.__h[name].push(handler);
    },
    send: function(event, data) {
      console.log('[lx.send] event=' + event);
    },
    EVENT_NAMES: {request:'request',inited:'inited',updateAlert:'updateAlert'},
    version:'2.0.0', env:'desktop',
    currentScriptInfo: {version:'1.0.0'},
    utils: {
      buffer: {
        from: function(data, encoding) {
          if (Buffer.isBuffer(data)) return data;
          if (typeof data === 'string') {
            if (encoding === 'hex') return Buffer.from(data, 'hex');
            if (encoding === 'base64') return Buffer.from(data, 'base64');
            return Buffer.from(data);
          }
          return Buffer.alloc(0);
        },
        bufToString: function(buffer, encoding) {
          if (Buffer.isBuffer(buffer)) return buffer.toString(encoding || 'utf8');
          return String(buffer);
        }
      },
      crypto: {md5:s=>{const crypto=require('crypto');return crypto.createHash('md5').update(s).digest('hex');}}
    }
  },
  console:console,
  setTimeout:(fn,ms)=>{setImmediate(fn);return 1;},
  clearTimeout:()=>{},
  atob:s=>Buffer.from(s,'base64').toString('binary'),
  btoa:s=>Buffer.from(s,'binary').toString('base64')
});
ctx.window=ctx; ctx.process={env:{}}; ctx.navigator={userAgent:'Mozilla/5.0'};

try{vm.runInContext(script + probe, ctx);}catch(e){
  console.log('Err:', e.message);
  console.log('Stack:', e.stack?.split('\n').slice(0,5).join('\n'));
}

console.log('\n=== trim calls before error ===');
ctx.__trim_calls__?.forEach((s,i) => console.log(`  ${i}: "${s}"`));
