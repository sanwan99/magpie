import AppKit
import CoreGraphics
import Foundation

enum ScreenshotResult: Equatable {
    case captured
    case saved
    case presented
    case copiedText
    case cancelledOrNonImage
    case permissionDenied
    case launchFailed(String)
}

@MainActor
protocol ScreenCapturePermissionProviding {
    func hasAccess() -> Bool
    func requestAccess() -> Bool
}

@MainActor
struct SystemScreenCapturePermission: ScreenCapturePermissionProviding {
    func hasAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

@MainActor
protocol ScreenshotPasteboardWriting {
    func writePNG(_ data: Data) -> Bool
    func writeText(_ text: String) -> Bool
}

@MainActor
struct GeneralScreenshotPasteboard: ScreenshotPasteboardWriting {
    func writeText(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
    func writePNG(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setData(data, forType: .png)
    }
}

@MainActor
protocol ScreenshotPanelControlling: AnyObject {
    var isVisible: Bool { get }
    func hide(completion: (() -> Void)?)
    func show()
}

extension PanelController: ScreenshotPanelControlling {}

@MainActor
protocol ScreenshotClipboardRouting: AnyObject {
    func prepareNextChange(origin: ClipboardChangeOrigin)
    func cancelPreparedChange(origin: ClipboardChangeOrigin)
    @discardableResult
    func pollNow(origin: ClipboardChangeOrigin) -> Bool
}

extension ClipboardWatcher: ScreenshotClipboardRouting {}

@MainActor
protocol ScreenshotFeedbackPresenting {
    func showPermissionDenied()
    func showLaunchFailure(_ message: String)
    func openPermissionSettings()
}

@MainActor
struct SystemScreenshotFeedbackPresenter: ScreenshotFeedbackPresenting {
    func showPermissionDenied() {
        let language = SettingsStore.shared.language
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = language.pick(
            zh: "需要屏幕录制权限",
            en: "Screen Recording permission required"
        )
        alert.informativeText = language.pick(
            zh: "请在系统设置的“隐私与安全性 → 录屏与系统录音”中允许 Magpie，再按系统提示重新打开应用。如果已经开启仍不能截图，请移除列表中的 Magpie，再添加“应用程序”里的 Magpie。也可从菜单栏的“屏幕录制权限…”返回这里。",
            en: "Allow Magpie in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen it if macOS asks. If access is already enabled but capture still fails, remove Magpie from that list and add the copy in Applications. You can return here using Screen Recording Permission… in the menu bar."
        )
        alert.addButton(withTitle: language.pick(zh: "打开系统设置", en: "Open System Settings"))
        alert.addButton(withTitle: language.pick(zh: "取消", en: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn { openPermissionSettings() }
    }

    func openPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func showLaunchFailure(_ message: String) {
        let language = SettingsStore.shared.language
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = language.pick(zh: "无法启动截图工具", en: "Unable to start screenshot tool")
        alert.informativeText = message
        alert.addButton(withTitle: language.pick(zh: "好", en: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
final class ScreenshotCoordinator {
    private let permission: ScreenCapturePermissionProviding
    private let session: ScreenshotSessionRunning
    private let pasteboard: ScreenshotPasteboardWriting
    private weak var panel: ScreenshotPanelControlling?
    private weak var clipboardRouter: ScreenshotClipboardRouting?
    private let feedback: ScreenshotFeedbackPresenting

    private var isCheckingPermission = false
    private var requestedPermission = false
    private var showedPermissionHelp = false
    private(set) var isCapturing = false
    private(set) var lastResult: ScreenshotResult?

    convenience init(
        panel: ScreenshotPanelControlling,
        clipboardRouter: ScreenshotClipboardRouting
    ) {
        self.init(
            permission: SystemScreenCapturePermission(),
            session: NativeScreenshotSession(),
            pasteboard: GeneralScreenshotPasteboard(),
            panel: panel,
            clipboardRouter: clipboardRouter,
            feedback: SystemScreenshotFeedbackPresenter()
        )
    }

    init(
        permission: ScreenCapturePermissionProviding,
        session: ScreenshotSessionRunning,
        pasteboard: ScreenshotPasteboardWriting,
        panel: ScreenshotPanelControlling,
        clipboardRouter: ScreenshotClipboardRouting,
        feedback: ScreenshotFeedbackPresenting
    ) {
        self.permission = permission
        self.session = session
        self.pasteboard = pasteboard
        self.panel = panel
        self.clipboardRouter = clipboardRouter
        self.feedback = feedback
    }

    func capture() {
        guard !isCapturing, !isCheckingPermission else {
            NSLog("[screenshot] ignored duplicate ⌘J while capture is active")
            return
        }

        isCheckingPermission = true
        var authorized = permission.hasAccess()
        if !authorized, !requestedPermission {
            requestedPermission = true
            authorized = permission.requestAccess()
        }
        guard authorized else {
            lastResult = .permissionDenied
            NSLog("[screenshot] permission unavailable; requested=%d helpShown=%d", requestedPermission, showedPermissionHelp)
            if !showedPermissionHelp {
                showedPermissionHelp = true
                feedback.showPermissionDenied()
            }
            isCheckingPermission = false
            return
        }
        isCheckingPermission = false
        showedPermissionHelp = false

        isCapturing = true
        let shouldRestorePanel = panel?.isVisible == true
        let launch: () -> Void = { [weak self] in
            guard let self else { return }
            self.launchCapture(
                shouldRestorePanel: shouldRestorePanel
            )
        }

        if shouldRestorePanel {
            panel?.hide(completion: launch)
        } else {
            launch()
        }
    }

    func openPermissionSettings() {
        feedback.openPermissionSettings()
    }

    private func launchCapture(shouldRestorePanel: Bool) {
        session.run { [weak self] result in
            guard let self else { return }
            self.isCapturing = false
            switch result {
            case .success(.copied(let data)):
                // Reserve only the synchronous write, not the whole editing session.
                self.clipboardRouter?.prepareNextChange(origin: .explicitScreenshot)
                if self.pasteboard.writePNG(data) {
                    _ = self.clipboardRouter?.pollNow(origin: .explicitScreenshot)
                    self.lastResult = .captured
                } else {
                    self.clipboardRouter?.cancelPreparedChange(origin: .explicitScreenshot)
                    self.reportFailure(ScreenshotSessionError.clipboardWriteFailed, restorePanel: shouldRestorePanel)
                }
            case .success(.copiedText(let text)):
                if self.pasteboard.writeText(text) {
                    _ = self.clipboardRouter?.pollNow(origin: .explicitScreenshot)
                    self.lastResult = .copiedText
                } else {
                    self.reportFailure(ScreenshotSessionError.clipboardWriteFailed, restorePanel: shouldRestorePanel)
                }
            case .success(.presented):
                self.lastResult = .presented
            case .success(.saved):
                self.lastResult = .saved
            case .success(.cancelled):
                self.lastResult = .cancelledOrNonImage
                if shouldRestorePanel { self.panel?.show() }
            case .failure(let error):
                self.reportFailure(error, restorePanel: shouldRestorePanel)
            }
        }
    }

    private func reportFailure(_ error: Error, restorePanel: Bool) {
        lastResult = .launchFailed(error.localizedDescription)
        if restorePanel { panel?.show() }
        DiagnosticLog.failure("screenshot", error: error)
        feedback.showLaunchFailure(error.localizedDescription)
    }
}
