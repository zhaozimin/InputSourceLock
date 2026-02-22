import SwiftUI
import AppKit

/// 菜单栏弹出的 SwiftUI 视图
struct MenuBarView: View {

    @ObservedObject var lockService: LockService
    @ObservedObject var loginItemManager: LoginItemManager

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

            // ── 当前输入法信息 ─────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text("当前输入法")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(lockService.isLocked ? lockService.lockedSourceName : lockService.currentSourceName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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
        .frame(width: 240)
        .background(.regularMaterial)
    }
}
