import SwiftUI
import AppKit

/// 激活/找回序列号 弹窗视图
struct ActivationView: View {

    @ObservedObject var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - 状态

    /// 当前显示模式：激活 / 找回 / 成功
    private enum ViewMode { case activate, recover, success(String) }

    @State private var mode: ViewMode = .activate
    @State private var emailInput: String = ""
    @State private var serialInput: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .activate:    activateContent
            case .recover:     recoverContent
            case .success(let msg): successContent(message: msg)
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // MARK: - 激活视图

    private var activateContent: some View {
        VStack(spacing: 0) {
            header(icon: "key.fill", title: "激活输入法锁定",
                   subtitle: licenseManager.isInTrial
                       ? "试用期剩余 \(licenseManager.trialDaysRemaining) 天，激活后永久使用"
                       : "试用期已结束，请激活以继续使用")

            VStack(spacing: 12) {
                // 邮箱输入框
                inputField(
                    icon: "envelope",
                    placeholder: "购买时使用的邮箱",
                    text: $emailInput
                )

                // 序列号输入框
                inputField(
                    icon: "number",
                    placeholder: "XXXX-XXXX-XXXX-XXXX",
                    text: $serialInput
                )
                .onChange(of: serialInput) { newValue in
                    serialInput = formatSerial(newValue)
                    errorMessage = ""
                }
                .font(.system(size: 14, design: .monospaced))

                errorRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // 操作按钮
            HStack {
                Button("忘记序列号") {
                    withAnimation { mode = .recover }
                    emailInput = ""
                    errorMessage = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.system(size: 12))
                
                Button("购买激活码") {
                    if let url = URL(string: "https://cklaozhao.me/#/post/ck20260222224940216") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.system(size: 12))
                .padding(.leading, 8)

                Spacer()

                Button { Task { await attemptActivation() } } label: {
                    loadingLabel("激活")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || emailInput.isEmpty || serialInput.count < 19)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - 找回序列号视图

    private var recoverContent: some View {
        VStack(spacing: 0) {
            header(icon: "envelope.badge.shield.half.filled",
                   title: "找回序列号",
                   subtitle: "输入购买时使用的邮箱，我们将把序列号发送到该邮箱")

            VStack(spacing: 12) {
                inputField(
                    icon: "envelope",
                    placeholder: "购买时使用的邮箱",
                    text: $emailInput
                )
                errorRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            HStack {
                Button("返回激活") {
                    withAnimation { mode = .activate }
                    errorMessage = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

                Spacer()

                Button { Task { await attemptRecover() } } label: {
                    loadingLabel("发送邮件")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || emailInput.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - 成功视图

    private func successContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .scaleEffect(1.0)
                .padding(.top, 28)

            Text(message)
                .font(.system(size: 15, weight: .semibold))

            Text("感谢你的支持！")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button("关闭") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 共用子组件

    private func header(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .padding(.top, 24)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 4)
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { _ in errorMessage = "" }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var errorRow: some View {
        if !errorMessage.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                Text(errorMessage)
                    .font(.system(size: 12))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadingLabel(_ title: String) -> some View {
        Group {
            if isLoading {
                ProgressView().scaleEffect(0.7).frame(width: 70)
            } else {
                Text(title).frame(width: 70)
            }
        }
    }

    // MARK: - 业务逻辑

    private func attemptActivation() async {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else {
            errorMessage = "请输入正确的邮箱地址"
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await licenseManager.activate(email: email, serial: serialInput)
            withAnimation { mode = .success("激活成功！") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attemptRecover() async {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else {
            errorMessage = "请输入正确的邮箱地址"
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await licenseManager.recoverKey(email: email)
            withAnimation { mode = .success("邮件已发送！\n请查收邮箱中的序列号。") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 工具

    /// 邮箱格式正则校验
    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// 序列号自动格式化（每 4 位加 -）
    private func formatSerial(_ input: String) -> String {
        let cleaned = input.uppercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(16)
        var result = ""
        for (index, char) in cleaned.enumerated() {
            if index > 0 && index % 4 == 0 { result.append("-") }
            result.append(char)
        }
        return result
    }
}
