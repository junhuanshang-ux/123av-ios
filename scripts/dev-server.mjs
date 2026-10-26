#!/usr/bin/env node
/**
 * 本地预览服务器（仅开发/自测用，不参与 IPA 打包）
 *
 *   1. 静态托管 www/（http://127.0.0.1:8787/）
 *   2. /p?u=<url> 跨域代理：站点接口只回 Allow-Origin: null，浏览器预览需要代理
 *
 * App 内不需要它：WKWebView 里所有请求都走原生 message handler。
 *
 *   node scripts/dev-server.mjs [port]
 */
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', 'www');
const PORT = Number(process.argv[2] || 8787);
const UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.json': 'application/json; charset=utf-8',
  '.ico': 'image/x-icon',
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
};

async function proxy(req, res, target) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : null;
  try {
    const upstream = await fetch(target, {
      method: req.method,
      headers: {
        'User-Agent': UA,
        'Accept-Language': 'zh-CN,zh;q=0.9',
        Accept: 'text/html,application/json;q=0.9,*/*;q=0.8',
        ...(req.headers['content-type'] ? { 'Content-Type': req.headers['content-type'] } : {}),
      },
      body: req.method === 'GET' || req.method === 'HEAD' ? undefined : body,
      redirect: 'follow',
    });
    const buf = Buffer.from(await upstream.arrayBuffer());
    res.writeHead(upstream.status, {
      ...CORS,
      'Content-Type': upstream.headers.get('content-type') || 'text/plain; charset=utf-8',
    });
    res.end(buf);
  } catch (e) {
    res.writeHead(502, { ...CORS, 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('proxy error: ' + e.message);
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS);
    return res.end();
  }

  if (url.pathname === '/p') {
    const target = url.searchParams.get('u');
    if (!target) {
      res.writeHead(400, CORS);
      return res.end('missing u');
    }
    return proxy(req, res, target);
  }

  let filePath = path.join(ROOT, decodeURIComponent(url.pathname));
  if (url.pathname === '/' || url.pathname === '') filePath = path.join(ROOT, 'index.html');
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403);
    return res.end('forbidden');
  }

  try {
    const s = await stat(filePath);
    if (s.isDirectory()) filePath = path.join(filePath, 'index.html');
    let data = await readFile(filePath);
    let type = MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream';

    // 注入开发用代理前缀
    if (filePath.endsWith('.html')) {
      data = Buffer.from(
        data
          .toString('utf8')
          .replace(
            '</head>',
            `<script>window.__DEV_PROXY__='http://127.0.0.1:${PORT}/p?u=';</script>\n</head>`
          ),
        'utf8'
      );
    }
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
    res.end(data);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404');
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`dev: http://127.0.0.1:${PORT}/   (proxy: /p?u=...)`);
});
