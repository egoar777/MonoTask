import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// UIKit owns the content boundary during keyboard motion and interactive dismissal.
struct KeyboardAnchoredLayout<Content: View, Dock: View>: UIViewControllerRepresentable {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var dock: () -> Dock

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content(), dock: dock())
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.contentHost.rootView = AnyView(content().ignoresSafeArea(.keyboard))
        controller.dockHost.rootView = AnyView(dock().fixedSize(horizontal: false, vertical: true))
    }

    final class Controller: UIViewController {
        let contentHost: UIHostingController<AnyView>
        let dockHost: UIHostingController<AnyView>

        init(content: Content, dock: Dock) {
            contentHost = UIHostingController(rootView: AnyView(content.ignoresSafeArea(.keyboard)))
            dockHost = UIHostingController(rootView: AnyView(dock.fixedSize(horizontal: false, vertical: true)))
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            // With no keyboard, allow content to reach the physical bottom edge.
            // The default keyboard guide stops at the home-indicator safe area.
            view.keyboardLayoutGuide.usesBottomSafeArea = false
            contentHost.safeAreaRegions = []
            dockHost.safeAreaRegions = []
            dockHost.sizingOptions = .intrinsicContentSize
            dockHost.view.setContentCompressionResistancePriority(.required, for: .vertical)
            dockHost.view.setContentHuggingPriority(.required, for: .vertical)
            for host in [contentHost, dockHost] {
                addChild(host)
                host.view.backgroundColor = .clear
                host.view.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(host.view)
                host.didMove(toParent: self)
            }
            let restPosition = dockHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            restPosition.priority = .defaultHigh
            NSLayoutConstraint.activate([
                contentHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                contentHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                contentHost.view.topAnchor.constraint(equalTo: view.topAnchor),
                dockHost.view.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
                dockHost.view.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor),
                dockHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                dockHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                contentHost.view.bottomAnchor.constraint(equalTo: dockHost.view.topAnchor),
                restPosition,
            ])
        }
    }
}
#else
struct KeyboardAnchoredLayout<Content: View, Dock: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var dock: () -> Dock
    var body: some View {
        VStack(spacing: 0) {
            content(); dock()
        }
    }
}
#endif
