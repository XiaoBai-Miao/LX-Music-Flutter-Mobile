// 解密野花音源脚本的特定字符串
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const script = fs.readFileSync(path.join(__dirname, 'yehua_source.js'), 'utf8');

const ctx = vm.createContext({
  lx: {
    request: () => {}, on: () => {}, send: () => {},
    EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
    version: '1.0.0', env: 'test',
    currentScriptInfo: { version: '1.0.0' },
    utils: { buffer: { from: x => x }, crypto: { md5: x => x } }
  }
});
ctx.window = ctx; ctx.process = { env: {} }; ctx.navigator = { userAgent: 't' };
ctx.console = console;
ctx.atob = s => Buffer.from(s, 'base64').toString('binary');
ctx.btoa = s => Buffer.from(s, 'binary').toString('base64');

const probe = `
;globalThis.__k__ = k;
;globalThis.__E_NAMES__ = e;
;globalThis.__INFO__ = {
  url: k(0x1a0) + k(0x193) + k(0x15f) + k(0x196) + i[k('\x30\x78\x31\x37\x62')],
  hash: k(0x182),
  songmid: k(0x19e),
  source: k(0x184),
  hex: k(0x185),
  data: k(0x194),
  body: k(0x172),
  inited: e[k(0x15c)],
  updateAlert: e[k(0x17c) + 't'],
  musicUrl: k(0x197),
  // 不同 source 的 id
  kwid: k(0x16d),  // kw
  wyid: k(0x16d),  // wy  
  kgid: k(0x182),  // kg = 'hash'
  mgid: k(0x183) + 'd',  // mg = 'copyrightId' + 'd' = 'copyrightIdd'? 这个不对，看下
  txid: k(0x184 + 'd'),  // tx
  // quality string
  q128k: k(0x18c),  // 'kw|128k&wy'
  q128mg: k(0x15e),  // '|128k&mg|1'
  q128tx: k(0x168),  // '28k&tx|128'
  q128kg: k(0x173),  // 'k&kg|128k'
  // JSON 字段
  errCode: k(0x181),  // 'code'
  errMsg: k(0x170),   // 'msg'
  failed: k(0x16d),   // 'failed'
  fialed: k(0x171),   // 'fialed'
  // 异常
  errServer: k(0x16c), // '服务器异常'
  errServer2: k(0x195),  // 拼接出来的 '服务器异常'
  // 字符串拼接
  httpBase: k(0x17e),  // 'http' + ...
  // 字符串函数
  url_path: k(0x18d),  // '/url/'
  urlinfo: k(0x196),  // '/urlinfo/'
  songmidField: k(0x19e),  // 'songmid'
  sourcesField: k(0x19f),  // 'sources'
  typeField: k(0x178),  // 'music' - 但是! 这是 'music' 还是 'type' 字段？
  // musicUrl handler 内部的 m map 索引
  mY: k(0x18d),
  mL: k(0x189),
  mK: k(0x161),
  mU: k(0x1a1),
  mH: k(0x18f),
  mS: k(0x1a1),
  mN: k(0x162),
  mB: k(0x192),
  mV: k(0x19b),
  mG: k(0x166),
  mM: k(0x174),
  mT: k(0x18b),
  mE: k(0x176),
  mg: k(0x18e)
};
;globalThis.__ALL_K__ = {};
;(function() {
  var _i;
  for (_i = 0x150; _i < 0x1b0; _i++) {
    globalThis.__ALL_K__['k_' + _i.toString(16)] = k(_i);
  }
})();
`;

try { vm.runInContext(script + probe, ctx); } catch (e) {
  console.log('脚本执行错误(预期):', e.message);
}

console.log('=== 关键字符串解码结果 ===');
console.log(JSON.stringify(ctx.__INFO__, null, 2));
console.log('\n=== 所有 k(0x150-0x1af) 索引 ===');
for (const k in ctx.__ALL_K__) {
  console.log(`  ${k}: ${JSON.stringify(ctx.__ALL_K__[k])}`);
}
