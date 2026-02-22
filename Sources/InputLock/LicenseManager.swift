import Foundation
import CryptoKit

/// 授权管理器：负责序列号验证、试用期管理、授权状态持久化
/// 所有公共属性在 @MainActor 上下文中访问，确保 UI 线程安全
@MainActor
final class LicenseManager: ObservableObject {

    // MARK: - 常量

    /// 试用天数
    private let trialDurationDays = 7

    /// Keychain 中保存激活序列号的 key
    private let keychainKey = "com.local.inputlock.licenseKey"

    /// UserDefaults 中保存首次启动日期的 key
    private let firstLaunchKey = "InputLock_FirstLaunchDate"

    // MARK: - 已发布状态

    /// 是否已通过序列号永久激活
    @Published private(set) var isActivated: Bool = false

    /// 剩余试用天数（已激活时为 0）
    @Published private(set) var trialDaysRemaining: Int = 0

    // MARK: - 计算属性

    /// 是否处于试用期（未过期且未激活）
    var isInTrial: Bool {
        !isActivated && trialDaysRemaining > 0
    }

    /// 是否可以使用锁定功能（已激活 或 仍在试用期内）
    var canUseLockFeature: Bool {
        isActivated || isInTrial
    }

    // MARK: - 初始化

    init() {
        refreshStatus()
    }

    // MARK: - 公共方法

    /// 刷新授权状态（从 Keychain 和 UserDefaults 读取）
    func refreshStatus() {
        // 1. 检查 Keychain 是否存有有效的激活序列号
        if let savedKey = KeychainHelper.load(forKey: keychainKey),
           validate(serialKey: savedKey) {
            isActivated = true
            trialDaysRemaining = 0
            return
        }

        // 2. 未激活，计算试用剩余天数
        isActivated = false
        trialDaysRemaining = computeTrialDaysRemaining()
    }

    /// 验证序列号格式是否合法（本地 HMAC 验证，无需联网）
    /// - Parameter serialKey: 用户输入的序列号，格式 XXXX-XXXX-XXXX-XXXX
    /// - Returns: 序列号是否有效
    func validate(serialKey: String) -> Bool {
        // 1. 规范化输入：去空格、转大写、去掉 "-"
        let cleaned = serialKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")

        let parts = cleaned.components(separatedBy: "-")
        guard parts.count == 4,
              parts.allSatisfy({ $0.count == 4 }) else {
            return false
        }

        // 2. 还原用户码 = 第1段 + 第2段
        let userCode = parts[0] + parts[1]

        // 3. 计算期望签名
        guard let expectedSig = hmacSignature(for: userCode) else {
            return false
        }

        // 4. 比对签名（第3段 + 第4段 与期望签名前8位）
        let providedSig = parts[2] + parts[3]
        return providedSig == expectedSig
    }

    /// 激活应用并将序列号保存至 Keychain
    /// - Parameter serialKey: 经过验证的合法序列号
    /// - Throws: 若序列号无效，抛出 LicenseError.invalidKey
    func activate(serialKey: String) throws {
        guard validate(serialKey: serialKey) else {
            throw LicenseError.invalidKey
        }

        let normalized = serialKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard KeychainHelper.save(normalized, forKey: keychainKey) else {
            throw LicenseError.keychainWriteFailed
        }

        refreshStatus()
    }

    // MARK: - 私有方法

    /// 计算剩余试用天数，首次运行时记录启动日期到 UserDefaults
    private func computeTrialDaysRemaining() -> Int {
        let defaults = UserDefaults.standard

        // 如果未记录首次启动时间，则记录当前时间
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(Date(), forKey: firstLaunchKey)
        }

        guard let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date else {
            return trialDurationDays
        }

        let daysPassed = Calendar.current.dateComponents(
            [.day],
            from: firstLaunch,
            to: Date()
        ).day ?? 0

        return max(0, trialDurationDays - daysPassed)
    }

    /// 使用 HMAC-SHA256 计算用户码的签名（取前 8 位十六进制大写）
    /// - Parameter userCode: 16 位十六进制用户码
    /// - Returns: 8 位大写十六进制签名，失败返回 nil
    private func hmacSignature(for userCode: String) -> String? {
        // HMAC 密钥：通过字节数组混淆，避免明文字符串出现在二进制中
        // ⚠️ 此密钥对应字符串，请勿修改，否则已发出的序列号将全部失效
        let keyBytes: [UInt8] = [
            73, 110, 112, 117, 116, 76, 111, 99, 107, 45,
            55, 102, 51, 97, 45, 57, 98, 50, 99, 45,
            52, 100, 56, 102, 45, 97, 51, 99, 55, 45,
            50, 48, 50, 52, 75, 101, 121
        ]

        let keyData = Data(bytes: keyBytes, count: keyBytes.count)
        guard let messageData = userCode.data(using: .utf8) else {
            return nil
        }

        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(
            for: messageData,
            using: symmetricKey
        )

        // 取摘要的前 4 字节 = 8 位十六进制
        let hexString = mac.withUnsafeBytes { bytes -> String in
            bytes.prefix(4)
                .map { String(format: "%02X", $0) }
                .joined()
        }

        return hexString
    }
}

// MARK: - 授权错误类型

enum LicenseError: LocalizedError {
    case invalidKey
    case keychainWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "序列号无效，请检查输入后重试"
        case .keychainWriteFailed:
            return "激活信息写入失败，请重试"
        }
    }
}
