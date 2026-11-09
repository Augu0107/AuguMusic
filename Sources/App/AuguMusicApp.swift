import SwiftUI

@main
struct AuguMusicApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var library: LibraryStore
    @StateObject private var userData: UserDataStore
    @StateObject private var player: PlayerController
    @StateObject private var ui: UIState

    init() {
        Prefs.register()
        let settings = AppSettings()
        let library = LibraryStore(settings: settings)
        let userData = UserDataStore()
        let player = PlayerController(library: library, settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _library = StateObject(wrappedValue: library)
        _userData = StateObject(wrappedValue: userData)
        _player = StateObject(wrappedValue: player)
        _ui = StateObject(wrappedValue: UIState())
        UserDataStore.shared = userData
        // Caricati subito: se l'app viene aperta in background da un pulsante del widget, la coda è già pronta.
        library.loadFromDisk()
        userData.load()
        player.restore()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(library.progress)
                .environmentObject(userData)
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(ui)
                .preferredColorScheme(settings.theme.colorScheme)
                .tint(settings.accent.color)
                .task {
                    await library.autoScanIfEnabled()
                    player.libraryDidChange()
                }
        }
    }
}
