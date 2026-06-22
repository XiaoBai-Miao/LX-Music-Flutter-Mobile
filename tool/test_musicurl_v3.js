// 测试 init 响应中添加 url 字段后的行为
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
        // 添加 url 字段 - 这可能是脚本需要的
        const body = {
          code: 0,
          s: 'kw|128k&wy|128k&mg|128k&tx|128k&kg|128k',
          m: 'd644ca7556c03cec156b929f6bbb330d',
          url: 'http://flower.tempmusics.tk'
        };
        callback(null, {statusCode:200, body:body}, body);
      } else {
        console.log('[lx.request] *** musicUrl request ***');
        console.log('[lx.request] full url: ' + url);
        console.log('[lx.request] full options: ' + JSON.stringify(options));
        // 模拟成功
        const body = {code:0, data:{url:'http://example.com/music.mp3', type:'128k', br:128}};
        callback(null, {statusCode:200, body:body}, body);
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
      buffer: {from:(d,e)=>({toString:()=>d}), bufToString:(b,e)=>b&&b.toString?b.toString():String(b)},
      crypto: {md5:s=>'md5_'+s}
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
