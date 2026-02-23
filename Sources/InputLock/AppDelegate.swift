import AppKit
import SwiftUI
import Combine

/// 应用委托：负责创建和管理菜单栏状态项
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private let lockService = LockService()
    private var loginItemManager: LoginItemManager?
    private var licenseManager: LicenseManager?
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 在 @MainActor 上下文中初始化各管理器
        let loginManager = LoginItemManager()
        loginItemManager = loginManager
        loginManager.refreshStatus()

        let licManager = LicenseManager()
        licenseManager = licManager

        setupStatusItem()
        setupPopover()

        // 后台静默验证 token（网络可用时自动续签）
        Task {
            await licManager.verifyTokenIfNeeded()
        }

        // 注入默认的 Edit 菜单以支持快捷键（如 Cmd+C/V）
        setupMainMenu()
    }

    // MARK: - 主菜单设置（为独立窗口支持快捷键）
    
    @MainActor
    private func setupMainMenu() {
        let mainMenu = NSMenu(title: "MainMenu")
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 菜单栏图标设置

    @MainActor
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }
        updateStatusItemIcon()
        button.action = #selector(togglePopover)
        button.target = self

        // 监听锁定状态，动态更新图标
        lockService.$isLocked
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemIcon()
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let iconName = lockService.isLocked ? "lock.fill" : "lock.open"
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "输入法锁定")
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - 弹出视图

    @MainActor
    private func setupPopover() {
        guard let loginItemManager, let licenseManager else { return }
        
        let hostingController = NSHostingController(
            rootView: MenuBarView(
                lockService: lockService,
                loginItemManager: loginItemManager,
                licenseManager: licenseManager
            )
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300), // Height will adjust to content
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        
        // 当点击其他地方时自动隐藏
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        self.window = window
        
        // 监听焦点丢失
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover(sender: nil)
            }
        }
    }

    @MainActor
    @objc private func togglePopover() {
        guard let window = self.window, let button = statusItem?.button else { return }
        
        if window.isVisible {
            closePopover(sender: nil)
        } else {
            // 精确计算位置
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
            let windowSize = window.frame.size
            
            // X: 居中对齐图标
            let x = buttonFrame.midX - windowSize.width / 2
            // Y: 图标底部，加上一个很小的间距，比如 2px
            let y = buttonFrame.minY - windowSize.height - 2
            
            window.setFrameOrigin(NSPoint(x: x, y: y))
            
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    func closePopover(sender: Any?) {
        window?.orderOut(sender)
    }
}
