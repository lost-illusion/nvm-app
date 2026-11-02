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
}
