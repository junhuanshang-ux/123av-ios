/* =========================================================================
 * 123AV iOS · 应用前端（本地离线 UI + 站点 API）
 *
 * 数据来源（均已实测）：
 *   1. 推荐服务  https://rec2.123av.com   POST，带 timestamp + signature
 *   2. 站点 JSON https://123av.com/api/v1/*
 *   3. 站点 HTML /cn/new|/cn/hot|/cn/genres|/cn/g/{slug}|/cn/search|/cn/v/{code}
 *   4. 封面图    https://icdn.123av.me/img2/s360/{md5(code)[:2]}/{code}/cover.jpg
 * ========================================================================= */
'use strict';

/* ------------------------------ 配置 ------------------------------ */
var CFG = {
  SITE: 'https://123av.com',
  REC: 'https://rec2.123av.com',
  REC_KEY: 'e8bcc533-bc38-4a33-af0e-678d38237754',
  CDN: 'https://icdn.123av.me',
  UA: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  LOCALE: 'zh-CN',
  URL_LOCALE: 'cn',
  // 浏览器预览时的跨域代理（scripts/dev-server.mjs 注入）；App 内走原生桥，不用它
  PROXY: window.__DEV_PROXY__ || null,
  LIST_PATHS: {
    new: '/cn/new',
    hot: '/cn/hot',
    recent: '/cn/recent',
    censored: '/cn/censored',
    uncensored: '/cn/uncensored',
    leaked: '/cn/uncensored-leaked'
  }
};

var LIST_NAME = { new: '新发布', hot: '热门', recent: '最近', censored: '有码', uncensored: '无码', leaked: '无码泄露' };

/* ------------------------------ 工具 ------------------------------ */
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

function unesc(s) {
  return String(s == null ? '' : s)
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, function (_, n) { return String.fromCharCode(+n); })
    .replace(/\s+/g, ' ')
    .trim();
}

function fmtSecs(v) {
  var n = parseInt(v, 10);
  if (!isFinite(n) || n <= 0) return '';
  var h = Math.floor(n / 3600), m = Math.floor((n % 3600) / 60), s = n % 60;
  var p = function (x) { return x < 10 ? '0' + x : '' + x; };
  return h > 0 ? h + ':' + p(m) + ':' + p(s) : m + ':' + p(s);
}

// 站点前端同款字符串哈希（用于 rec2 签名）
function simpleHash(input) {
  var hash = 0;
  for (var i = 0; i < input.length; i++) {
    hash = (hash << 5) - hash + input.charCodeAt(i);
    hash |= 0;
  }
  return (hash >>> 0).toString(16);
}

// 还原 HTML 里被 JS 转义过的 JSON 字符串
function jsUnescape(s) {
  return String(s).replace(/\\(u[0-9a-fA-F]{4}|[\s\S])/g, function (_, e) {
    if (e[0] === 'u') return String.fromCharCode(parseInt(e.slice(1), 16));
    return { n: '\n', t: '\t', r: '\r', b: '\b', f: '\f' }[e] || e;
  });
}

function uuid() {
  if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
  var s = '', i;
  for (i = 0; i < 32; i++) s += ((Math.random() * 16) | 0).toString(16);
  return s.slice(0, 8) + '-' + s.slice(8, 12) + '-4' + s.slice(13, 16) + '-a' + s.slice(17, 20) + '-' + s.slice(20, 32);
}

function userId() {
  try {
    var id = localStorage.getItem('user_id');
    if (!id) { id = uuid(); localStorage.setItem('user_id', id); }
    return id;
  } catch (e) { return uuid(); }
}

var toastTimer = null;
function toast(msg) {
  var el = document.getElementById('toast');
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(function () { el.hidden = true; }, 2200);
}


/* ------------------------------ 主题（白天 / 夜间） ------------------------------ */
var ICON_MOON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A8.5 8.5 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>';
var ICON_SUN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4.2"/><path d="M12 2v2.4M12 19.6V22M2 12h2.4M19.6 12H22M4.9 4.9l1.7 1.7M17.4 17.4l1.7 1.7M19.1 4.9l-1.7 1.7M6.6 17.4l-1.7 1.7"/></svg>';

var Theme = {
  KEY: 'theme',
  current: 'dark',
  manual: false,

  init: function () {
    var saved = null;
    try { saved = localStorage.getItem(Theme.KEY); } catch (e) {}
    Theme.manual = !!saved;
    Theme.apply(saved || Theme.systemTheme(), false);
    if (!saved && window.matchMedia) {
      var mq = window.matchMedia('(prefers-color-scheme: light)');
      var handler = function () { if (!Theme.manual) Theme.apply(Theme.systemTheme(), false); };
      if (mq.addEventListener) mq.addEventListener('change', handler);
      else if (mq.addListener) mq.addListener(handler);
    }
  },

  systemTheme: function () {
    return (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';
  },

  apply: function (theme, persist) {
    Theme.current = theme === 'light' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', Theme.current);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', Theme.current === 'light' ? '#f5f6f8' : '#0e0f11');
    var btn = document.getElementById('themeBtn');
    if (btn) btn.innerHTML = Theme.current === 'light' ? ICON_MOON : ICON_SUN;
    if (persist) {
      Theme.manual = true;
      try { localStorage.setItem(Theme.KEY, Theme.current); } catch (e) {}
    }
    // 通知原生：状态栏与系统控件跟着变
    if (Native.theme) {
      try { window.webkit.messageHandlers.theme.postMessage({ theme: Theme.current }); } catch (e) {}
    }
  },

  toggle: function () {
    Theme.apply(Theme.current === 'light' ? 'dark' : 'light', true);
  }
};

/* ------------------------------ 网络 ------------------------------ */
var Native = {
  net: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.net),
  player: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.player),
  theme: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.theme)
};

var pendingMap = Object.create(null);
var reqSeq = 0;

window.__net = {
  res: function (id, status, b64) {
    var p = pendingMap[id];
    if (!p) return;
    delete pendingMap[id];
    var text = '';
    try {
      var bin = atob(b64 || '');
      var bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      text = new TextDecoder('utf-8').decode(bytes);
    } catch (e) { text = ''; }
    if (status >= 200 && status < 400) p.resolve({ status: status, text: text });
    else p.reject(new Error('HTTP ' + status));
  }
};

function netFetch(url, opts) {
  opts = opts || {};
  var method = opts.method || 'GET';
  var headers = Object.assign(
    { 'User-Agent': CFG.UA, 'Accept-Language': 'zh-CN,zh;q=0.9' },
    opts.headers || {}
  );
  var body = opts.body || null;
  var timeout = opts.timeout || 20000;

  if (Native.net) {
    return new Promise(function (resolve, reject) {
      var id = 'r' + (++reqSeq) + '_' + Date.now().toString(36);
      var timer = setTimeout(function () {
        if (pendingMap[id]) { delete pendingMap[id]; reject(new Error('请求超时')); }
      }, timeout);
      pendingMap[id] = {
        resolve: function (v) { clearTimeout(timer); resolve(v); },
        reject: function (e) { clearTimeout(timer); reject(e); }
      };
      try {
        window.webkit.messageHandlers.net.postMessage({ id: id, url: url, method: method, headers: headers, body: body });
      } catch (e) {
        delete pendingMap[id];
        clearTimeout(timer);
        reject(e);
      }
    });
  }

  var target = CFG.PROXY ? CFG.PROXY + encodeURIComponent(url) : url;
  var init = { method: method, headers: headers };
  if (body) init.body = body;
  return fetch(target, init).then(function (r) {
    return r.text().then(function (t) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return { status: r.status, text: t };
    });
  });
}

/* ------------------------------ API ------------------------------ */
var props = ['code', 'title_' + (CFG.LOCALE === 'zh-CN' ? 'cn' : 'en'), 'duration'];

function recUrl(path) {
  var ts = Math.floor(Date.now() / 1000).toString();
  var sig = simpleHash(CFG.REC_KEY + ts + CFG.UA);
  return CFG.REC + path + '?timestamp=' + ts + '&signature=' + sig;
}

function recPost(path, body) {
  return netFetch(recUrl(path), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {})
  }).then(function (r) { return JSON.parse(r.text); });
}

function coverUrl(code) {
  var c = String(code).toLowerCase();
  return CFG.CDN + '/img2/s360/' + MD5(c).slice(0, 2) + '/' + c + '/cover.jpg';
}

function mapRec(it) {
  return {
    code: it.code,
    title: it[props[1]] || it.code,
    cover: coverUrl(it.code),
    duration: fmtSecs(it.duration),
    views: ''
  };
}

var Api = {
  segments: function () {
    return recPost('/users/' + userId() + '/segments', { count: 3 }).then(function (d) {
      return (d.recomms || []).filter(function (x) { return typeof x === 'string'; });
    });
  },

  items: function (q) {
    return recPost('/users/' + userId() + '/items', Object.assign({
      count: 12,
      scenario: 'home-recommended',
      included_properties: props
    }, q || {})).then(function (d) {
      return (d.recomms || []).filter(function (x) { return x && x.code; }).map(mapRec);
    });
  },

  batch: function (reqs) {
    return recPost('/batch', { requests: reqs }).then(function (arr) {
      return (arr || []).map(function (d) {
        return (d && d.recomms || []).filter(function (x) { return x && x.code; }).map(mapRec);
      });
    });
  },

  similar: function (code) {
    return recPost('/items/' + String(code).toLowerCase() + '/items', {
      count: 12,
      target_user: userId(),
      included_properties: props
    }).then(function (d) {
      return (d.recomms || []).filter(function (x) { return x && x.code; }).map(mapRec);
    });
  },

  genreLabels: function () {
    return netFetch(CFG.SITE + '/api/v1/genre-labels?locale=' + CFG.LOCALE).then(function (r) {
      return JSON.parse(r.text);
    });
  }
};

/* ------------------------------ HTML 解析 ------------------------------ */
function parseCards(html) {
  var parts = String(html).split('<div class="card"');
  var seen = Object.create(null);
  var out = [];
  for (var i = 1; i < parts.length; i++) {
    var s = parts[i];
    var codeM = s.match(/href="\/cn\/v\/([^"#?]+)"/);
    if (!codeM) continue;
    var code = codeM[1];
    if (seen[code]) continue;
    seen[code] = 1;
    var img = (s.match(/class="card__img"[^>]*src="([^"]+)"/) || [])[1] || '';
    var dur = (s.match(/class="card__dur">([^<]*)</) || [])[1] || '';
    var title = unesc((s.match(/class="card__link"[^>]*>([\s\S]*?)<\/a>/) || [])[1] || code);
    var views = '';
    var vm = s.match(/class="card__views"[\s\S]{0,400}?<\/svg>([\s\S]{0,24}?)<\/span>/);
    if (vm) views = unesc(vm[1]);
    out.push({ code: code, title: title, cover: img || coverUrl(code), duration: dur, views: views });
  }
  return out;
}

function parseDetail(html, code) {
  var d = { code: code.toUpperCase(), genres: [], actresses: [], makers: [], episodes: [], title: '', poster: '' };

  var h1 = html.match(/<h1 class="watch__title">([\s\S]*?)<\/h1>/);
  if (h1) d.title = unesc(h1[1]);

  var stat = html.match(/watch__meta--stats">([\s\S]{0,600}?)<\/div>/);
  if (stat) {
    var spans = stat[1].match(/watch__metaitem[^>]*>[\s\S]*?<\/svg>([\s\S]*?)<\/span>/g) || [];
    d.stats = spans.map(function (x) { return unesc(x.replace(/^[\s\S]*<\/svg>/, '')); }).filter(Boolean);
  }

  var pm = html.match(/player\(JSON\.parse\('((?:[^'\\]|\\.)*)'\),\s*(\d+),\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'\)/);
  if (pm) {
    d.titleId = parseInt(pm[2], 10);
    d.recBase = jsUnescape(pm[4]);
    d.recKey = pm[5];
    try {
      d.episodes = JSON.parse(jsUnescape(pm[1])).map(function (e) {
        return { name: e.name || '', number: e.number || 0, url: e.url };
      });
    } catch (e) { d.episodes = []; }
  }

  var bg = html.match(/class="player"[^>]*background-image:url\('([^']+)'\)/);
  if (bg) d.poster = bg[1];

  var info = {}, order = [];
  var re = /<div class="watch__info-row">\s*<dt>([^<]*)<\/dt>\s*<dd[^>]*>([\s\S]*?)<\/dd>/g, m;
  while ((m = re.exec(html))) {
    var key = unesc(m[1]);
    var val = unesc(m[2]);
    info[key] = val;
    order.push(key);
  }
  d.info = info;
  d.infoOrder = order;

  var cre = /<a class="chip" href="\/cn\/genres\/([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  while ((m = cre.exec(html))) d.genres.push({ slug: m[1], name: unesc(m[2]) });

  var are = /<a class="chip" href="\/cn\/actresses\/([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  while ((m = are.exec(html))) d.actresses.push({ slug: m[1], name: unesc(m[2]) });

  var mre = /<a class="chip" href="\/cn\/makers\/([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  while ((m = mre.exec(html))) d.makers.push({ slug: m[1], name: unesc(m[2]) });

  return d;
}

/* ------------------------------ 分类缓存 ------------------------------ */
var genresCache = null;
function loadGenres() {
  if (genresCache) return Promise.resolve(genresCache);
  return netFetch(CFG.SITE + '/cn/genres').then(function (r) {
    var re = /<a[^>]+href="\/cn\/genres\/([^"?#]+)"[^>]*>([\s\S]{0,120}?)<\/a>/g;
    var seen = Object.create(null), list = [], m;
    while ((m = re.exec(r.text))) {
      var slug = m[1];
      if (seen[slug]) continue;
      var label = unesc(m[2]);
      var mm = label.match(/^(.*?)\s+([\d,]+[Kk万]?)$/);
      var name = mm ? mm[1] : label;
      var count = mm ? mm[2] : '';
      if (!slug || !name || /^[\d,]+$/.test(name)) continue;
      seen[slug] = 1;
      list.push({ slug: slug, name: name, count: count });
    }
    genresCache = list;
    return list;
  });
}

/* ------------------------------ 渲染：卡片 ------------------------------ */
function cardHtml(it) {
  return '' +
    '<div class="card" data-code="' + esc(it.code) + '">' +
      '<a class="card__cover" href="#/v/' + encodeURIComponent(it.code) + '">' +
        '<img loading="lazy" src="' + esc(it.cover) + '" alt="">' +
        (it.duration ? '<span class="card__dur">' + esc(it.duration) + '</span>' : '') +
      '</a>' +
      '<div class="card__title">' + esc(it.title) + '</div>' +
      (it.views ? '<div class="card__sub"><span>' + esc(it.views) + '</span></div>' : '') +
    '</div>';
}

function gridHtml(items) {
  return '<div class="grid">' + items.map(cardHtml).join('') + '</div>';
}

function skeletonGrid(n) {
  var s = '';
  for (var i = 0; i < n; i++) s += '<div class="sk-card"><div class="skeleton"></div><div class="skeleton"></div></div>';
  return '<div class="grid">' + s + '</div>';
}

function emptyHtml(title, sub) {
  return '<div class="empty"><b>' + esc(title) + '</b>' + esc(sub || '') + '</div>';
}

function sectionHtml(title, inner, moreHref, moreText) {
  return '<section class="section">' +
    '<div class="section-head"><h2 class="section-title">' + esc(title) + '</h2>' +
    (moreHref ? '<a class="section-more" href="' + moreHref + '">' + esc(moreText || '更多 ›') + '</a>' : '') +
    '</div>' + inner + '</section>';
}

/* ------------------------------ 视图：推荐 ------------------------------ */
var homeCache = null;
var homeCacheAt = 0;

function renderHome(root) {
  document.getElementById('tbTitle').textContent = '推荐';

  if (homeCache && Date.now() - homeCacheAt < 5 * 60 * 1000) {
    root.innerHTML = homeCache;
    return;
  }

  root.innerHTML = sectionHtml('为你推荐', skeletonGrid(4)) + sectionHtml('正在加载', skeletonGrid(2));

  var uid = userId();
  var batchReq = [
    { url: 'users/' + uid + '/items', data: { count: 12, scenario: 'home-recommended', included_properties: props } }
  ];

  Promise.all([
    Api.segments().catch(function () { return []; }),
    netFetch(CFG.SITE + '/cn/new').then(function (r) { return parseCards(r.text).slice(0, 12); }).catch(function () { return []; }),
    loadGenres().catch(function () { return []; })          // 为了把中文段落名映射回分类 slug
  ]).then(function (res) {
    var segs = res[0], fresh = res[1];
    var labels = {};

    var jobs = segs.map(function (g) {
      batchReq.push({ url: 'users/' + uid + '/items', data: { count: 12, scenario: 'home-segments-items', genre: g, included_properties: props } });
    });

    return Api.genreLabels().catch(function () { return {}; }).then(function (map) {
      labels = map || {};
      return Api.batch(batchReq).catch(function () { return []; });
    }).then(function (arr) {
      var rec = arr[0] || [];
      var html = '';

      if (rec.length) {
        html += sectionHtml('为你推荐', gridHtml(rec));
      }

      for (var i = 0; i < segs.length; i++) {
        var items = arr[i + 1] || [];
        if (!items.length) continue;
        var name = labels[segs[i]] || segs[i];
        html += sectionHtml(name, '<div class="rail">' + items.map(cardHtml).join('') + '</div>',
          '#/g/' + encodeURIComponent(slugFromLabel(name, segs[i])), '全部 ›');
      }

      if (fresh.length) {
        html += sectionHtml('新发布', '<div class="rail">' + fresh.map(cardHtml).join('') + '</div>', '#/l/new', '更多 ›');
      }

      if (!html) html = emptyHtml('暂时没有内容', '请检查网络后下拉刷新');

      homeCache = html;
      homeCacheAt = Date.now();
      root.innerHTML = html;
    });
  }).catch(function (e) {
    root.innerHTML = emptyHtml('加载失败', (e && e.message) || '请稍后重试') +
      '<div style="text-align:center;padding:0 24px 24px"><button class="btn" id="retry">重新加载</button></div>';
    var b = document.getElementById('retry');
    if (b) b.onclick = function () { renderHome(root); };
  });
}

// 用中文标签尽力映射到分类 slug（首页 rail 的“全部”入口）
function slugFromLabel(label, raw) {
  if (!genresCache) return String(raw).toLowerCase().replace(/\s+/g, '-');
  for (var i = 0; i < genresCache.length; i++) {
    if (genresCache[i].name === label) return genresCache[i].slug;
  }
  return String(raw).toLowerCase().replace(/\s+/g, '-');
}

/* ------------------------------ 视图：分类 ------------------------------ */
function renderCats(root) {
  document.getElementById('tbTitle').textContent = '分类';
  var quick = [
    ['new', '新发布'], ['hot', '热门'], ['recent', '最近'],
    ['censored', '有码'], ['uncensored', '无码'], ['leaked', '无码泄露']
  ];

  root.innerHTML =
    '<div class="chips" style="padding-top:12px">' +
      quick.map(function (q) { return '<a class="chip" href="#/l/' + q[0] + '">' + esc(q[1]) + '</a>'; }).join('') +
    '</div>' +
    '<div class="section"><div class="section-head"><h2 class="section-title">全部分类</h2></div>' +
      '<div class="field" style="margin:0 14px 12px">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4.2-4.2"/></svg>' +
        '<input id="catFilter" type="search" placeholder="筛选分类，如 中出 / 巨乳" autocomplete="off">' +
      '</div>' +
      '<div id="catList">' + skeletonGrid(2) + '</div>' +
    '</div>';

  var listEl = document.getElementById('catList');
  loadGenres().then(function (list) {
    function paint(kw) {
      var q = (kw || '').trim().toLowerCase();
      var arr = !q ? list : list.filter(function (g) {
        return g.name.toLowerCase().indexOf(q) >= 0 || g.slug.indexOf(q) >= 0;
      });
      if (!arr.length) { listEl.innerHTML = emptyHtml('没有匹配的分类'); return; }
      listEl.innerHTML = '<div class="cat-grid">' + arr.map(function (g) {
        return '<a class="cat-item" href="#/g/' + encodeURIComponent(g.slug) + '">' +
          '<span>' + esc(g.name) + '</span>' +
          (g.count ? '<span class="n">' + esc(g.count) + '</span>' : '') +
        '</a>';
      }).join('') + '</div>';
    }
    paint('');
    var input = document.getElementById('catFilter');
    input.addEventListener('input', function () { paint(input.value); });
  }).catch(function (e) {
    listEl.innerHTML = emptyHtml('分类加载失败', (e && e.message) || '');
  });
}

/* ------------------------------ 视图：分类列表 / 站点列表 ------------------------------ */
var listState = null;

function renderGenre(root, slug) {
  var title = slug;
  root.innerHTML =
    '<div class="section" style="margin-top:0">' +
      '<div class="section-head"><h2 class="section-title" id="gTitle">' + esc(title) + '</h2></div>' +
      '<div id="gGrid">' + skeletonGrid(4) + '</div>' +
      '<div class="loading-more" id="gMore"></div>' +
    '</div>';

  var gridEl = document.getElementById('gGrid');
  var moreEl = document.getElementById('gMore');
  var page = 0, hasMore = true, loading = false;

  function load() {
    if (loading || !hasMore) return Promise.resolve();
    loading = true;
    moreEl.textContent = '加载中…';
    page += 1;
    return netFetch(CFG.SITE + '/cn/genres/' + encodeURIComponent(slug) + '?page=' + page).then(function (r) {
      var items = parseCards(r.text);
      if (page === 1) {
        var h1 = r.text.match(/<h1[^>]*>([\s\S]{0,80}?)<\/h1>/);
        if (h1) document.getElementById('gTitle').textContent = unesc(h1[1]) || title;
        var total = r.text.match(/([\d,]+)个/);
        if (total) document.getElementById('gTitle').textContent += ' · ' + total[1];
        gridEl.innerHTML = items.length ? '<div class="grid" id="gInner">' + items.map(cardHtml).join('') + '</div>' : emptyHtml('该分类暂无内容');
      } else if (items.length) {
        var inner = document.getElementById('gInner');
        if (inner) inner.insertAdjacentHTML('beforeend', items.map(cardHtml).join(''));
      }
      hasMore = items.length >= 10 && page < 60;
      if (!items.length) hasMore = false;
      moreEl.textContent = hasMore ? '' : (page === 1 ? '' : '已经到底了');
    }).catch(function (e) {
      moreEl.textContent = '加载失败：' + ((e && e.message) || '');
      hasMore = false;
    }).then(function () { loading = false; });
  }

  load().then(function () {
    bindInfinite(document.getElementById('gMore'), function () { load(); });
  });
}

function renderList(root, key) {
  var name = LIST_NAME[key] || key;
  document.getElementById('tbTitle').textContent = name;

  root.innerHTML =
    '<div class="section" style="margin-top:0">' +
      '<div id="lGrid">' + skeletonGrid(4) + '</div>' +
      '<div class="loading-more" id="lMore"></div>' +
    '</div>';

  var gridEl = document.getElementById('lGrid');
  var moreEl = document.getElementById('lMore');
  var path = CFG.LIST_PATHS[key] || ('/cn/' + key);
  var page = 0, hasMore = true, loading = false;

  function load() {
    if (loading || !hasMore) return Promise.resolve();
    loading = true;
    page += 1;
    var url = CFG.SITE + path + (page > 1 ? '?page=' + page : '');
    return netFetch(url).then(function (r) {
      var items = parseCards(r.text);
      if (page === 1) gridEl.innerHTML = items.length ? '<div class="grid" id="lInner">' + items.map(cardHtml).join('') + '</div>' : emptyHtml('暂无内容');
      else if (items.length) {
        var inner = document.getElementById('lInner');
        if (inner) inner.insertAdjacentHTML('beforeend', items.map(cardHtml).join(''));
      }
      hasMore = items.length >= 10 && page < 60;
      moreEl.textContent = hasMore ? '' : '已经到底了';
    }).catch(function (e) {
      moreEl.textContent = '加载失败：' + ((e && e.message) || '');
      hasMore = false;
    }).then(function () { loading = false; });
  }

  load().then(function () {
    bindInfinite(document.getElementById('lMore'), function () { load(); });
  });
}

/* ------------------------------ 视图：搜索 ------------------------------ */
var searchState = { kw: '', page: 0, hasMore: true, loading: false };

function renderSearch(root, kw) {
  document.getElementById('tbTitle').textContent = '搜索';
  kw = kw || '';

  var hot = ['JUR', 'SNOS', 'FC2', '中出', '巨乳', '无码'];
  root.innerHTML =
    '<div class="field" style="margin-top:12px">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4.2-4.2"/></svg>' +
      '<input id="qInput" type="search" enterkeyhint="search" placeholder="搜索番号、标题、女演员、制作商" autocomplete="off" value="' + esc(kw) + '">' +
      '<button id="qGo" style="color:#e83e8c;font-size:14px;font-weight:600">搜索</button>' +
    '</div>' +
    '<div class="chips" id="hotChips">' +
      hot.map(function (h) { return '<a class="chip" href="#/s/' + encodeURIComponent(h) + '">' + esc(h) + '</a>'; }).join('') +
    '</div>' +
    '<div class="section" style="margin-top:16px"><div id="sResult"></div><div class="loading-more" id="sMore"></div></div>';

  var input = document.getElementById('qInput');
  var resultEl = document.getElementById('sResult');
  var moreEl = document.getElementById('sMore');

  function go() {
    var v = input.value.trim();
    if (!v) { toast('请输入关键词'); return; }
    var hash = '#/s/' + encodeURIComponent(v);
    if (location.hash === hash) renderSearch(document.getElementById('view'), v);
    else location.hash = hash;
  }
  document.getElementById('qGo').onclick = go;
  input.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); go(); } });

  if (!kw) {
    resultEl.innerHTML = emptyHtml('搜点什么', '支持番号（如 JUR-889）、中文标题、女演员名');
    return;
  }

  searchState = { kw: kw, page: 0, hasMore: true, loading: false };
  resultEl.innerHTML = skeletonGrid(4);

  function load() {
    if (searchState.loading || !searchState.hasMore) return Promise.resolve();
    searchState.loading = true;
    searchState.page += 1;
    var url = CFG.SITE + '/cn/search?keyword=' + encodeURIComponent(kw) +
      (searchState.page > 1 ? '&page=' + searchState.page : '');
    return netFetch(url).then(function (r) {
      var items = parseCards(r.text);
      if (searchState.page === 1) {
        if (!items.length) { resultEl.innerHTML = emptyHtml('没有找到结果', '换个关键词试试'); return; }
        resultEl.innerHTML = '<div class="grid" id="sInner">' + items.map(cardHtml).join('') + '</div>';
      } else if (items.length) {
        var inner = document.getElementById('sInner');
        if (inner) inner.insertAdjacentHTML('beforeend', items.map(cardHtml).join(''));
      }
      searchState.hasMore = items.length >= 10 && searchState.page < 30;
      moreEl.textContent = searchState.hasMore ? '' : (searchState.page > 1 ? '没有更多了' : '');
    }).catch(function (e) {
      resultEl.innerHTML = emptyHtml('搜索失败', (e && e.message) || '');
      searchState.hasMore = false;
    }).then(function () { searchState.loading = false; });
  }

  load().then(function () {
    bindInfinite(document.getElementById('sMore'), function () { load(); });
  });
}

/* ------------------------------ 视图：详情 ------------------------------ */
function renderDetail(root, code) {
  document.getElementById('tbTitle').textContent = '详情';
  root.innerHTML = '<div class="detail-hero"><div class="skeleton" style="width:100%;height:100%;border-radius:0"></div></div>' +
    '<div class="detail-body"><div class="skeleton" style="height:20px;margin-bottom:10px"></div>' +
    '<div class="skeleton" style="height:14px;width:60%"></div></div>';

  netFetch(CFG.SITE + '/cn/v/' + encodeURIComponent(code)).then(function (r) {
    var d = parseDetail(r.text, code);
    document.getElementById('tbTitle').textContent = d.code || code.toUpperCase();

    var poster = d.poster || coverUrl(code);
    var infoRows = (d.infoOrder || []).map(function (k) {
      var v = d.info[k] || '';
      if (!v) return '';
      return '<div class="info-row"><dt>' + esc(k) + '</dt><dd>' + esc(v) + '</dd></div>';
    }).join('');

    var genreChips = d.genres.map(function (g) {
      return '<a class="chip" href="#/g/' + encodeURIComponent(g.slug) + '">' + esc(g.name) + '</a>';
    }).join('');

    var epBtns = d.episodes.length > 1 ? '<div class="chips" style="padding:12px 0 0">' +
      d.episodes.map(function (e, i) {
        return '<button class="chip" data-ep="' + i + '">第 ' + (i + 1) + ' 集</button>';
      }).join('') + '</div>' : '';

    root.innerHTML =
      '<div class="detail-hero">' +
        '<img class="detail-hero__poster" src="' + esc(poster) + '" alt="">' +
        '<button class="detail-hero__play" id="playBtn" aria-label="播放"><span>' +
          '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg></span></button>' +
      '</div>' +
      '<div class="detail-body">' +
        '<h1 class="detail-title">' + esc(d.title || d.code) + '</h1>' +
        '<div class="detail-meta">' + (d.stats || []).map(function (s) { return '<span>' + esc(s) + '</span>'; }).join('') + '</div>' +
        '<div class="detail-actions">' +
          '<button class="btn primary" id="playBtn2">立即播放</button>' +
          '<a class="btn" href="' + esc(CFG.SITE + '/cn/v/' + encodeURIComponent(code)) + '" target="_blank" rel="noopener" id="openWeb">网页版</a>' +
        '</div>' +
        epBtns +
      '</div>' +
      '<dl class="info-list">' + infoRows + '</dl>' +
      (genreChips ? '<div class="section"><div class="section-head"><h2 class="section-title">类别</h2></div><div class="chips">' + genreChips + '</div></div>' : '') +
      '<div class="section"><div class="section-head"><h2 class="section-title">你可能喜欢</h2></div><div id="relGrid">' + skeletonGrid(2) + '</div></div>';

    function play(idx) {
      var ep = d.episodes[idx || 0];
      if (!ep || !ep.url) { toast('暂无播放源'); return; }
      openPlayer(ep.url, d.title || d.code, d.code);
    }

    document.getElementById('playBtn').onclick = function () { play(0); };
    document.getElementById('playBtn2').onclick = function () { play(0); };
    Array.prototype.forEach.call(root.querySelectorAll('[data-ep]'), function (b) {
      b.onclick = function () { play(parseInt(b.getAttribute('data-ep'), 10)); };
    });

    Api.similar(code).then(function (items) {
      var el = document.getElementById('relGrid');
      if (!el) return;
      el.innerHTML = items.length ? '<div class="grid">' + items.map(cardHtml).join('') + '</div>' : emptyHtml('暂无相关推荐');
    }).catch(function () {
      var el = document.getElementById('relGrid');
      if (el) el.innerHTML = '';
    });
  }).catch(function (e) {
    root.innerHTML = emptyHtml('详情加载失败', (e && e.message) || '');
  });
}

/* ------------------------------ 播放器 ------------------------------ */
function openPlayer(url, title, code) {
  if (Native.player) {
    window.webkit.messageHandlers.player.postMessage({ url: url, title: title || '', code: code || '' });
    return;
  }
  var wrap = document.createElement('div');
  wrap.className = 'player-wrap';
  wrap.innerHTML =
    '<div class="pv-head"><b>' + esc(title || '播放') + '</b><button class="pv-close">关闭</button></div>' +
    '<iframe src="' + esc(url) + '" allow="autoplay; fullscreen; encrypted-media; picture-in-picture" ' +
      'sandbox="allow-scripts allow-same-origin allow-forms allow-presentation" allowfullscreen></iframe>';
  wrap.querySelector('.pv-close').onclick = function () { wrap.remove(); };
  document.body.appendChild(wrap);
}

/* ------------------------------ 路由 ------------------------------ */
function bindInfinite(sentinel, fn) {
  if (!sentinel) return null;
  if (!('IntersectionObserver' in window)) return null;
  var busy = false;
  var io = new IntersectionObserver(function (entries) {
    if (busy) return;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].isIntersecting) {
        busy = true;
        Promise.resolve(fn()).then(function () {
          setTimeout(function () { busy = false; }, 250);
        });
        return;
      }
    }
  }, { rootMargin: '500px 0px' });
  io.observe(sentinel);
  return io;
}

function currentRoute() {
  var h = location.hash || '#/';
  var m;
  if ((m = h.match(/^#\/v\/([^/?]+)/))) return { name: 'detail', code: decodeURIComponent(m[1]) };
  if ((m = h.match(/^#\/g\/([^/?]+)/))) return { name: 'genre', slug: decodeURIComponent(m[1]) };
  if ((m = h.match(/^#\/l\/([^/?]+)/))) return { name: 'list', key: decodeURIComponent(m[1]) };
  if ((m = h.match(/^#\/s\/([^?]*)/))) return { name: 'search', kw: decodeURIComponent(m[1] || '') };
  if (h === '#/search') return { name: 'search', kw: '' };
  if (h === '#/cats') return { name: 'cats' };
  return { name: 'home' };
}

function syncChrome(route) {
  var tabbar = document.getElementById('tabbar');
  var back = document.getElementById('backBtn');
  var view = document.getElementById('view');
  var tab = route.name === 'detail' ? null :
    route.name === 'cats' || route.name === 'genre' ? 'cats' :
    route.name === 'search' ? 'search' :
    route.name === 'list' ? null : 'home';

  Array.prototype.forEach.call(tabbar.querySelectorAll('a'), function (a) {
    a.classList.toggle('is-on', a.getAttribute('data-tab') === tab);
  });
  tabbar.hidden = route.name === 'detail';
  view.classList.toggle('no-tab', route.name === 'detail');
  back.hidden = !(route.name === 'detail' || route.name === 'genre' || route.name === 'list');
  back.onclick = function () {
    if (history.length > 1) history.back();
    else location.hash = '#/';
  };
}

function route() {
  var r = currentRoute();
  var root = document.getElementById('view');
  root.scrollTop = 0;
  window.scrollTo(0, 0);
  syncChrome(r);

  switch (r.name) {
    case 'detail': renderDetail(root, r.code); break;
    case 'genre': renderGenre(root, r.slug); break;
    case 'list': renderList(root, r.key); break;
    case 'search': renderSearch(root, r.kw); break;
    case 'cats': renderCats(root); break;
    default: renderHome(root);
  }
}

function boot() {
  if (window.__APP__) {
    // App 内：禁用长按弹菜单、双击缩放
    document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
  }
  Theme.init();
  document.getElementById('themeBtn').onclick = function () { Theme.toggle(); };
  document.getElementById('searchBtn').onclick = function () {
    location.hash = '#/search';
  };
  window.addEventListener('hashchange', route);
  route();
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
