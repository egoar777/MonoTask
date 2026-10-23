import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class KeyboardObserver: ObservableObject {
    static let shared = KeyboardObserver()

    @Published var isKeyboardVisible: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.isKeyboardVisible = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
            .sink { [weak self] _ in self?.isKeyboardVisible = false }
            .store(in: &cancellables)
        #endif
    }
}
