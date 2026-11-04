import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate   // NSApplication holds the delegate weakly; `delegate` lives for the whole run() call
    app.run()
}
