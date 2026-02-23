import Foundation
import AppKit
import ApplicationServices

/// 监听前台应用内的焦点元素变化
/// 当焦点进入密码输入框时，通知外部回调；焦点离开时同理
@MainActor
final class FocusWatcher {

    // MARK: - 回调

    /// 密码框焦点状态变化回调：true = 进入密码框，false = 离开密码框
    var onPasswordFieldFocusChanged: ((Bool) -> Void)?

    // MARK: - 私有状态

    private var axObserver: AXObserver?
    private var observedApp: AXUIElement?
    private var currentAppPID: pid_t = 0
    private var isInPasswordField: Bool = false

    // 监听前台 App 变化（以重新绑定 AX 观察者）
    private var workspaceObserver: NSObjectProtocol?

    // MARK: - 生命周期

    func start() {
        bindToFrontmostApp()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 当切换到新 App 时，重新绑定观察者
                if let pid { self.bindObserver(for: pid) }
            }
        }
    }

    func stop() {
        unbindCurrentObserver()
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
        // 恢复状态
        if isInPasswordField {
            isInPasswordField = false
            onPasswordFieldFocusChanged?(false)
        }
    }

    // MARK: - 绑定当前前台 App

    private func bindToFrontmostApp() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        bindObserver(for: pid)
    }

    private func bindObserver(for pid: pid_t) {
        guard pid != currentAppPID else { return }
        unbindCurrentObserver()
        currentAppPID = pid

        let appElement = AXUIElementCreateApplication(pid)
        observedApp = appElement

        var observer: AXObserver?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let result = AXObserverCreate(pid, { (_, element, _, refcon) in
            guard let refcon else { return }
            let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
            // 在主线程更新状态
            DispatchQueue.main.async {
                watcher.handleFocusChanged(element: element)
            }
        }, &observer)

        guard result == .success, let observer else { return }
        axObserver = observer

        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        // 初始检查：当前焦点可能已经是密码框
        checkCurrentFocus(in: appElement)
    }

    private func unbindCurrentObserver() {
        guard let observer = axObserver, let app = observedApp else { return }
        AXObserverRemoveNotification(observer, app, kAXFocusedUIElementChangedNotification as CFString)
        if let src = AXObserverGetRunLoopSource(observer) as CFRunLoopSource? {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        axObserver = nil
        observedApp = nil
        currentAppPID = 0
        
        // 关键修复：当彻底解绑一个 App 的观察者时，说明用户切走了。
        // 如果切走前焦点在密码框里，必须强行触发“离开密码框”的消息，给 LockService 解锁。
        if isInPasswordField {
            isInPasswordField = false
            onPasswordFieldFocusChanged?(false)
        }
    }

    // MARK: - 焦点判断

    private func handleFocusChanged(element: AXUIElement) {
        let nowInPassword = isPasswordField(element)
        guard nowInPassword != isInPasswordField else { return }
        isInPasswordField = nowInPassword
        onPasswordFieldFocusChanged?(nowInPassword)
    }

    private func checkCurrentFocus(in appElement: AXUIElement) {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedElement = focused as! AXUIElement? else { return }
        handleFocusChanged(element: focusedElement)
    }

    /// 判断某个 AXUIElement 是否是密码输入框
    private func isPasswordField(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return false }

        // role 是 AXTextField，且 subrole 是 AXSecureTextField
        if role == kAXTextFieldRole as String {
            var subroleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
               let subrole = subroleValue as? String,
               subrole == kAXSecureTextFieldSubrole as String {
                return true
            }
        }

        return false
    }
}
