import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var creatingAccount = false
    @FocusState private var focusedField: Field?
    private enum Field { case email, password }
    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !auth.isBusy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                CurrentDateLabel()
                VStack(alignment: .leading, spacing: 14) {
                    EyebrowLabel(text: "Личное пространство")
                    Text("MONOTASK")
                        .font(Theme.Typography.display)
                        .foregroundColor(Theme.Colors.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(creatingAccount ? "РЕГИСТРАЦИЯ" : "ВХОД")
                        .font(Theme.Typography.heading(22))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Задачи и синхронизация в вашем аккаунте.")
                        .font(Theme.Typography.callout)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        EyebrowLabel(text: "Email")
                        TextField(
                            "Email", text: $email,
                            prompt: Text(verbatim: "name@example.com").foregroundColor(Theme.Colors.textMuted)
                        )
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .modifier(AuthFieldStyle())
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        EyebrowLabel(text: "Пароль")
                        SecureField(creatingAccount ? "Не менее 6 символов" : "Ваш пароль", text: $password)
                            .textContentType(creatingAccount ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                            .modifier(AuthFieldStyle())
                    }
                    if let error = auth.errorMessage {
                        Text(error).font(Theme.Typography.callout).foregroundColor(Theme.Colors.danger)
                            .accessibilityLabel("Ошибка: \(error)")
                    }
                    if let info = auth.infoMessage {
                        Text(info).font(Theme.Typography.callout).foregroundColor(Theme.Colors.accent)
                    }
                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if auth.isBusy { ProgressView().tint(Theme.Colors.onAccent) }
                            Text(creatingAccount ? "Создать аккаунт" : "Войти")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.Colors.accent.opacity(canSubmit || auth.isBusy ? 1 : 0.35))
                        .foregroundColor(canSubmit || auth.isBusy ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    }
                    .buttonStyle(FullSurfaceButtonStyle())
                    .disabled(!canSubmit)
                }
                .disabled(auth.isBusy)
                Button {
                    creatingAccount.toggle()
                    auth.errorMessage = nil
                    auth.infoMessage = nil
                } label: {
                    Text(creatingAccount ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Зарегистрироваться")
                        .font(Theme.Typography.callout)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(FullSurfaceButtonStyle())
                .disabled(auth.isBusy)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .monoScrollEdge()
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
    }

    private func submit() {
        guard canSubmit else { return }
        if creatingAccount && password.count < 6 {
            auth.errorMessage = "Пароль должен содержать не менее 6 символов."
            focusedField = .password
            return
        }
        focusedField = nil
        Task {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if creatingAccount {
                await auth.signUp(email: trimmed, password: password)
            } else {
                await auth.signIn(email: trimmed, password: password)
            }
        }
    }
}

private struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.Colors.ruleStrong, lineWidth: 1))
    }
}
