import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// UIKit owns the bottom boundary so keyboard motion and interactive dismissal
/// have a single layout source. The footer stays behind the keyboard instead
/// of being removed halfway through a SwiftUI safe-area update.
struct KeyboardAnchoredLayout<Content: View, Dock: View, Footer: View>: UIViewControllerRepresentable {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var dock: () -> Dock
    @ViewBuilder var footer: () -> Footer

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content(), dock: dock(), footer: footer())
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.contentHost.rootView = AnyView(content().ignoresSafeArea(.keyboard))
        controller.dockHost.rootView = AnyView(dock().fixedSize(horizontal: false, vertical: true))
        controller.footerHost.rootView = AnyView(
            footer().fixedSize(horizontal: false, vertical: true).ignoresSafeArea(.keyboard))
    }

    final class Controller: UIViewController {
        let contentHost: UIHostingController<AnyView>
        let dockHost: UIHostingController<AnyView>
        let footerHost: UIHostingController<AnyView>

        init(content: Content, dock: Dock, footer: Footer) {
            contentHost = UIHostingController(rootView: AnyView(content.ignoresSafeArea(.keyboard)))
            dockHost = UIHostingController(rootView: AnyView(dock.fixedSize(horizontal: false, vertical: true)))
            footerHost = UIHostingController(
                rootView: AnyView(footer.fixedSize(horizontal: false, vertical: true).ignoresSafeArea(.keyboard)))
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            contentHost.safeAreaRegions = []
            footerHost.safeAreaRegions = []
            dockHost.safeAreaRegions = []
            dockHost.sizingOptions = .intrinsicContentSize
            dockHost.view.setContentCompressionResistancePriority(.required, for: .vertical)
            dockHost.view.setContentHuggingPriority(.required, for: .vertical)
            footerHost.sizingOptions = .intrinsicContentSize
            footerHost.view.setContentCompressionResistancePriority(.required, for: .vertical)
            footerHost.view.setContentHuggingPriority(.required, for: .vertical)
            for host in [footerHost, contentHost, dockHost] {
                addChild(host)
                host.view.backgroundColor = .clear
                host.view.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(host.view)
                host.didMove(toParent: self)
            }
            let restPosition = dockHost.view.bottomAnchor.constraint(equalTo: footerHost.view.topAnchor)
            restPosition.priority = .defaultHigh
            NSLayoutConstraint.activate([
                footerHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                footerHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                footerHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                contentHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                contentHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                contentHost.view.topAnchor.constraint(equalTo: view.topAnchor),
                dockHost.view.bottomAnchor.constraint(lessThanOrEqualTo: footerHost.view.topAnchor),
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
struct KeyboardAnchoredLayout<Content: View, Dock: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var dock: () -> Dock
    @ViewBuilder var footer: () -> Footer
    var body: some View {
        VStack(spacing: 0) {
            content(); dock(); footer()
        }
    }
}
#endif
