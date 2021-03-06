import Cocoa

extension AXUIElement {
    static let globalTimeoutInSeconds = Float(120)

    // default timeout for AX calls is 6s. We increase it in order to avoid retrying every 6s, thus saving resources
    static func setGlobalTimeout() {
        // we add 5s to make sure to not do an extra retry
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), globalTimeoutInSeconds + 5)
    }

    static let normalLevel = CGWindowLevelForKey(.normalWindow)

    func axCallWhichCanThrow<T>(_ result: AXError, _ successValue: inout T) throws -> T? {
        switch result {
            case .success: return successValue
            // .cannotComplete can happen if the app is unresponsive; we throw in that case to retry until the call succeeds
            case .cannotComplete: throw AxError.runtimeError
            // for other errors it's pointless to retry
            default: return nil
        }
    }

    func cgWindowId() throws -> CGWindowID? {
        var id = CGWindowID(0)
        return try axCallWhichCanThrow(_AXUIElementGetWindow(self, &id), &id)
    }

    func pid() throws -> pid_t? {
        var pid = pid_t(0)
        return try axCallWhichCanThrow(AXUIElementGetPid(self, &pid), &pid)
    }

    func attribute<T>(_ key: String, _ type: T.Type) throws -> T? {
        var value: AnyObject?
        return try axCallWhichCanThrow(AXUIElementCopyAttributeValue(self, key as CFString, &value), &value) as? T
    }

    private func value<T>(_ key: String, _ target: T, _ type: AXValueType) throws -> T? {
        if let a = try attribute(key, AXValue.self) {
            var value = target
            AXValueGetValue(a, type, &value)
            return value
        }
        return nil
    }

    func isActualWindow(_ runningApp: NSRunningApplication, _ wid: CGWindowID, _ isOnNormalLevel: Bool, _ title: String?, _ subrole: String?, _ role: String?) -> Bool {
        // Some non-windows have title: nil (e.g. some OS elements)
        // Some non-windows have subrole: nil (e.g. some OS elements), "AXUnknown" (e.g. Bartender), "AXSystemDialog" (e.g. Intellij tooltips)
        // Minimized windows or windows of a hidden app have subrole "AXDialog"
        // Activity Monitor main window subrole is "AXDialog" for a brief moment at launch; it then becomes "AXStandardWindow"

        // Some non-windows have cgWindowId == 0 (e.g. windows of apps starting at login with the checkbox "Hidden" checked)
        return wid != 0 &&
            // CGWindowLevel == .normalWindow helps filter out iStats Pro and other top-level pop-overs, and floating windows
            isOnNormalLevel &&
            (["AXStandardWindow", "AXDialog"].contains(subrole) ||
                steam(runningApp, title, role) ||
                firefoxFullscreenVideo(runningApp, role) ||
                androidEmulator(runningApp, title) ||
                sanGuoShaAirWD(runningApp) ||
                dvdFab(runningApp) ||
                drBetotte(runningApp))
    }

    private func drBetotte(_ runningApp: NSRunningApplication) -> Bool {
        return runningApp.bundleIdentifier == "com.ssworks.drbetotte"
    }

    private func dvdFab(_ runningApp: NSRunningApplication) -> Bool {
        return runningApp.bundleIdentifier == "com.goland.dvdfab.macos"
    }

    private func sanGuoShaAirWD(_ runningApp: NSRunningApplication) -> Bool {
        return runningApp.bundleIdentifier == "SanGuoShaAirWD"
    }

    private func steam(_ runningApp: NSRunningApplication, _ title: String?, _ role: String?) -> Bool {
        // All Steam windows have subrole == AXUnknown
        // some dropdown menus are not desirable; they have title == "", or sometimes role == nil when switching between menus quickly
        return runningApp.bundleIdentifier == "com.valvesoftware.steam" && title != "" && role != nil
    }

    private func firefoxFullscreenVideo(_ runningApp: NSRunningApplication, _ role: String?) -> Bool {
        // Firefox fullscreen video have subrole == AXUnknown if fullscreen'ed when the base window is not fullscreen
        return runningApp.bundleIdentifier == "org.mozilla.firefox" && role == "AXWindow"
    }

    private func androidEmulator(_ runningApp: NSRunningApplication, _ title: String?) -> Bool {
        // android emulator small vertical menu is a "window" with empty title; we exclude it
        if title != "",
           // NSRunningApplication provides no way to identify the emulator; we pattern match on its KERN_PROCARGS
           runningApp.bundleIdentifier == nil,
           let executablePath = Sysctl.run([CTL_KERN, KERN_PROCARGS, runningApp.processIdentifier]) {
            // example path: ~/Library/Android/sdk/emulator/qemu/darwin-x86_64/qemu-system-x86_64
            return executablePath.range(of: "qemu-system[^/]*$", options: .regularExpression, range: nil, locale: nil) != nil
        }
        return false
    }

    func isOnNormalLevel(_ wid: CGWindowID) -> Bool {
        let level: CGWindowLevel = wid.level()
        return level == AXUIElement.normalLevel
    }

    func position() throws -> CGPoint? {
        return try value(kAXPositionAttribute, CGPoint.zero, .cgPoint)
    }

    func title() throws -> String? {
        return try attribute(kAXTitleAttribute, String.self)
    }

    func parent() throws -> AXUIElement? {
        return try attribute(kAXParentAttribute, AXUIElement.self)
    }

    func windows() throws -> [AXUIElement]? {
        return try attribute(kAXWindowsAttribute, [AXUIElement].self)
    }

    func isMinimized() throws -> Bool {
        return try attribute(kAXMinimizedAttribute, Bool.self) == true
    }

    func isFullscreen() throws -> Bool {
        return try attribute(kAXFullscreenAttribute, Bool.self) == true
    }

    func focusedWindow() throws -> AXUIElement? {
        return try attribute(kAXFocusedWindowAttribute, AXUIElement.self)
    }

    func role() throws -> String? {
        return try attribute(kAXRoleAttribute, String.self)
    }

    func subrole() throws -> String? {
        return try attribute(kAXSubroleAttribute, String.self)
    }

    func closeButton() throws -> AXUIElement? {
        return try attribute(kAXCloseButtonAttribute, AXUIElement.self)
    }

    func focusWindow() {
        performAction(kAXRaiseAction)
    }

    func subscribeToNotification(_ axObserver: AXObserver, _ notification: String, _ callback: (() -> Void)? = nil, _ runningApplication: NSRunningApplication? = nil, _ wid: CGWindowID? = nil, _ startTime: DispatchTime = DispatchTime.now()) throws {
        let result = AXObserverAddNotification(axObserver, self, notification as CFString, nil)
        if result == .success || result == .notificationAlreadyRegistered {
            callback?()
        } else if result != .notificationUnsupported && result != .notImplemented {
            throw AxError.runtimeError
        }
    }

    func setAttribute(_ key: String, _ value: Any) {
        AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef)
    }

    func performAction(_ action: String) {
        AXUIElementPerformAction(self, action as CFString)
    }
}

enum AxError: Error {
    case runtimeError
}
