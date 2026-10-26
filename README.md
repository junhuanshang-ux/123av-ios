# 123AV · iOS 客户端（含站点接口逆向分析）

把 `https://123av.com/cn` 做成一个能装进 iPhone 的 App。仓库里同时包含**接口分析**与**客户端源码**。

| 交付物 | 路径 | 说明 |
| --- | --- | --- |
| 接口/分类分析报告 | [`docs/API.md`](docs/API.md) | 推荐 API 签名算法、播放链路、封面规则、分类体系，全部实测 |
| 分类全量数据 | [`docs/categories.json`](docs/categories.json) | 499 个分类（slug + 中文名 + 影片数）+ 479 条标签映射 |
| 客户端前端 | `www/` | 原生手感的三 tab 应用（推荐/分类/搜索）+ 详情页，纯静态、离线可跑 |
| iOS 原生壳 | `Sources/` | WKWebView + 原生网络桥 + 全屏播放器（4 个 Swift 文件，零第三方依赖） |
| 构建 | `scripts/build-ipa.sh` | macOS 上一条命令出**未签名 IPA**（不用 Xcode 工程文件） |
| CI | `.github/workflows/build-ipa.yml` | 没 Mac 也能出 IPA：push 到 GitHub 直接拿产物 |
| 免构建方案 | `webclip/123AV.mobileconfig` | 描述文件，装完桌面就有全屏图标 |

实测截图：`docs/screenshots/`（首页 / 分类 / 详情 / 播放器）

---

## 一、最快用上（不用 Mac、不用签名）

`webclip/123AV.mobileconfig` 是一个 iOS 描述文件，里面带分类图标。

1. 把文件传到 iPhone（AirDrop、iCloud 云盘、微信文件传输、局域网 `python3 -m http.server` 任一都行）
2. 手机上点开 → 设置里「已下载描述文件」→ **安装**
3. 回到桌面，出现 **123AV** 图标，点开即全屏打开站点（无 Safari 地址栏）

> 这只相当于一个全屏书签；想要真正的 App（离线 UI、原生播放器、无广告元素）看下面。

---

## 二、出 IPA

### 方案 A：GitHub Actions（没有 Mac 也能出）

```bash
cd 123AV-iOS
git init && git add -A && git commit -m "123AV iOS app"
# 推到你的 GitHub 仓库（本目录即仓库根）
```

- 打开仓库 **Actions → build-ipa → Run workflow**
- 跑完在 run 页面的 **Artifacts** 下载 `123AV-unsigned-ipa`
- 里面是 `123AV-unsigned.ipa` 和 `123AV.app`

工作流用的是 `macos-14` runner + Xcode，`scripts/build-ipa.sh` 全自动编译打包，
不需要签名证书（侧载工具会重新签）。

### 方案 B：本机 macOS

```bash
cd 123AV-iOS
chmod +x scripts/build-ipa.sh
./scripts/build-ipa.sh
# 产物：dist/123AV-unsigned.ipa
```

可覆盖的参数：

```bash
APP_NAME=MyApp BUNDLE_ID=com.me.myapp VERSION=1.0.1 ./scripts/build-ipa.sh
```

### 方案 C：在 Windows 上把已有的 .app 打包成 IPA

```powershell
python tools/pack_ipa.py pack build/Payload/123AV.app dist/123AV.ipa
python tools/pack_ipa.py verify dist/123AV-unsigned.ipa   # 结构自检
```

---

## 三、安装到 iPhone

| 工具 | 说明 |
| --- | --- |
| **Sideloadly**（Win/Mac） | 连数据线 → 选 ipa → 填 Apple ID → Start。免费账号签名 **7 天**过期，重连重签即可 |
| **AltStore / SideStore** | 装到手机上，7 天自动续签（需同一 Wi-Fi 下的 AltServer） |
| **TrollStore** | iOS 14.0–16.6.1 / 17.0 的部分版本，可直接装 `123AV.app`（或 ipa），**永久签名**，无需 Apple ID |
| **企业签名 / 自签证书** | 有证书的话直接重签：`codesign -f -s "iPhone Distribution: XXX" Payload/123AV.app` |

装完首次打开如果提示"未受信任的开发者"，去「设置 → 通用 → VPN与设备管理」信任该证书。

---

## 四、本地预览（不用手机、不用 Mac）

改 UI 的时候直接看效果：

```bash
node scripts/dev-server.mjs        # 需要 Node 18+
# 浏览器打开 http://127.0.0.1:8787/
```

`dev-server.mjs` 会：静态托管 `www/`，并提供 `/p?u=` 跨域代理（站点接口只回
`Access-Control-Allow-Origin: null`，浏览器里必须代理才能调）。App 内不需要它。

用 Chrome 手机模式（430×932）看，就是 iPhone 上的样子。

---

## 五、App 是怎么工作的

```
┌──────────────── iPhone ────────────────┐
│  WebAppViewController (WKWebView)      │
│   └─ file://…/www/index.html           │  前端：列表/分类/搜索/详情
│        │                               │
│        ├─ fetch? 不行 ✗                │  file:// 页面直接被 CORS 拦
│        └─ window.webkit.messageHandlers│
│              .net.postMessage(...)     │
│                    ↓                   │
│  NetBridge (URLSession)  ──→ 123av.com │  原生发请求：统一 UA + Referer
│                          ──→ rec2…     │  返回 base64 文本 → JS 解析
│                                        │
│  点"播放" → PlayerViewController        │  全屏 WKWebView 打开 embed 页
│             （拦 window.open / 外链）   │  只允许原站域名导航
└────────────────────────────────────────┘
```

关键设计：

- **前端完全本地化**：`www/` 打包进 App，秒开、可离线看骨架屏，不受站点改版影响首屏；
  数据全部来自站点接口。
- **网络走原生**：绕开 `file://` 的跨域限制，同时保证 rec2 签名用的 UA 与请求头一致。
- **播放器隔离**：播放源在第三方 embed 页（`sadie-shop.site`），用独立全屏 WKWebView 加载，
  拦掉 `window.open`、拦截一切非原站导航 —— 广告跳转无效。
- **原生体感**：下拉刷新、状态栏/安全区适配、深色模式、横屏播放、静音键下继续出声。

---

## 六、目录结构

```
123AV-iOS/
├─ www/                     前端（App 内本地资源）
│  ├─ index.html            外壳 + 底部 tab
│  ├─ app.css               深色主题
│  ├─ app.js                路由 / 视图 / 解析 / 接口
│  └─ md5.js                封面 CDN 需要的 MD5（已与 Node crypto 对拍）
├─ Sources/                 原生（4 个文件，无第三方依赖）
│  ├─ AppDelegate.swift
│  ├─ SceneDelegate.swift
│  ├─ WebAppViewController.swift   WKWebView 容器 + 导航策略 + JS 弹窗
│  ├─ NetBridge.swift              JS ⇄ URLSession 网络桥
│  └─ PlayerViewController.swift   全屏播放器（弹窗拦截）
├─ Resources/
│  ├─ Info.plist            Bundle 信息（iOS 14+，arm64）
│  ├─ Assets.xcassets/      App 图标（1024）+ 启动色
│  └─ brand/logo-square.png 站点 logo 原图（图标源）
├─ scripts/
│  ├─ build-ipa.sh          macOS 构建 + 打包 IPA
│  └─ dev-server.mjs        本地预览 + 跨域代理
├─ docs/
│  ├─ API.md                接口与分类分析（核心交付）
│  ├─ categories.json       499 个分类全量数据
│  └─ screenshots/          实测截图
├─ webclip/                 免签名 Web Clip
└─ .github/workflows/build-ipa.yml
```

工作区里另有 `tools/*.mjs|py`：接口探测脚本、图标/描述文件生成、IPA 校验。

---

## 七、改成你的样子

| 想改什么 | 改哪里 |
| --- | --- |
| 启动页 / 站点地址 | `www/app.js` 顶部 `CFG.SITE`、`CFG.LOCALE`、`CFG.URL_LOCALE` |
| App 名字 | `Resources/Info.plist` 的 `CFBundleDisplayName`、`CFBundleName` |
| Bundle ID | `Resources/Info.plist` 的 `CFBundleIdentifier`（或构建时 `BUNDLE_ID=`） |
| 图标 | 换 `Resources/brand/logo-square.png` 后跑 `python tools/make_icons.py` |
| 最低系统 | `Info.plist` 的 `MinimumOSVersion` + 构建时 `MIN_IOS=15.0` |
| 主题色 | `www/app.css` 里的 `--accent` |
| 分类排序 / 首页段落数 | `app.js` 的 `renderHome`（`Api.segments()` 的 `count`） |

---

## 八、已知限制

1. **没有全站视频列表接口**：站点是 SSR，全量翻页只能抓 HTML（本项目按 12 条/页、最多 60 页）。
2. **推荐接口依赖签名**：`recKey` 或签名算法一旦变，需要照 `docs/API.md` 第 4 节重新适配。
3. **播放源会过期**：`episode.id`（如 `7N1ZQ0`）有时效，所以每次进详情页都重新解析，不做缓存。
4. **免费签名 7 天**：不是 App 的问题，是 Apple 免费账号策略；要长期用选 TrollStore 或自签证书。
5. **不能上架 App Store**：内容与形态都不符合审核规则，仅侧载自用。

---

## 九、免责声明

- 本项目仅用于**个人学习**（客户端开发 / 接口分析 / 逆向分析练习）。
- 内容为 18+ 成人内容，请确认你已成年，并遵守当地法律。
- 不包含、不存储、不分发任何视频文件；所有播放均指向站点自身的播放源。
- 请勿用于商业用途或公开分发；由此产生的任何后果由使用者自行承担。
