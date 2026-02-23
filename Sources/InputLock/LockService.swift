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

    /// 系统中所有的键盘输入法
    @MainActor
    @Published var availableSources: [InputSourceItem] = []

    /// 用户在界面上选择要锁定的输入法ID
    @MainActor
    @Published var selectedSourceID: String = ""

    /// 当前菜单栏显示的输入法名称（实时更新）
    @MainActor
    @Published var currentSourceName: String = InputSourceManager.currentInputSourceName()

    /// 锁定时记录的输入法名称（用于 UI 展示）
    @MainActor
    @Published var lockedSourceName: String = ""

    /// 锁定时保存的输入法 ID
    @MainActor
    private var lockedSourceID: String?

    /// 记录最后一次活跃 App 发生切换的时间，用于判定系统自动切换还是用户手动切换
    @MainActor
    private var lastAppChangeTime: Date = .distantPast

    /// 记录最后一次用户手动触碰切换键的时间
    @MainActor
    private var lastManualSwitchTime: Date = .distantPast

    /// 标记当前是否因为进入了终端类 App 而被迫切换为英文
    @MainActor
    private var isForcedEnglishInTerminal: Bool = false

    /// 标记当前是否因为进入了密码输入框而被迫切换为英文
    @MainActor
    private var isForcedEnglishInPasswordField: Bool = false

    /// 密码框焦点监听器
    @MainActor
    private var focusWatcher: FocusWatcher?

    /// 通知观察者 token
    private var observer: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?

    // nonisolated init，可在任意上下文中调用
    init() {
        startObservingInputSourceChanges()
        Task { @MainActor in
            self.refreshAvailableSources()
        }
    }

    @MainActor
    func refreshAvailableSources() {
        availableSources = InputSourceManager.getAllEnabledInputSources()
        if let currentRef = InputSourceManager.currentInputSourceRef(),
           let currentID = InputSourceManager.sourceID(of: currentRef) {
            selectedSourceID = currentID
        }
    }

    // MARK: - 锁定控制（必须从 MainActor 调用）

    /// 激活锁定
    @MainActor
    func lock() {
        let currentRef = InputSourceManager.currentInputSourceRef()
        let currentID = currentRef.flatMap { InputSourceManager.sourceID(of: $0) }
        
        // 如果 selectedSourceID 不空，优先选择该 ID；否则用当前系统的
        let targetID = selectedSourceID.isEmpty ? (currentID ?? "") : selectedSourceID
        
        lockedSourceID = targetID
        lockedSourceName = availableSources.first(where: { $0.id == targetID })?.name ?? InputSourceManager.currentInputSourceName()
        currentSourceName = lockedSourceName
        isLocked = true
        
        // 确保真正切过去
        if !targetID.isEmpty {
            InputSourceManager.selectInputSource(byID: targetID)
        }
        
        // 启动 FocusWatcher
        let watcher = FocusWatcher()
        watcher.onPasswordFieldFocusChanged = { [weak self] isInPassword in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isForcedEnglishInPasswordField = isInPassword
                if isInPassword {
                    // 进入密码框，强制切换为英文
                    if let englishSource = InputSourceManager.getEnglishInputSource() {
                        InputSourceManager.selectInputSource(englishSource)
                    }
                } else {
                    // 离开密码框，恢复锁定的输入法
                    if let lockedID = self.lockedSourceID {
                        InputSourceManager.selectInputSource(byID: lockedID)
                    }
                }
            }
        }
        watcher.start()
        focusWatcher = watcher
    }

    /// 取消锁定
    @MainActor
    func unlock() {
        isLocked = false
        lockedSourceID = nil
        lockedSourceName = ""
        currentSourceName = InputSourceManager.currentInputSourceName()
        isForcedEnglishInPasswordField = false
        isForcedEnglishInTerminal = false
        focusWatcher?.stop()
        focusWatcher = nil
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
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            
            Task { @MainActor in
                guard let self = self else { return }
                self.lastAppChangeTime = Date()
                
                // 终端类 App 强制英文逻辑
                if self.isLocked, let bundleID = bundleID {
                    
                    let terminalApps = ["com.apple.Terminal", "com.googlecode.iterm2"]
                    if terminalApps.contains(bundleID) {
                        if let englishSource = InputSourceManager.getEnglishInputSource() {
                            InputSourceManager.selectInputSource(englishSource)
                            self.isForcedEnglishInTerminal = true
                        }
                    } else if self.isForcedEnglishInTerminal {
                        // 离开终端类 App 时，恢复原来锁定的输入法
                        if let lockedID = self.lockedSourceID {
                            InputSourceManager.selectInputSource(byID: lockedID)
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

        guard isLocked, let lockedID = lockedSourceID else { return }

        // 如果目前正处于因为终端或密码框而强制英文的状态，忽略任何输入法切换（不修改锁定目标）
        if isForcedEnglishInTerminal || isForcedEnglishInPasswordField { return }

        let currentName = InputSourceManager.currentInputSourceName()
        if currentName != lockedSourceName {
            let now = Date()
            
            // 智能判定：如果是系统随着 App 切换导致的自动变动，强行拉回
            if now.timeIntervalSince(lastAppChangeTime) < 0.5 {
                try? await Task.sleep(for: .milliseconds(50))
                InputSourceManager.selectInputSource(byID: lockedID)
            } else {
                // 用户手动通过 Option+Tab 或其他方式明确切换的 -> 接纳为最新的锁定目标
                if let newSource = InputSourceManager.currentInputSourceRef(),
                   let newID = InputSourceManager.sourceID(of: newSource) {
                    lockedSourceID = newID
                    selectedSourceID = newID
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
