import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class KeyboardObserver: ObservableObject {
    static let shared = KeyboardObserver()

    @Published var isKeyboardVisible: Bool = false

    private var duration: Double = 0.25
    private var curve: Int = 0

    var transitionAnimation: Animation {
        switch curve {
        case 1: return .easeIn(duration: duration)
        case 2: return .easeOut(duration: duration)
        case 3: return .linear(duration: duration)
        default: return .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] in self?.update(visible: true, notification: $0) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] in self?.update(visible: false, notification: $0) }
            .store(in: &cancellables)
        #endif
    }

    private func update(visible: Bool, notification: Notification) {
        #if os(iOS)
        let systemDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        duration = systemDuration > 0 ? systemDuration : 0.25
        curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 0
        if isKeyboardVisible != visible { isKeyboardVisible = visible }
        #endif
    }
}
