import Foundation
import AVFoundation
import ApplicationServices
import AppKit

public enum MicStatus: Sendable, Equatable { case granted, denied, notDetermined }

public enum Permissions {
    public static func accessibilityGranted(prompt: Bool) -> Bool {
        // Literal value of kAXTrustedCheckOptionPrompt (the global is not concurrency-safe in Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func microphoneStatus() -> MicStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Never prompts.
    public static func screenRecordingGranted() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Asks macOS for the grant (shows its prompt the first time). macOS often applies it only after a relaunch.
    @discardableResult public static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    public static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
