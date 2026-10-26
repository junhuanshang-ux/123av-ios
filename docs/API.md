# 123AV 接口与分类逆向分析

> 分析时间：2026-10-26 · 全部结论均来自真实请求（本机实测），不是猜测。
> 站点：`https://123av.com`（Cloudflare 前置，中文前台 `/cn`）
> 结论可直接用于第三方客户端；接口为前端逆向所得，站点改版后可能失效。

---

## 0. 一句话结论

站点是 **服务端渲染（Alpine.js 局部水合）+ 一个签名推荐服务**：

| 层 | 地址 | 作用 | 是否需要签名 |
| --- | --- | --- | --- |
| 页面 | `https://123av.com/cn/...` | 列表/详情/搜索，HTML 直出 | 否 |
| 业务 API | `https://123av.com/api/v1/...` | 标签字典、登录、关注、播放计数 | 否 |
| 推荐 API | `https://rec2.123av.com/...` | 个性化推荐、相似推荐、分页游标 | **是** |
| 图床 | `https://icdn.123av.me/...` | 封面 / 预览图 | 否（无需 Referer） |
| 播放 | `https://sadie-shop.site/stream` → `*.maya-shop.site` 等 | 解析出 HLS(m3u8) | 否（m3u8 需 Referer） |

**没有** 任何“一次性返回全站视频列表”的官方 JSON 接口——列表数据只能从 HTML 里取，
或者走推荐服务的个性化接口（覆盖首页/相似推荐，不能做全量翻页）。

---

## 1. 站点架构

- 前端：Alpine.js（`js/common/*.js` 拆模块，`app-dev-*.js` 单文件 ~285KB，**未混淆**）
- 后端：Laravel 风格（`/api/v1/...` 404 返回 `{"message":"The route api/v1/xxx could not be found."}`）
- 前端组件（Alpine `x-data`）：
  `header` / `dropdown` / `auth` / `captcha` / `player` / `preview` / `save` /
  `recSections` / `recommendation` / `search` / `filters`
- 跨域：`/api/v1/*` 与所有页面都会**回显请求的 Origin**（`Access-Control-Allow-Origin: <origin>`，
  无 Origin 时返回 `null`），`rec2` 返回 `Access-Control-Allow-Origin: null` + `allow-credentials: true`

---

## 2. 页面路由（SSR，可直接抓 HTML）

| 用途 | 路径 | 备注 |
| --- | --- | --- |
| 首页 | `/cn` | 顶部推荐 + 新发布 + 最近 |
| 新发布 | `/cn/new?page=N` | 每页 12 条 |
| 热门 | `/cn/hot` | |
| 最近 | `/cn/recent?page=N` | |
| 趋势 | `/cn/all?sort=today` / `week` / `month` | |
| 有码 | `/cn/censored` | |
| 无码 | `/cn/uncensored` | |
| 无码泄露 | `/cn/uncensored-leaked` | |
| 分类索引 | `/cn/genres` | 一页列出 499 个分类 |
| 分类列表 | `/cn/genres/{slug}?page=N` | 12 条/页，标题里带 `125,880个` 总数 |
| 女演员 | `/cn/actresses`、`/cn/actresses/{slug}` | |
| 制作商 | `/cn/makers`、`/cn/makers/{slug}` | |
| 系列 | `/cn/series`、`/cn/series/{slug}` | |
| 标签 | `/cn/tags/{tag}` | |
| 搜索 | `/cn/search?keyword=xxx&page=N` | 另有隐藏参数 `year`、`actress`、`sort=relevant` |
| 详情 | `/cn/v/{code}` | code 为小写番号，如 `jur-889` |

### 2.1 卡片 HTML 结构（列表页通用）

```html
<div class="card" x-data="save({ type: 'title', id: 1166477, saved: false })">
  <div class="card__poster" x-data="preview" data-preview="https://icdn.123av.me/preview/ac/xxx/preview.png">
    <a class="card__cover" href="/cn/v/caribbeancom-102626-001">
      <img class="card__img" src="https://icdn.123av.me/img2/s360/ac/caribbeancom-102626-001/cover.jpg" loading="lazy">
      <span class="card__dur">1:07:06</span>
    </a>
  </div>
  <div class="card__body">
    <h3 class="card__title"><a class="card__link" href="/cn/v/...">标题</a></h3>
    <div class="card__meta"><span>49 分钟 6 秒前</span><span class="dot"></span>
      <span class="card__views" title="观看">…450</span></div>
  </div>
</div>
```

抓取要点：按 `<div class="card"` 切块，取 `href="/cn/v/([^"]+)"`、`card__img src`、`card__dur`、`card__link` 文本。

### 2.2 详情页结构

```html
<h1 class="watch__title">JUR-889 — 标题…</h1>
<div class="watch__meta watch__meta--stats">…3 天 17 小时前…99.5K次观看…</div>

<div class="watch__main" x-data="player(JSON.parse('[{"number":1,"name":"1",
     "url":"https://sadie-shop.site/e/7N1ZQ0?poster=https%3A%2F%2Ficdn.123av.me%2F..."}]'),
     1165995, 'jur-889', 'https://rec2.123av.com', 'e8bcc533-bc38-4a33-af0e-678d38237754')">

<dl class="watch__info">
  <div class="watch__info-row"><dt>代码</dt><dd>JUR-889</dd></div>
  <div class="watch__info-row"><dt>类型</dt><dd><a href="/cn/censored">有码</a></dd></div>
  <div class="watch__info-row"><dt>发布日期</dt><dd>2026-10-22</dd></div>
  <div class="watch__info-row"><dt>时长</dt><dd>2:07:24</dd></div>
  <div class="watch__info-row"><dt>演员</dt><dd class="chips"><a class="chip" href="/cn/actresses/shinohara-iyo">…</a></dd></div>
  <div class="watch__info-row"><dt>制作商</dt><dd class="chips"><a class="chip" href="/cn/makers/madonna">…</a></dd></div>
  <div class="watch__info-row"><dt>类别</dt><dd class="chips"><a class="chip" href="/cn/genres/creampie">中出</a>…</dd></div>
  <div class="watch__info-row"><dt>标签</dt><dd class="chips"><a class="chip" href="/cn/tags/jur">JUR</a></dd></div>
</dl>
```

`player(episodes, titleId, code, recBase, recKey)` 的 5 个参数分别是：
**播放源数组、视频内部 ID、番号、推荐服务地址、推荐服务签名密钥**。

---

## 3. 业务 API（`https://123av.com/api/v1`，无需签名）

| 方法 | 路径 | 说明 | 实测 |
| --- | --- | --- | --- |
| GET | `/api/v1/genre-labels?locale=zh-CN` | 英文分类键 → 中文标签（479 条） | 200，21KB |
| GET | `/api/v1/auth/me` | 当前登录用户 | 需 Cookie |
| POST | `/api/v1/auth/login\|register\|reset\|logout` | 账号体系（含 Cloudflare Turnstile `data-sitekey=0x4AAAAAADkzNCt1vIP70it4`） | 需验证码 |
| POST | `/api/v1/follows/follow\|unfollow` | 收藏/关注 | 需登录 |
| GET | `/api/v1/me/follows/status` | 关注状态 | 需登录 |
| POST | `/api/v1/titles/{titleId}/view` | 播放计数（`credentials: same-origin`） | 200 |

`/api/v1/genre-labels` 实测片段：

```json
{"Incest":"乱伦","Creampie":"中出","High Vision":"高视力","Amateur":"业余","Maid":"女佣",
 "Fair Skin":"白皙的皮肤","Bondage":"束缚","Big Tits":"大胸部","Black Hair":"黑发", ...}
```

> `locale=en` 返回 `{}`（英文名本身就是键，无需映射）。

---

## 4. 推荐 API（`rec2`，必须签名）★

详情页 / 首页都会把 `recBase`（`https://rec2.123av.com`）和 `recKey` 下发给前端，
`recKey` 目前全站一致：`e8bcc533-bc38-4a33-af0e-678d38237754`。

### 4.1 签名算法（站点前端原文逻辑）

```js
function simpleHash(input) {           // Java 风格 32 位字符串哈希
  let hash = 0;
  for (let i = 0; i < input.length; i++) {
    hash = (hash << 5) - hash + input.charCodeAt(i);
    hash |= 0;
  }
  return (hash >>> 0).toString(16);     // 无符号十六进制，小写
}

function signedUrl(base, key, path) {
  const timestamp = Math.floor(Date.now() / 1000).toString();   // 秒
  const signature = simpleHash(key + timestamp + navigator.userAgent);
  return `${base}${path}?timestamp=${timestamp}&signature=${signature}`;
}
```

- **signature 的输入包含 UA**：服务端用请求头里的 `User-Agent` 重算，所以
  **请求头 UA 必须和算签名时的 UA 完全一致**（实测自定义 UA 也能通过，见下）。
- `timestamp` 是秒级；有效期实测 ≥ 十几分钟窗口，建议每次现算。

### 4.2 端点

| 方法 | 路径 | 请求体 | 返回 |
| --- | --- | --- | --- |
| POST | `/users/{userId}/segments` | `{"count":3}` | `{"id":0,"recomms":["Big Tits","Solowork","Lewd/Hard"]}` |
| POST | `/users/{userId}/items` | `{"count":12,"scenario":"home-recommended","included_properties":["code","title_cn","duration"]}` | `{"recomm_id":"…","recomms":[{"code":"SNOS-416-Uncensored-Leaked","title_cn":"…","duration":"6668"}]}` |
| POST | `/batch` | `{"requests":[{"url":"users/{id}/items","data":{…}}, …]}` | 与请求顺序对应的数组 |
| POST | `/next/items/{recommId}` | `{"count":24}` | 同 items（游标翻页） |
| POST | `/items/{code}/items` | `{"count":12,"target_user":"{userId}","included_properties":[…]}` | 相似推荐 |
| POST | `/detailviews/{userId}/{code}` | `{}` | 埋点，无返回 |

`scenario` 取值：`home-recommended`（首页为你推荐）、`home-segments-items`（按分类段落）、
`watch-similar`（详情页相似）。

`userId` 是前端 `localStorage.user_id` 里的随机 UUID（不存在就 `genUserId()` 生成 36 位 v4），
**服务端不校验其真伪**，随便给一个合法 UUID 就能拿到推荐流。

### 4.3 实测（Node 复现，`tools/rec_api_probe.mjs`）

```bash
POST https://rec2.123av.com/users/3f2b9c1e-7a4d-4c2b-8f11-9d0c1b2a3e45/segments?timestamp=1793015894&signature=59dbd9ff
Content-Type: application/json
User-Agent: <与签名一致的 UA>

{"count":3}

→ 200 {"id":0,"recomms":["Big Tits","Solowork","Lewd/Hard"]}
```

```bash
POST https://rec2.123av.com/users/{uid}/items?timestamp=…&signature=…
{"count":4,"scenario":"home-recommended","included_properties":["code","title_cn","duration"]}

→ 200 {"recomm_id":"2bbeba3e8686560309a0b4e5f2e7b308","recomms":[
   {"code":"SNOS-416-Uncensored-Leaked","title_cn":"趁父母不在家…","duration":"6668"},
   {"code":"STARS-649-Uncensored-Leaked","title_cn":"首次肛门开发…","duration":"7673"}]}
```

> `duration` 是**秒**（6668 → 1:51:08），前端用 `h:mm:ss` 显示。
> 返回里**没有封面地址**，要按第 6 节的 md5 规则自己拼。

---

## 5. 播放链路（重点）★

```
/cn/v/{code}                              HTML 里带 episodes[]
   ↓  episode.url = https://sadie-shop.site/e/{id}?poster=...
https://sadie-shop.site/e/{id}            1638 字节的 plyr + hls.js 壳
   ↓  JS: GET {origin}/stream?<原样 query>&id={id}
https://sadie-shop.site/stream?id=7N1ZQ0
   → 200 {"status":"ok","media":{
        "stream":"https://jzxz.maya-shop.site/oo5/XEn0…/video.m3u8",
        "vtt":"https://jzxz.maya-shop.site/oo5/XEn0…/preview.vtt"}}
   ↓  GET m3u8（必须带 Referer: https://sadie-shop.site/）
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2816000,RESOLUTION=1280x720
qc/v.m3u8            ← 相对路径，正片分片列表（VOD，3 秒/片）
```

实测细节：

| 现象 | 结论 |
| --- | --- |
| `/stream` 不带 Referer / 不带 UA | 均 200（不校验） |
| m3u8 **不带** Referer | **403 Cloudflare**（`Attention Required!`） |
| m3u8 **带** `Referer: https://sadie-shop.site/` | 200 `application/vnd.apple.mpegurl` |
| UA 是否影响 m3u8 | 不影响（手机 UA / 桌面 UA 都放行） |
| `m3u8` 域名 | 每次轮换：`jzxz.maya-shop.site`、`e625.realpuremind.site`、`ek9n.mason-studio.site`… |
| episode 的 `id`（如 `7N1ZQ0`、`NL680Y`） | **会过期**，必须每次从详情页重新解析，不能长期缓存 |
| 多集 | `episodes` 数组多个元素（如 FC2 有第 1、2 集），各自独立 id |

> 结论：**原生播放器（AVPlayer）要用这套 URL，必须能自定义 Referer 请求头**；
> 最稳的做法是直接用 WKWebView 打开 embed 页（浏览器天然带对 Referer），
> 本项目的 iOS 客户端就是这么做的（`PlayerViewController.swift`）。
> embed 页里那段落弹窗脚本对 `document.referrer` 是 `123av.com` 才跳过，
> 客户端里用“拦截 window.open + 只允许原站导航”即可完全屏蔽。

---

## 6. 封面 / 预览图（无需 Referer）

```
封面    https://icdn.123av.me/img2/s360/{md5(code)[:2]}/{code}/cover.jpg     # 360 宽
大图    https://icdn.123av.me/img2/s500/{md5(code)[:2]}/{code}/cover.jpg     # 详情页用
预览    https://icdn.123av.me/preview/{md5(code)[:2]}/{code}/preview.png     # 悬停小视频底图
```

- `code` 必须**小写**；`{md5(code)[:2]}` 是小写十六进制前 2 位。
- 例：`jur-889` → `md5=2477455feb…` → `https://icdn.123av.me/img2/s360/24/jur-889/cover.jpg`（实测 200）
- 图片不需要 Referer / Cookie，直接 `<img>` 即可。

---

## 7. 分类体系

### 7.1 导航层级（首页 `/cn`）

```
新 / 热门 / 最近
趋势：今天(today) 本周(week) 本月(month)
类型：有码(censored) 无码(uncensored) 无码泄露(uncensored-leaked)
集合：类别(genres) 女演员(actresses) 制作商(makers) 系列(series)
业余：SIRO LUXU 200GANA PRESTIGE ORECO S-CUTE ARA 390JAC
无码：FC2 HEYZO 1pondo Caribbeancom 10musume Pacopacomama Tokyo Hot XXX-AV
```

后两组都是 `tags/*` 或 `makers/*` 的别名入口，不是独立分类维度。

### 7.2 分类数量

| 来源 | 数量 |
| --- | --- |
| `/cn/genres` 页面里的分类链接（slug + 中文名 + 影片数） | **499** |
| `/api/v1/genre-labels` 英文键→中文标签 | **479** |
| 全站分类影片数合计（含重复计数） | 约 690 万条次 |

完整清单已导出：**`docs/categories.json`**（按影片数倒序，含 `labels` 映射表）。

前 20（影片数）：

```
solowork 179,692 · creampie 中出 167,102 · big-tits 大胸部 125,880
married-womanhousewife 已婚女性/家庭主妇 92,875 · amateur 业余 89,911
high-vision 高视力 60,380 · e22f5b4c15 口交 51,811 · beautiful-girl 美丽的女孩 48,959
beautiful-breasts 美丽的乳房 42,398 · slender 苗条 41,868 · gonzo 37,982
slut 荡妇 37,704 · threesome-foursome 3P/4P 34,867 · squirting 喷出 32,121
digimo 数字的 31,844 · cuckold-cuckolded-ntr 30,844 · exclusive 独家的 27,607
over-4-hours 4小时或以上 26,716 · paizuri 乳交 25,889 · cowgirl 女牛仔 24,913
```

⚠️ 注意 slug 与中文名**不是**可推导关系（`creampie`→中出，`big-tits`→大胸部，
而 `e22f5b4c15`、`7889ef8307` 这种是纯哈希 slug），**必须用站点给的映射表**。

---

## 8. 做第三方客户端的注意事项

1. **UA 一致性**：rec2 签名包含 UA，请求头 UA 与签名 UA 必须一致（本项目在
   `app.js` 里统一用 `CFG.UA`，原生桥按 JS 传的 header 原样发送）。
2. **跨域**：站点回显 Origin，所以 `file://` 页面（Origin: null）反而能直接 fetch；
   iOS 客户端更稳的做法是**用原生 URLSession 代理请求**（本项目 `NetBridge.swift`）。
3. **Referer**：只有 HLS 需要 `https://sadie-shop.site/`；接口/页面/图片都不校验。
4. **播放源时效**：`episode.id` 会过期，详情页必须现拉；不要在本地长期存 m3u8。
5. **频率**：列表页 12 条/页、分类页最多翻到第 60 页（本项目按此限量），别做全站遍历。
6. **Cloudflare**：页面/接口都在 CF 后面，UA 为空或异常 UA 可能被挑战。
7. **合规**：内容为 18+，接口为逆向所得、无授权文档，仅供个人学习研究；不要公开分发或商用。

---

## 9. 复现脚本（本仓库 `tools/`）

| 脚本 | 作用 |
| --- | --- |
| `tools/rec_api_probe.mjs` | 推荐 API 签名 + 调用（segments / items） |
| `tools/site_api_probe.mjs` | genre-labels、列表页、搜索端点探测 |
| `tools/detail_probe.mjs` | 详情页 player 数据解析 + embed 页分析 |
| `tools/stream_probe.mjs` | 详情 → `/stream` → m3u8 全链路 |
| `tools/hls_probe.mjs` | m3u8 / 分片可达性与 Referer 校验 |
| `tools/search_probe.mjs` | 搜索参数（`keyword=`）与 Referer 放行实验 |
| `tools/cors_probe.mjs` | 跨域行为（回显 Origin → `file://` 可直连） |
| `tools/dump_categories.mjs` | 导出 `docs/categories.json` |

细节见 `tools/README.md`。
