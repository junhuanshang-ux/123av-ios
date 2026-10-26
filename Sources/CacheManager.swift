import Foundation
import WebKit

/// 缓存统计与清理。
///
/// 占用来源：
///   1. URLCache（HTTP 响应 + 封面图）—— 磁盘，已封顶 64MB
///   2. LocalHLSProxy 分片缓存 —— 内存 48MB，退出即释放
///   3. 图片 NSCache —— 内存，系统可回收
///   4. WKWebView 数据（仅兜底网页播放器使用）
enum CacheManager {

    /// 安装一个有上限的 URLCache，避免越用越大
    static func installBoundedURLCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "123av-http"
        )
    }

    static var httpDiskBytes: Int {
        URLCache.shared.currentDiskUsage
    }

    static var memoryBytes: Int {
        LocalHLSProxy.shared.cachedBytes
    }

    static func summary() -> String {
        let disk = Double(httpDiskBytes) / 1024 / 1024
        let memory = Double(memoryBytes) / 1024 / 1024
        return String(format: "磁盘 %.1f MB · 内存 %.1f MB", disk, memory)
    }

    /// 清除全部缓存（磁盘 + 内存 + 网页数据），保留"最近观看"等使用记录
    static func clearAll(completion: @escaping () -> Void) {
        URLCache.shared.removeAllCachedResponses()
        RemoteImageView.clearCache()
        LocalHLSProxy.shared.clearCache()

        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) {
            DispatchQueue.main.async { completion() }
        }
    }
}
