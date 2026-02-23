import Foundation
import CryptoKit
import IOKit

/// 授权管理器（服务器版）
/// 负责：API 调用激活、设备 ID 管理、Token Keychain 持久化、试用期管理
@MainActor
final class LicenseManager: ObservableObject {

    // MARK: - 常量

    /// ⚠️ 部署 Workers 后，将此 URL 替换为你的 Workers 地址
    static let apiBaseURL = "http://api.cklaozhao.me/api"

    private let trialDurationDays = 7
    private let tokenKey      = "com.local.inputlock.authToken"
    private let deviceIDKey   = "com.local.inputlock.deviceID"
    private let tokenExpiryKey = "InputLock_TokenExpiry"
    private let firstLaunchKey = "InputLock_FirstLaunchDate"
    private let installFingerprintKey = "InputLock_InstallFingerprint"

    // MARK: - 已发布状态

    @Published private(set) var isActivated: Bool = false
    @Published private(set) var trialDaysRemaining: Int = 0

    // MARK: - 计算属性

    var isInTrial: Bool { !isActivated && trialDaysRemaining > 0 }
    var canUseLockFeature: Bool { isActivated || isInTrial }

    // MARK: - 初始化

    init() {
        checkInstallationFingerprint()
        refreshStatus()
    }

    // MARK: - 公共方法

    /// 刷新授权状态（从 UserDefaults 读取 token 并校验有效期）
    func refreshStatus() {
        if let token = UserDefaults.standard.string(forKey: tokenKey),
           !token.isEmpty {
            // 检查本地存储的 token 过期时间
            let expiry = UserDefaults.standard.double(forKey: tokenExpiryKey)
            let now = Date().timeIntervalSince1970
            if expiry > now {
                isActivated = true
                trialDaysRemaining = 0
                return
            }
        }
        isActivated = false
        trialDaysRemaining = computeTrialDaysRemaining()
    }

    /// 激活：向服务器发送邮箱+序列号，成功后本地保存 token
    func activate(email: String, serial: String) async throws {
        let deviceID = getOrCreateDeviceID()
        let body: [String: String] = [
            "email": email,
            "serial": serial.uppercased(),
            "device_id": deviceID
        ]

        let data = try await postRequest(path: "/activate", body: body)

        struct ActivateResponse: Decodable {
            let token: String?
            let expires_at: Double?
            let error: String?
        }

        let response = try JSONDecoder().decode(ActivateResponse.self, from: data)

        if let errorMsg = response.error {
            throw LicenseError.serverError(errorMsg)
        }
        guard let token = response.token, let expiresAt = response.expires_at else {
            throw LicenseError.serverError("服务器返回数据异常")
        }

        // 保存 token 和过期时间到 UserDefaults
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(expiresAt, forKey: tokenExpiryKey)

        isActivated = true
        trialDaysRemaining = 0
    }

    /// 找回序列号（只需邮箱，服务器发邮件）
    func recoverKey(email: String) async throws {
        let body = ["email": email]
        let data = try await postRequest(path: "/recover", body: body)

        struct RecoverResponse: Decodable {
            let status: String?
            let error: String?
        }

        let response = try JSONDecoder().decode(RecoverResponse.self, from: data)
        if let errorMsg = response.error {
            throw LicenseError.serverError(errorMsg)
        }
    }

    /// 后台静默验证 token 是否仍有效（每 30 天调用一次）
    func verifyTokenIfNeeded() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty else { return }

        // 如果本地过期时间还剩超过 7 天，无需联网验证
        let expiry = UserDefaults.standard.double(forKey: tokenExpiryKey)
        let sevenDays: Double = 7 * 24 * 60 * 60
        if expiry - Date().timeIntervalSince1970 > sevenDays { return }

        // 临近过期，联网续签
        do {
            let deviceID = getOrCreateDeviceID()
            let body = ["token": token, "device_id": deviceID]
            let data = try await postRequest(path: "/verify", body: body)

            struct VerifyResponse: Decodable {
                let valid: Bool
                let expires_at: Double?
            }

            let response = try JSONDecoder().decode(VerifyResponse.self, from: data)
            if response.valid, let newExpiry = response.expires_at {
                UserDefaults.standard.set(newExpiry, forKey: tokenExpiryKey)
                isActivated = true
            } else {
                // Token 已被服务器吊销
                UserDefaults.standard.removeObject(forKey: tokenKey)
                UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
                isActivated = false
                trialDaysRemaining = computeTrialDaysRemaining()
            }
        } catch {
            // 网络错误时不修改本地状态（容忍离线）
        }
    }

    // MARK: - 私有方法

    /// 检查安装指纹：如果 App 被重新安装（文件创建时间变动），则清除旧的激活状态
    private func checkInstallationFingerprint() {
        guard let url = Bundle.main.executableURL else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let creationDate = attributes[.creationDate] as? Date {
                let currentFingerprint = "\(creationDate.timeIntervalSince1970)"
                let savedFingerprint = UserDefaults.standard.string(forKey: installFingerprintKey)
                
                if savedFingerprint != currentFingerprint {
                    // 指纹不匹配，说明是全新安装或被覆盖安装
                    // 清除旧的激活状态
                    UserDefaults.standard.removeObject(forKey: tokenKey)
                    UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
                    UserDefaults.standard.removeObject(forKey: firstLaunchKey)
                    // 保存新的指纹
                    UserDefaults.standard.set(currentFingerprint, forKey: installFingerprintKey)
                    print("[LicenseManager] 检测到 App 重新安装，已清除旧的激活状态。")
                }
            }
        } catch {
            print("[LicenseManager] 无法获取安装指纹: \(error)")
        }
    }

    /// 获取设备唯一 ID（硬件序列号哈希存入 UserDefaults，脱敏且抗重装）
    private func getOrCreateDeviceID() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existing
        }
        
        var serialNumber = UUID().uuidString
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if platformExpert != 0 {
            if let serial = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? String {
                serialNumber = serial
            }
            IOObjectRelease(platformExpert)
        }
        
        // 使用 SHA256 脱敏硬件序列号，避免明文收集
        let hashedHardwareID = SHA256.hash(data: Data(serialNumber.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        
        UserDefaults.standard.set(hashedHardwareID, forKey: deviceIDKey)
        return hashedHardwareID
    }

    /// 计算剩余试用天数
    private func computeTrialDaysRemaining() -> Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(Date(), forKey: firstLaunchKey)
        }
        guard let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date else {
            return trialDurationDays
        }
        let daysPassed = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        return max(0, trialDurationDays - daysPassed)
    }

    /// 通用 POST 请求
    private func postRequest(path: String, body: [String: String]) async throws -> Data {
        guard let url = URL(string: LicenseManager.apiBaseURL + path) else {
            throw LicenseError.serverError("API 地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError
        }
        // 4xx 错误也解析返回，交给调用方处理 error 字段
        if http.statusCode >= 500 {
            throw LicenseError.serverError("服务器内部错误，请稍后重试")
        }
        return data
    }
}

// MARK: - 授权错误类型

enum LicenseError: LocalizedError {
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "网络连接失败，请检查网络后重试"
        case .serverError(let msg):
            return msg
        }
    }
}
