import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var aboutWindow: NSWindow?
    private var aboutWindowDelegate: WindowDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor @objc func showAboutWindow() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = currentLocale.identifier.hasPrefix("zh") ? "关于 BrewGraph" : "About BrewGraph"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(
            rootView: AppAboutView()
                .environment(\.locale, currentLocale)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        let delegate = WindowDelegate { [weak self] in
            self?.aboutWindow = nil
            self?.aboutWindowDelegate = nil
        }
        window.delegate = delegate
        aboutWindowDelegate = delegate

        aboutWindow = window
    }

    private var currentLocale: Locale {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.appLanguage) ?? AppLanguage.english.rawValue
        let language = AppLanguage(rawValue: raw) ?? .english
        return Locale(identifier: language.localeCode)
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct AppAboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            }

            VStack(spacing: 4) {
                Text("BrewGraph")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Version \(appVersion) (\(appBuild))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A read-only inspector for your Homebrew installation.\nBrowse installed formulae, explore dependency graphs, and discover maintenance insights.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .frame(width: 240)

            Link("View on GitHub", destination: URL(string: "https://github.com/chaserli/brewgraph")!)
                .font(.caption)
        }
        .padding(36)
        .frame(width: 420)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
