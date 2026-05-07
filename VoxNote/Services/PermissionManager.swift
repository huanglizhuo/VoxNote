import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import os.log

private let permLogger = Logger(subsystem: "com.voxnote", category: "PermissionManager")

/// Checks and requests system permissions needed for dictation (accessibility, microphone).
@MainActor
final class PermissionManager: ObservableObject {
    @Published var isAccessibilityGranted = false
    @Published var isMicrophoneGranted = false

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let axTrusted = AXIsProcessTrusted()
        permLogger.info("AXIsProcessTrusted = \(axTrusted)")
        isAccessibilityGranted = axTrusted
        isMicrophoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Check accessibility permission, optionally prompting the user.
    @discardableResult
    func checkAccessibility(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permLogger.info("AXIsProcessTrustedWithOptions(prompt=\(prompt)) = \(trusted)")
        isAccessibilityGranted = trusted
        return isAccessibilityGranted
    }

    func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        isMicrophoneGranted = granted
        return granted
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
