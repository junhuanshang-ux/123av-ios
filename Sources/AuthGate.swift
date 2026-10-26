import Foundation
import LocalAuthentication

/// 面容 / 指纹验证闸门。
/// - 进入 App 必须验证；
/// - 进入播放器也验证（有 grace 秒宽限，避免连看多集时反复扫脸）。
enum AuthGate {

    /// 进入 App / 回到前台 的宽限时间
    static let grace: TimeInterval = 60

    /// 打开播放器时的宽限：只容忍"刚验证完又点了一下"的重复触发
    static let playerGrace: TimeInterval = 5

    private(set) static var lastSuccessAt: Date = .distantPast

    static var isFresh: Bool {
        Date().timeIntervalSince(lastSuccessAt) < grace
    }

    static func fresh(within seconds: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastSuccessAt) < seconds
    }

    static func markSuccess() {
        lastSuccessAt = Date()
    }

    static func reset() {
        lastSuccessAt = .distantPast
    }

    /// 设备是否具备生物识别能力（Face ID / Touch ID）
    static var biometricsAvailable: Bool {
        let ctx = LAContext()
        var error: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 发起验证。优先面容/指纹，设备不支持时退回锁屏密码。
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "取消"
        ctx.localizedFallbackTitle = "使用密码"

        var error: NSError?
        let policy: LAPolicy
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            policy = .deviceOwnerAuthentication
        } else {
            // 设备完全没有设密码：按"无保护"处理，直接放行
            markSuccess()
            DispatchQueue.main.async { completion(true) }
            return
        }

        ctx.evaluatePolicy(policy, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async {
                if ok { markSuccess() }
                completion(ok)
            }
        }
    }
}
