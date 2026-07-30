import SwiftUI

struct AccountToolbarControl: View {
    @ObservedObject var account: AccountViewModel

    var body: some View {
        if let session = account.session {
            Menu {
                Text(session.displayName)
                if let email = session.email, email != session.displayName {
                    Text(email)
                }
                Divider()
                Button("退出登录", role: .destructive) {
                    account.logout()
                }
            } label: {
                Image(systemName: "person.crop.circle.fill")
            }
            .help("已登录：\(session.displayName)")
        } else {
            Button {
                account.clearError()
                account.isLoginSheetPresented = true
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .help("登录 MOJi")
        }
    }
}

struct LoginView: View {
    @ObservedObject var account: AccountViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var email = ""
    @State private var password = ""
    @State private var agreesToTerms = false

    private enum Field {
        case email
        case password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("登录 MOJi")
                    .font(.title3.weight(.semibold))
                Text("会话令牌保存在 macOS 钥匙串中；密码不会保存。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("邮箱地址", text: $email)
                    .textContentType(.emailAddress)
                    .focused($focusedField, equals: .email)

                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .privacySensitive()
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        submitIfPossible()
                    }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 116)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("我同意 MOJi 的用户协议和隐私政策", isOn: $agreesToTerms)
                HStack(spacing: 12) {
                    Link("查看用户协议", destination: URL(
                            string: "https://www.shareintelli.com/mojidict-terms-of-use/"
                        )!
                    )
                    Link("查看隐私政策", destination: URL(
                            string: "https://www.shareintelli.com/mojidict-privacy-policy/"
                        )!
                    )
                }
                .font(.caption)
            }

            if let error = account.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消") {
                    password = ""
                    dismiss()
                }
                Button {
                    submit()
                } label: {
                    if account.isLoggingIn {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 48)
                    } else {
                        Text("登录")
                            .frame(width: 48)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 460)
        .font(.callout)
        .onAppear {
            focusedField = .email
        }
        .onDisappear {
            password = ""
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && agreesToTerms
            && !account.isLoggingIn
    }

    private func submitIfPossible() {
        guard canSubmit else { return }
        submit()
    }

    private func submit() {
        let submittedEmail = email
        let submittedPassword = password
        password = ""

        Task {
            let succeeded = await account.login(
                email: submittedEmail,
                password: submittedPassword
            )
            if succeeded {
                dismiss()
            }
        }
    }
}
