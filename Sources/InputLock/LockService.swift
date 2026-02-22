import Carbon
import AppKit
import Combine

/// 输入法锁定核心服务
/// 监听系统输入法切换通知，在锁定模式下自动恢复到锁定的输入法
final class LockService: ObservableObject {

    /// 是否处于锁定状态
    @MainActor
    @Published var isLocked: Bool = false

    /// 当前菜单栏显示的输入法名称（实时更新）
    @MainActor
    @Published var currentSourceName: String = InputSourceManager.currentInputSourceName()

    /// 锁定时记录的输入法名称（用于 UI 展示）
    @MainActor
    @Published var lockedSourceName: String = ""

    /// 锁定时保存的 TISInputSource 引用（仅 MainActor 访问）
    @MainActor
    private var lockedSource: TISInputSource?

    /// 通知观察者 token
    private var observer: NSObjectProtocol?

    // nonisolated init，可在任意上下文中调用
    init() {
        startObservingInputSourceChanges()
    }

    // MARK: - 锁定控制（必须从 MainActor 调用）

    /// 激活锁定
    @MainActor
    func lock() {
        lockedSource = InputSourceManager.currentInputSourceRef()
        lockedSourceName = InputSourceManager.currentInputSourceName()
        currentSourceName = lockedSourceName
        isLocked = true
    }

    /// 取消锁定
    @MainActor
    func unlock() {
        isLocked = false
        lockedSource = nil
        lockedSourceName = ""
        currentSourceName = InputSourceManager.currentInputSourceName()
    }

    // MARK: - 私有方法

    /// 注册分布式通知监听器
    private func startObservingInputSourceChanges() {
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleInputSourceChanged()
            }
        }
    }

    /// 输入法切换回调（在 MainActor 上执行）
    @MainActor
    private func handleInputSourceChanged() async {
        currentSourceName = InputSourceManager.currentInputSourceName()

        guard isLocked, let locked = lockedSource else { return }

        let currentName = InputSourceManager.currentInputSourceName()
        if currentName != lockedSourceName {
            // 延迟 50ms 执行，避免与系统切换动作冲突
            try? await Task.sleep(for: .milliseconds(50))
            InputSourceManager.selectInputSource(locked)
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
