import SwiftUI
import AppKit

/// 菜单栏弹出的 SwiftUI 视图
struct MenuBarView: View {

    @ObservedObject var lockService: LockService
    @ObservedObject var loginItemManager: LoginItemManager
    @ObservedObject var licenseManager: LicenseManager
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 标题头部 ──────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: lockService.isLocked ? "lock.fill" : "lock.open.fill")
                    .foregroundStyle(lockService.isLocked ? .red : .secondary)
                    .font(.system(size: 14, weight: .semibold))
                Text("输入法锁定")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── 选择锁定输入法 ─────────────────────────
            HStack {
                Text("锁定目标")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Picker("", selection: $lockService.selectedSourceID) {
                    ForEach(lockService.availableSources, id: \.id) { source in
                        Text(source.name)
                            .font(.system(size: 12))
                            .tag(source.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 130)
                .disabled(lockService.isLocked) // 锁定时不允许修改目标
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // ── 锁定开关 ──────────────────────────────
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(lockService.isLocked ? .red : .secondary)
                        .font(.system(size: 13))
                    Text(lockService.isLocked ? "已锁定" : "点击锁定")
                        .font(.system(size: 13))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { lockService.isLocked },
                    set: { newValue in
                        if newValue { lockService.lock() } else { lockService.unlock() }
                    }
                ))
                .toggleStyle(.switch)
                .tint(.green)
                .labelsHidden()
                .disabled(!licenseManager.canUseLockFeature)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .opacity(licenseManager.canUseLockFeature ? 1.0 : 0.4)

            // 锁定时显示被锁定的输入法
            if lockService.isLocked {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("已锁定至：\(lockService.lockedSourceName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            // ── 授权状态区域 ───────────────────────────
            licenseStatusRow

            Divider()

            // ── 开机自启开关 ───────────────────────────
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(loginItemManager.isEnabled ? .green : .secondary)
                        .font(.system(size: 13))
                    Text("开机自启")
                        .font(.system(size: 13))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { _ in loginItemManager.toggle() }
                ))
                .toggleStyle(.switch)
                .tint(.green)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── 退出按钮 ──────────────────────────────
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("退出")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .frame(width: 250, alignment: .top)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(8) // 给阴影留出空间，如果不留空间，悬浮窗的边缘截断会很生硬
    }

    // MARK: - 授权状态行

    @ViewBuilder
    private var licenseStatusRow: some View {
        if licenseManager.isActivated {
            // ✅ 已永久激活
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13))
                Text("已激活")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

        } else if licenseManager.isInTrial {
            // ⏳ 试用期中
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    Text("试用剩余 \(licenseManager.trialDaysRemaining) 天")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }
                Spacer()
               // 未激活，点击打开独立激活窗口
                Button {
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.closePopover(sender: nil)
                    }
                    ActivationWindowManager.shared.showWindow(licenseManager: licenseManager)
                } label: {
                    Text("激活")
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

        } else {
            // ❌ 试用到期，功能锁定
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 13))
                    Text("试用已到期")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("立即激活") {
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.closePopover(sender: nil)
                    }
                    ActivationWindowManager.shared.showWindow(licenseManager: licenseManager)
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 自定义 iOS 风格纯绿开关
struct GreenSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(configuration.isOn ? Color(red: 52/255, green: 199/255, blue: 89/255) : Color.gray.opacity(0.3)) // iOS 原生翠绿
                .frame(width: 32, height: 20)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 6 : -6)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
                )
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}
