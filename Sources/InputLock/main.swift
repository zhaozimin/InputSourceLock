import AppKit

// 应用入口：不使用 @main 标注（Swift Package 可执行文件需手动管理 RunLoop）
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 设置激活策略为 accessory，配合 LSUIElement 确保不出现在 Dock
app.setActivationPolicy(.accessory)

app.run()
