import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var model = JarvisAppModel()

    var body: some Scene {
        MenuBarExtra {
            JarvisMenuView(model: model)
                .onAppear {
                    if !model.isEnabled {
                        model.start()
                    }
                }
        } label: {
            StatusBarMonsterEyeIcon(status: model.status)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
