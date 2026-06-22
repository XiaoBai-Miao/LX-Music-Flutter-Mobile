// 测试完整的 needle 响应格式
const fs = require('fs');
const vm = require('vm');
const script = fs.readFileSync(__dirname + '/yehua_source.js', 'utf8');

const urls = [];
const ctx = vm.createContext({
  lx: {
    request: function(url, options, callback) {
      if (typeof options === 'function') { callback = options; options = {}; }
      console.log('[lx.request] url=' + url);
      urls.push(url);

      if (url.includes('/urlinfo/')) {
        // 完整模拟 needle 响应格式
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
        console.log('[lx.request] *** musicUrl request ***');
        console.log('[lx.request] full url: ' + url);
        const bodyStr = '{"code":0,"data":{"url":"http://example.com/music.mp3","type":"128k","br":128}}';
        const bodyObj = JSON.parse(bodyStr);
        callback(null, {
          statusCode: 200,
          statusMessage: 'OK',
          headers: {'content-type':'application/json'},
          bytes: bodyStr.length,
          raw: Buffer.from(bodyStr),
          body: bodyObj
        }, bodyObj);
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
      if (data && data.sources) {
        console.log('[lx.send] sources keys: ' + Object.keys(data.sources).join(','));
      }
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

try{vm.runInContext(script,ctx);}catch(e){console.log('Err:',e.message);}

console.log('\n=== Init done, testing musicUrl ===');
if(ctx.__h&&ctx.__h.request){
  urls.length=0;
  const r=ctx.__h.request[0]({
    action:'musicUrl',source:'tx',
    info:{type:'128k',musicInfo:{
      songmid:'003aAYrm3GE0Ac',hash:'003aAYrm3GE0Ac',
      name:'稻香',singer:'周杰伦',source:'tx',
      interval:'03:43',_interval:223,type:'128k',
      albumName:'魔杰座',album:'魔杰座',
      picUrl:'https://y.gtimg.cn/music/photo_new/T002R500x500M000002Neh8l0uciQZ.jpg',
      img:'https://y.gtimg.cn/music/photo_new/T002R500x500M000002Neh8l0uciQZ.jpg'
    }}
  });
  if(r&&typeof r.then==='function'){
    r.then(v=>{console.log('result:',JSON.stringify(v));console.log('URLs:',urls);}).catch(e=>{console.log('error:',e);console.log('URLs:',urls);});
  }
}
