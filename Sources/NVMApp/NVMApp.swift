import AppKit
import NVMCore
import SwiftUI

@main
struct NVMAppRoot: App {
    @State private var model = NVMModel(layout: NVMLayout.detect(
        override: UserDefaults.standard.string(forKey: "nvmDirOverride")))
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup("Node Versions") {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    // SwiftPM executables can start without frontmost focus.
                    if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
                    applyAppearance(appearance)
                    // Undocumented knob for README screenshots:
                    // NVM_APP_SHOT=<path> captures the window after data loads,
                    // writes a PNG, and exits.
                    if let shotPath = ProcessInfo.processInfo.environment["NVM_APP_SHOT"] {
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            Self.captureShot(to: shotPath)
                        }
                    }
                    // "Update versions" runs at launch: disk state first, then the
                    // remote catalog and the cached dist metadata in parallel.
                    Task {
                        model.refreshHookStatus()
                        await model.refresh()
                        if model.status == .ready {
                            await withTaskGroup(of: Void.self) { group in
                                group.addTask { await model.loadRemote() }
                                group.addTask { await model.prepareDistAtLaunch() }
                            }
                            await model.refreshExtras()
                            await model.refreshHealth()
                            await model.refreshAllPins()  // no-op unless folders are watched
                        }
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
            }
        }
    }

    @MainActor
    private static func captureShot(to path: String) {
        // Capture the whole window frame (incl. title bar) without needing
        // Screen Recording permission — cacheDisplay renders our own views.
        let window = NSApp.windows.first { $0.isVisible && $0.title.contains("Node Versions") }
            ?? NSApp.keyWindow
        guard let window,
              let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            NSApp.terminate(nil)
            return
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        NSApp.terminate(nil)
    }
}
