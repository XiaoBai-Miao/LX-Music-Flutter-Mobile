// 测试 init 成功后 musicUrl handler 的行为
const fs = require('fs');
const vm = require('vm');
const script = fs.readFileSync(__dirname + '/yehua_source.js', 'utf8');

const urls = [];
const ctx = vm.createContext({
  lx: {
    request: function(url, options, callback) {
      if (typeof options === 'function') { callback = options; options = {}; }
      console.log('[lx.request] url=' + url);
      console.log('[lx.request] headers=' + JSON.stringify(options.headers || {}));
      urls.push(url);

      if (url.includes('/urlinfo/')) {
        const body = {code:0, s:'kw|128k&wy|128k&mg|128k&tx|128k&kg|128k', m:'d644ca7556c03cec156b929f6bbb330d'};
        callback(null, {statusCode:200, body:body}, body);
      } else {
        console.log('[lx.request] *** musicUrl request ***');
        console.log('[lx.request] full url: ' + url);
        console.log('[lx.request] full options: ' + JSON.stringify(options));
        callback(null, {statusCode:404, body:'Not Found'}, 'Not Found');
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

// 测试 musicUrl
if(ctx.__h&&ctx.__h.request){
  console.log('\n=== Testing musicUrl ===');
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
    r.then(v=>console.log('result:',JSON.stringify(v))).catch(e=>console.log('error:',e));
  } else {
    console.log('sync result:', r);
  }
}
