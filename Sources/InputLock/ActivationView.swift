import SwiftUI
import AppKit

/// 序列号激活弹窗视图
struct ActivationView: View {

    @ObservedObject var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss

    @State private var serialInput: String = ""
    @State private var errorMessage: String = ""
    @State private var isActivating: Bool = false
    @State private var showSuccess: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // ── 头部 ──────────────────────────────────
            VStack(spacing: 8) {
                Image(systemName: showSuccess ? "checkmark.seal.fill" : "key.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(showSuccess ? .green : .blue)
                    .scaleEffect(showSuccess ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: showSuccess)

                Text(showSuccess ? "激活成功！" : "激活输入法锁定")
                    .font(.system(size: 16, weight: .semibold))

                if !showSuccess {
                    Text(licenseManager.isInTrial
                         ? "试用期剩余 \(licenseManager.trialDaysRemaining) 天，购买后永久使用"
                         : "试用期已结束，请输入序列号以继续使用")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 20)

            if showSuccess {
                // ── 激活成功状态 ──────────────────────────
                Text("感谢支持！所有功能已永久解锁。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 20)
                .padding(.bottom, 24)

            } else {
                // ── 序列号输入区域 ──────────────────────
                VStack(spacing: 10) {
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $serialInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))
                        .onChange(of: serialInput) { newValue in
                            // 自动格式化输入，插入连字符（macOS 13 兼容写法）
                            serialInput = formatInput(newValue)
                            errorMessage = ""
                        }
                        .onSubmit {
                            attemptActivation()
                        }

                    if !errorMessage.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text(errorMessage)
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // ── 操作按钮区域 ──────────────────────
                HStack(spacing: 12) {
                    // 购买链接
                    Button {
                        if let url = URL(string: "https://your-website.com/buy") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("购买序列号")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Spacer()

                    // 激活按钮
                    Button {
                        attemptActivation()
                    } label: {
                        if isActivating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 60)
                        } else {
                            Text("激活")
                                .frame(width: 60)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isActivating || serialInput.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 320)
    }

    // MARK: - 私有方法

    /// 尝试激活序列号
    private func attemptActivation() {
        guard !serialInput.isEmpty else { return }
        isActivating = true
        errorMessage = ""

        // 使用 Task 模拟短暂处理动画，避免 UI 卡顿
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))

            do {
                try licenseManager.activate(serialKey: serialInput)
                withAnimation {
                    showSuccess = true
                }
            } catch let error as LicenseError {
                errorMessage = error.errorDescription ?? "激活失败"
            } catch {
                errorMessage = "激活失败，请重试"
            }

            isActivating = false
        }
    }

    /// 自动格式化输入，每 4 位添加连字符
    private func formatInput(_ input: String) -> String {
        // 仅保留字母和数字
        let cleaned = input
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(16)

        var result = ""
        for (index, char) in cleaned.enumerated() {
            if index > 0 && index % 4 == 0 {
                result.append("-")
            }
            result.append(char)
        }
        return result
    }
}
