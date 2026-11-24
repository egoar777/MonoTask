import AuthenticationServices
import SwiftUI

struct AuthView: View {
    let isLaunching: Bool
    let departureUserID: UUID?
    let onDepartureFinished: () -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode?
    @State private var folderCorners: [UnitPoint] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
    @State private var departureAnimationID: UUID?
    @FocusState private var focusedField: Field?
    private enum Field { case email, password }
    private enum Mode {
        case signIn, signUp

        var heading: String { self == .signUp ? "Регистрация" : "Вход в аккаунт" }
        var actionTitle: String { self == .signUp ? "Создать аккаунт" : "Войти" }
    }
    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !auth.isBusy
    }

    private var isDeparting: Bool { departureAnimationID != nil }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                page
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
            .monoScrollEdge()
        }
        .opacity(isDeparting ? 0 : 1)
        .animation(.easeOut(duration: 0.24), value: isDeparting)
        .overlay {
            GeometryReader { geometry in
                let showsCorners = geometry.size.height >= 660 && !dynamicTypeSize.isAccessibilitySize
                let isPreparingDeparture = departureUserID != nil && !reduceMotion
                let isVisible = isPreparingDeparture || (showsCorners && focusedField == nil)
                cornerFolders(in: geometry.size)
                    .opacity(isVisible ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: isPreparingDeparture ? 0.14 : 0.26),
                        value: isVisible
                    )
                    .opacity(isLaunching ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.36), value: isLaunching)
                    .allowsHitTesting(isVisible && !isLaunching && departureUserID == nil)
            }
            .ignoresSafeArea(.keyboard)
            .accessibilityHidden(true)
        }
        .allowsHitTesting(departureUserID == nil)
        .accessibilityHidden(departureUserID != nil)
        .task(id: departureUserID) { await depart(afterSigningIn: departureUserID) }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled && departureUserID != nil { onDepartureFinished() }
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
    }

    private func depart(afterSigningIn userID: UUID?) async {
        guard let userID else {
            departureAnimationID = nil
            return
        }
        guard !reduceMotion else {
            onDepartureFinished()
            return
        }

        focusedField = nil
        // Give folders hidden by the keyboard or a compact layout time to appear.
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled, auth.userID == userID else { return }

        let animationID = UUID()
        withAnimation(.timingCurve(0.32, 0, 0.62, 1, duration: 0.44)) {
            departureAnimationID = animationID
        } completion: {
            guard departureAnimationID == animationID, auth.userID == userID else { return }
            onDepartureFinished()
        }
    }

    private var page: some View {
        VStack(spacing: 28) {
            AuthBrandHeader(title: mode?.heading ?? "MonoTask", titleTransition: pageTransition)
                .anchorPreference(key: AuthBrandBoundsKey.self, value: .bounds) { bounds in
                    isLaunching ? bounds : nil
                }
                .opacity(isLaunching ? 0 : 1)

            VStack(spacing: 28) {
                if let mode {
                    form(for: mode)
                    backButton
                } else {
                    welcome
                        .opacity(isLaunching ? 0 : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.36), value: isLaunching)
                }
            }
            .id(mode)
            .transition(pageTransition)
        }
        .frame(maxWidth: 380)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let direction: CGFloat = mode == nil ? -1 : 1
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: direction * 24))
                .combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .offset(y: direction * 14))
        )
    }

    private func cornerFolders(in size: CGSize) -> some View {
        ZStack {
            cornerFolder(0, tint: Color(hex: "#5AA9FF"), icon: "tray.fill", width: 76, angle: -14, in: size)
            cornerFolder(1, tint: Theme.Colors.accent, icon: "checkmark", width: 108, angle: 13, in: size)
            cornerFolder(2, tint: Color(hex: "#B48CFF"), icon: "star.fill", width: 104, angle: -11, in: size)
            cornerFolder(3, tint: Color(hex: "#3DDC97"), icon: "calendar", width: 72, angle: 16, in: size)
        }
        .coordinateSpace(.named("auth-folders"))
    }

    private func cornerFolder(
        _ index: Int, tint: Color, icon: String, width: CGFloat, angle: Double, in size: CGSize
    ) -> some View {
        AuthCornerFolder(
            tint: tint, icon: icon, width: width, angle: angle, anchor: folderCorners[index],
            bounds: size, isDeparting: isDeparting
        ) {
            corner in
            guard let occupant = folderCorners.firstIndex(of: corner), occupant != index else { return }
            folderCorners.swapAt(index, occupant)
        }
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                entryButton(Mode.signIn.actionTitle, to: .signIn, prominent: true)
                entryButton(Mode.signUp.actionTitle, to: .signUp)
            }
            socialSignIn
            messages
        }
    }

    private func form(for mode: Mode) -> some View {
        let creatingAccount = mode == .signUp
        return VStack(spacing: 20) {
            VStack(spacing: 12) {
                field("Электронная почта", focus: .email) {
                    TextField(
                        "Электронная почта", text: $email,
                        prompt: Text(verbatim: "name@example.com").foregroundStyle(Theme.Colors.textMuted)
                    )
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                }
                .modifier(AuthFormReveal(delay: 0.04))

                field("Пароль", focus: .password) {
                    SecureField(
                        "Пароль", text: $password,
                        prompt: Text(creatingAccount ? "Не менее 6 символов" : "Ваш пароль")
                            .foregroundStyle(Theme.Colors.textMuted)
                    )
                    .textContentType(creatingAccount ? .newPassword : .password)
                    .submitLabel(.go)
                    .onSubmit { submit(mode) }
                }
                .modifier(AuthFormReveal(delay: 0.14))
            }
            .disabled(auth.isBusy)

            messages

            Button {
                submit(mode)
            } label: {
                AuthActionLabel(
                    title: mode.actionTitle, prominent: true, isBusy: auth.isBusy
                )
            }
            .buttonStyle(FullSurfaceButtonStyle())
            .disabled(!canSubmit)
            .modifier(AuthFormReveal(delay: 0.24))
        }
    }

    private func field<Content: View>(_ title: String, focus: Field, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Theme.Typography.section)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.leading, 18)
                .accessibilityHidden(true)
            content()
                .focused($focusedField, equals: focus)
                .modifier(AuthFieldStyle(isFocused: focusedField == focus))
        }
    }

    private var socialSignIn: some View {
        VStack(spacing: 12) {
            Text("Или войти через")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                providerButton(.google)
                providerButton(.apple)
            }
        }
        .disabled(auth.isBusy)
    }

    private func providerButton(_ provider: AuthManager.SocialProvider) -> some View {
        Button {
            Task {
                await auth.signIn(with: provider) { url in
                    try await webAuthenticationSession.authenticate(
                        using: url,
                        callback: .customScheme(AuthManager.callbackScheme),
                        additionalHeaderFields: [:])
                }
            }
        } label: {
            Group {
                if auth.activeSocialProvider == provider {
                    ProgressView().controlSize(.small)
                } else if provider == .google {
                    Image("GoogleSignInMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 23, height: 23)
                        .offset(x: 1)
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 24, weight: .medium))
                        .offset(x: 1.5, y: -2)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(
                provider == .google ? Color(hex: "#131314") : Color.black,
                in: .circle
            )
            .overlay {
                Circle()
                    .strokeBorder(Color(hex: "#8E918F"))
                    .allowsHitTesting(false)
            }
            .contentShape(Circle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .accessibilityLabel("Войти через \(provider.name)")
    }

    @ViewBuilder private var messages: some View {
        if let error = auth.errorMessage {
            Label(error, systemImage: "exclamationmark.circle")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.danger)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Ошибка: \(error)")
        }
        if let info = auth.infoMessage {
            Text(info)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.accent)
                .multilineTextAlignment(.center)
        }
    }

    private var backButton: some View {
        Button {
            show(nil)
        } label: {
            Label("Назад", systemImage: "chevron.left")
                .font(Theme.Typography.section)
                .foregroundStyle(Theme.Colors.accent)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.Spacing.touchTargetMin)
                .background(Theme.Colors.accent.opacity(0.075), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(Theme.Colors.accent.opacity(0.75))
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .disabled(auth.isBusy)
        .modifier(AuthFormReveal(delay: 0.30))
    }

    private func entryButton(_ title: String, to mode: Mode, prominent: Bool = false) -> some View {
        Button {
            show(mode)
        } label: {
            AuthActionLabel(title: title, prominent: prominent)
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .disabled(auth.isBusy)
    }

    private func show(_ mode: Mode?) {
        guard mode != self.mode else { return }
        focusedField = nil
        auth.errorMessage = nil
        auth.infoMessage = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.34)) {
            self.mode = mode
        }
    }

    private func submit(_ mode: Mode) {
        guard canSubmit else { return }
        if mode == .signUp && password.count < 6 {
            auth.errorMessage = "Пароль должен содержать не менее 6 символов."
            focusedField = .password
            return
        }
        focusedField = nil
        Task {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if mode == .signUp {
                await auth.signUp(email: trimmed, password: password)
            } else {
                await auth.signIn(email: trimmed, password: password)
            }
        }
    }
}

private struct AuthFormReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let delay: Double

    func body(content: Content) -> some View {
        let isVisible = appeared || reduceMotion
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .scaleEffect(isVisible ? 1 : 0.98)
            .animation(reduceMotion ? nil : .smooth(duration: 0.42).delay(delay), value: appeared)
            .task { appeared = true }
    }
}

struct AuthBrandBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct AuthBrandHeader: View {
    let title: String
    var titleTransition: AnyTransition = .identity

    var body: some View {
        VStack(spacing: 14) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.displayLarge)
                .tracking(Theme.Typography.displayTracking)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .id(title)
                .transition(titleTransition)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

struct AuthActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let prominent: Bool
    var isBusy = false

    private var usesSolidFill: Bool { prominent && (isEnabled || isBusy) }

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().tint(Theme.Colors.onAccent)
                    .accessibilityHidden(true)
            }
            Text(title).multilineTextAlignment(.center)
        }
        .font(.headline)
        .foregroundStyle(usesSolidFill ? Theme.Colors.onAccent : Theme.Colors.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            Theme.Colors.accent.opacity(usesSolidFill ? 1 : (prominent ? 0.28 : 0.075)),
            in: .capsule
        )
        .overlay {
            if !prominent {
                Capsule()
                    .strokeBorder(Theme.Colors.accent.opacity(0.75))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Capsule())
    }
}

private struct AuthCornerFolder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color
    let icon: String
    let width: CGFloat
    let angle: Double
    let anchor: UnitPoint
    let bounds: CGSize
    let isDeparting: Bool
    let moveToCorner: (UnitPoint) -> Void

    @State private var dragOrigin: CGPoint?
    @State private var draggedCenter: CGPoint?
    @State private var tapCount = 0
    @GestureState private var isDragging = false

    private var inset: CGFloat { width / 2 + 10 }
    private var center: CGPoint {
        CGPoint(
            x: anchor.x == 0 ? inset : bounds.width - inset,
            y: anchor.y == 0 ? inset : bounds.height - inset
        )
    }

    private var horizontalDirection: CGFloat { anchor.x == 0 ? -1 : 1 }
    private var verticalDirection: CGFloat { anchor.y == 0 ? -1 : 1 }
    private var departureCenter: CGPoint {
        CGPoint(
            x: anchor.x * bounds.width + horizontalDirection * width * 0.67,
            y: center.y + verticalDirection * (width * 0.78 + 24)
        )
    }

    var body: some View {
        ClassicFolderArtwork(tint: tint, icon: icon)
            .frame(width: width, height: width * 0.78)
            .contentShape(Rectangle())
            .phaseAnimator([false, true, false], trigger: tapCount) { artwork, isPressed in
                artwork
                    .scaleEffect(isPressed && !reduceMotion ? 0.9 : 1)
                    .rotationEffect(.degrees(angle + (isPressed && !reduceMotion ? 7 : 0)))
            } animation: { pressed in
                pressed ? .easeOut(duration: 0.09) : .spring(duration: 0.32, bounce: 0.48)
            }
            .scaleEffect(isDragging && !reduceMotion ? 1.1 : 1)
            .animation(.spring(duration: 0.28, bounce: 0.24), value: isDragging)
            .rotationEffect(.degrees(isDeparting ? 28 * Double(horizontalDirection) : 0))
            .position(isDeparting ? departureCenter : (draggedCenter ?? center))
            .gesture(drag)
            .onTapGesture {
                Haptics.light()
                tapCount += 1
            }
            .onChange(of: isDragging) { _, dragging in
                if !dragging && draggedCenter != nil { settle(in: anchor) }
            }
            .zIndex(isDragging ? 1 : 0)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("auth-folders"))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = center
                    Haptics.light()
                }
                draggedCenter = boundedCenter(by: value.translation)
            }
            .onEnded { value in
                let translation = reduceMotion ? value.translation : value.predictedEndTranslation
                let target = boundedCenter(by: translation)
                settle(in: UnitPoint(x: target.x < bounds.width / 2 ? 0 : 1, y: target.y < bounds.height / 2 ? 0 : 1))
                Haptics.selection()
            }
    }

    private func boundedCenter(by translation: CGSize) -> CGPoint {
        let origin = dragOrigin ?? center
        return CGPoint(
            x: min(max(origin.x + translation.width, inset), bounds.width - inset),
            y: min(max(origin.y + translation.height, inset), bounds.height - inset)
        )
    }

    private func settle(in corner: UnitPoint) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.33)) {
            moveToCorner(corner)
            draggedCenter = nil
            dragOrigin = nil
        }
    }
}

private struct AuthFieldStyle: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Colors.surface, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(isFocused ? Theme.Colors.accent : Theme.Colors.ruleStrong, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
