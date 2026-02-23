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

    /// 记录最后一次用户手动触碰切换键的时间
    @MainActor
    private var lastManualSwitchTime: Date = .distantPast

    /// 标记当前是否因为进入了终端类 App 而被迫切换为英文
    @MainActor
    private var isForcedEnglishInTerminal: Bool = false

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
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self = self else { return }
                self.lastAppChangeTime = Date()
                
                // 终端类 App 强制英文逻辑
                if self.isLocked,
                   let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let bundleID = app.bundleIdentifier {
                    
                    let terminalApps = ["com.apple.Terminal", "com.googlecode.iterm2"]
                    if terminalApps.contains(bundleID) {
                        if let englishSource = InputSourceManager.getEnglishInputSource() {
                            InputSourceManager.selectInputSource(englishSource)
                            self.isForcedEnglishInTerminal = true
                        }
                    } else if self.isForcedEnglishInTerminal {
                        // 离开终端类 App 时，恢复原来锁定的输入法
                        if let locked = self.lockedSource {
                            InputSourceManager.selectInputSource(locked)
                        }
                        self.isForcedEnglishInTerminal = false
                    }
                }
            }
        }
    }

    /// 输入法切换回调（在 MainActor 上执行）
    @MainActor
    private func handleInputSourceChanged() async {
        currentSourceName = InputSourceManager.currentInputSourceName()

        guard isLocked, let locked = lockedSource else { return }

        // 如果目前正处于因为终端而强制英文的状态，忽略任何输入法切换（不修改锁定目标）
        if isForcedEnglishInTerminal { return }

        let currentName = InputSourceManager.currentInputSourceName()
        if currentName != lockedSourceName {
            let now = Date()
            
            // 智能判定：如果是系统随着 App 切换导致的自动变动，强行拉回
            if now.timeIntervalSince(lastAppChangeTime) < 0.5 {
                try? await Task.sleep(for: .milliseconds(50))
                InputSourceManager.selectInputSource(locked)
            } else {
                // 用户手动切换的防误触逻辑（双击才生效）
                if now.timeIntervalSince(lastManualSwitchTime) < 0.4 {
                    // 确认是双击（0.4 秒内连按），允许更换锁定目标！
                    if let newSource = InputSourceManager.currentInputSourceRef() {
                        lockedSource = newSource
                        lockedSourceName = currentName
                        lastManualSwitchTime = .distantPast // 重置，防止连续触发
                    }
                } else {
                    // 只是误触一次，强行拉回并记录这次点击的时间
                    lastManualSwitchTime = now
                    try? await Task.sleep(for: .milliseconds(50))
                    InputSourceManager.selectInputSource(locked)
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
