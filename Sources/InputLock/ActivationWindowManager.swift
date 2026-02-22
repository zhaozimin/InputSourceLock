import SwiftUI
import AppKit

/// 独立激活窗口管理器
/// 用于取代 Popover，使激活框表现为一个标准的前台窗口，支持正常的文本粘贴等快捷键操作。
@MainActor
final class ActivationWindowManager {
    
    static let shared = ActivationWindowManager()
    
    private var window: NSWindow?
    
    private init() {}
    
    /// 显示激活窗口
    /// - Parameter licenseManager: 传入已经在 AppDelegate 里初始化的 Authorization Manager
    func showWindow(licenseManager: LicenseManager) {
        if let existingWindow = window {
            // 如果窗口已存在，直接激活并拉到前台
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: ActivationView(licenseManager: licenseManager))
        
        // 创建无边框、有固定尺寸的系统弹出窗
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "输入法锁定 - 激活"
        newWindow.titlebarAppearsTransparent = true
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        
        newWindow.contentViewController = hostingController
        
        self.window = newWindow
        
        // 监听窗口关闭以清除资源
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
        }
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// 关闭窗口（如果需要手动关闭）
    func closeWindow() {
        window?.close()
    }
}
