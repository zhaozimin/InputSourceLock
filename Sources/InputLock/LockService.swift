import Carbon
import AppKit
import Combine

/// 输入法锁定核心服务
/// 监听系统输入法切换通知，在锁定模式下自动恢复到锁定的输入法
/// @unchecked Sendable：全部可变状态均由 @MainActor 保护，跨线程安全
final class LockService: ObservableObject, @unchecked Sendable {

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

    /// 记录最后一次活跃 App 发生切换的时间，用于判定系统自动切换还是用户手动切换
    @MainActor
    private var lastAppChangeTime: Date = .distantPast

    /// 通知观察者 token
    private var observer: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?

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
        
        // 监听前台应用切换事件
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastAppChangeTime = Date()
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
            // 智能判定：如果刚切换完 App（< 0.5s），这很可能是 macOS 的"自动切换到文档输入源"机制强行切的
            // 此时我们要拉回锁定的输入法。
            // 否则（切换 App 已经过了很久），说明你是通过 Cmd+Space 手动切换的，那我们顺从你的意愿，把新的输入法作为锁定的目标！
            if Date().timeIntervalSince(lastAppChangeTime) < 0.5 {
                // 系统自动切换的 -> 我们不答应，强行拉回
                try? await Task.sleep(for: .milliseconds(50))
                InputSourceManager.selectInputSource(locked)
            } else {
                // 用户手动切换的 -> 更新最新的锁定目标
                if let newSource = InputSourceManager.currentInputSourceRef() {
                    lockedSource = newSource
                    lockedSourceName = currentName
                }
            }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }
}
