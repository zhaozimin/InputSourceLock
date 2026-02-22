import ServiceManagement
import Combine

/// 开机自启管理器，封装 macOS 13+ 的 SMAppService API
@MainActor
final class LoginItemManager: ObservableObject {

    /// 当前是否已开启开机自启
    @Published private(set) var isEnabled: Bool = false

    init() {
        refreshStatus()
    }

    /// 刷新开机自启状态（从 SMAppService 读取）
    func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// 切换开机自启状态
    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    /// 开启开机自启
    func enable() {
        do {
            try SMAppService.mainApp.register()
            refreshStatus()
        } catch {
            // 用户拒绝授权或其他错误，静默处理
            print("[LoginItemManager] 开启开机自启失败: \(error.localizedDescription)")
        }
    }

    /// 关闭开机自启
    func disable() {
        do {
            try SMAppService.mainApp.unregister()
            refreshStatus()
        } catch {
            print("[LoginItemManager] 关闭开机自启失败: \(error.localizedDescription)")
        }
    }
}
