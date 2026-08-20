import AppKit
import CoreGraphics
import Foundation

enum ScreenshotResult: Equatable {
    case captured
    case cancelledOrNonImage
    case permissionDenied
    case launchFailed(String)
}

enum SystemScreenshotCommand {
    static let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    static let arguments = ["-i", "-U", "-c", "-d"]
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
protocol ScreenshotCommandRunning: AnyObject {
    func run(completion: @escaping (Result<Int32, Error>) -> Void)
}

private enum ScreenshotCommandError: LocalizedError {
    case alreadyRunning

    var errorDescription: String? {
        "A screenshot command is already running."
    }
}

@MainActor
final class ProcessScreenshotCommandRunner: ScreenshotCommandRunning {
    private var process: Process?

    func run(completion: @escaping (Result<Int32, Error>) -> Void) {
        guard process == nil else {
            completion(.failure(ScreenshotCommandError.alreadyRunning))
            return
        }

        let process = Process()
        process.executableURL = SystemScreenshotCommand.executableURL
        process.arguments = SystemScreenshotCommand.arguments
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                self?.process = nil
                completion(.success(status))
            }
        }
        self.process = process

        do {
            try process.run()
        } catch {
            self.process = nil
            completion(.failure(error))
        }
    }
}

@MainActor
protocol ScreenshotPasteboardReading {
    var changeCount: Int { get }
    var containsImage: Bool { get }
}

@MainActor
struct GeneralScreenshotPasteboard: ScreenshotPasteboardReading {
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    var containsImage: Bool {
        let pasteboard = NSPasteboard.general
        guard let type = pasteboard.availableType(from: [.png, .tiff]),
              let data = pasteboard.data(forType: type)
        else {
            return false
        }
        return !data.isEmpty
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
            zh: "请在系统设置的“隐私与安全性 → 屏幕与系统音频录制”中允许 Magpie，然后重新启动 Magpie 再试。",
            en: "Allow Magpie in System Settings → Privacy & Security → Screen & System Audio Recording, then restart Magpie and try again."
        )
        alert.addButton(withTitle: language.pick(zh: "打开系统设置", en: "Open System Settings"))
        alert.addButton(withTitle: language.pick(zh: "取消", en: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
              )
        else {
            return
        }
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
    private let commandRunner: ScreenshotCommandRunning
    private let pasteboard: ScreenshotPasteboardReading
    private weak var panel: ScreenshotPanelControlling?
    private weak var clipboardRouter: ScreenshotClipboardRouting?
    private let feedback: ScreenshotFeedbackPresenting

    private(set) var isCapturing = false
    private(set) var lastResult: ScreenshotResult?

    convenience init(
        panel: ScreenshotPanelControlling,
        clipboardRouter: ScreenshotClipboardRouting
    ) {
        self.init(
            permission: SystemScreenCapturePermission(),
            commandRunner: ProcessScreenshotCommandRunner(),
            pasteboard: GeneralScreenshotPasteboard(),
            panel: panel,
            clipboardRouter: clipboardRouter,
            feedback: SystemScreenshotFeedbackPresenter()
        )
    }

    init(
        permission: ScreenCapturePermissionProviding,
        commandRunner: ScreenshotCommandRunning,
        pasteboard: ScreenshotPasteboardReading,
        panel: ScreenshotPanelControlling,
        clipboardRouter: ScreenshotClipboardRouting,
        feedback: ScreenshotFeedbackPresenting
    ) {
        self.permission = permission
        self.commandRunner = commandRunner
        self.pasteboard = pasteboard
        self.panel = panel
        self.clipboardRouter = clipboardRouter
        self.feedback = feedback
    }

    func capture() {
        guard !isCapturing else {
            NSLog("[screenshot] ignored duplicate ⌘J while capture is active")
            return
        }

        guard permission.hasAccess() || permission.requestAccess() else {
            lastResult = .permissionDenied
            NSLog("[screenshot] screen capture permission denied")
            feedback.showPermissionDenied()
            return
        }

        isCapturing = true
        let pasteboardChangeCount = pasteboard.changeCount
        let shouldRestorePanel = panel?.isVisible == true
        let launch: () -> Void = { [weak self] in
            guard let self else { return }
            self.launchCapture(
                pasteboardChangeCount: pasteboardChangeCount,
                shouldRestorePanel: shouldRestorePanel
            )
        }

        if shouldRestorePanel {
            panel?.hide(completion: launch)
        } else {
            launch()
        }
    }

    private func launchCapture(pasteboardChangeCount: Int, shouldRestorePanel: Bool) {
        clipboardRouter?.prepareNextChange(origin: .explicitScreenshot)
        NSLog("[screenshot] launch %@ %@",
              SystemScreenshotCommand.executableURL.path,
              SystemScreenshotCommand.arguments.joined(separator: " "))

        commandRunner.run { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let terminationStatus):
                self.finishCapture(
                    pasteboardChangeCount: pasteboardChangeCount,
                    terminationStatus: terminationStatus,
                    shouldRestorePanel: shouldRestorePanel
                )
            case .failure(let error):
                self.clipboardRouter?.cancelPreparedChange(origin: .explicitScreenshot)
                self.lastResult = .launchFailed(error.localizedDescription)
                self.isCapturing = false
                if shouldRestorePanel {
                    self.panel?.show()
                }
                NSLog("[screenshot] launch failed: %@", error.localizedDescription)
                self.feedback.showLaunchFailure(error.localizedDescription)
            }
        }
    }

    private func finishCapture(
        pasteboardChangeCount: Int,
        terminationStatus: Int32,
        shouldRestorePanel: Bool
    ) {
        let capturedImage = pasteboard.changeCount != pasteboardChangeCount && pasteboard.containsImage
        isCapturing = false

        if capturedImage {
            _ = clipboardRouter?.pollNow(origin: .explicitScreenshot)
            lastResult = .captured
            NSLog("[screenshot] captured status=%d pasteboard=%d",
                  terminationStatus,
                  pasteboard.changeCount)
            return
        }

        clipboardRouter?.cancelPreparedChange(origin: .explicitScreenshot)
        lastResult = .cancelledOrNonImage
        if shouldRestorePanel {
            panel?.show()
        }
        NSLog("[screenshot] cancelled or non-image result status=%d", terminationStatus)
    }
}
