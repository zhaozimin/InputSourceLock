import AppKit
import SwiftUI
import Combine

/// 应用委托：负责创建和管理菜单栏状态项
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let lockService = LockService()
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
    }

    // MARK: - 菜单栏图标设置

    @MainActor
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }
        updateStatusItemIcon()
        button.action = #selector(togglePopover)
        button.target = self

        // 监听锁定状态变化，更新菜单栏图标
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

    // MARK: - 弹出视图设置

    @MainActor
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(lockService: lockService)
        )
        self.popover = popover
    }

    @MainActor
    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
