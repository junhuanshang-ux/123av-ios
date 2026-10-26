/* 精简 MD5（RFC 1321），仅用于计算封面图 CDN 路径前缀：md5(code)[:2] */
(function (root) {
  'use strict';

  var K = new Uint32Array(64);
  for (var i = 0; i < 64; i++) {
    K[i] = (Math.abs(Math.sin(i + 1)) * 4294967296) | 0;
  }
  var S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];

  function rotl(x, c) { return (x << c) | (x >>> (32 - c)); }

  function encode(str) {
    if (root.TextEncoder) return new root.TextEncoder().encode(str);
    var utf8 = unescape(encodeURIComponent(str));
    var out = new Uint8Array(utf8.length);
    for (var i = 0; i < utf8.length; i++) out[i] = utf8.charCodeAt(i);
    return out;
  }

  function md5(str) {
    var msg = encode(String(str));
    var bitLen = msg.length * 8;
    var blocks = ((msg.length + 8) >> 6) + 1;
    var total = blocks * 64;
    var buf = new Uint8Array(total);
    buf.set(msg);
    buf[msg.length] = 0x80;
    var dv = new DataView(buf.buffer);
    dv.setUint32(total - 8, bitLen >>> 0, true);
    dv.setUint32(total - 4, Math.floor(bitLen / 4294967296), true);

    var a0 = 0x67452301 | 0, b0 = 0xefcdab89 | 0, c0 = 0x98badcfe | 0, d0 = 0x10325476 | 0;
    var M = new Uint32Array(16);

    for (var off = 0; off < total; off += 64) {
      for (var j = 0; j < 16; j++) M[j] = dv.getUint32(off + j * 4, true);
      var a = a0, b = b0, c = c0, d = d0;
      for (var r = 0; r < 64; r++) {
        var f, g;
        if (r < 16) { f = (b & c) | (~b & d); g = r; }
        else if (r < 32) { f = (d & b) | (~d & c); g = (5 * r + 1) & 15; }
        else if (r < 48) { f = b ^ c ^ d; g = (3 * r + 5) & 15; }
        else { f = c ^ (b | ~d); g = (7 * r) & 15; }
        var tmp = d;
        d = c;
        c = b;
        var sum = (a + f + K[r] + M[g]) | 0;
        b = (b + rotl(sum, S[(r >> 4) * 4 + (r & 3)])) | 0;
        a = tmp;
      }
      a0 = (a0 + a) | 0;
      b0 = (b0 + b) | 0;
      c0 = (c0 + c) | 0;
      d0 = (d0 + d) | 0;
    }

    var out = '';
    [a0, b0, c0, d0].forEach(function (v) {
      for (var t = 0; t < 4; t++) {
        out += ((v >>> (t * 8)) & 0xff).toString(16).padStart(2, '0');
      }
    });
    return out;
  }

  root.MD5 = md5;
})(typeof window !== 'undefined' ? window : globalThis);
