import SwiftUI
import AppIntents

@MainActor
@main
struct SanagControlApp: App {
    @StateObject private var bluetooth = B21SBluetoothManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        bluetooth.applicationDidBecomeActive()
                    } else if newPhase == .background {
                        bluetooth.applicationDidEnterBackground()
                    }
                }
        }
    }
}


/// Disponibile nell'app Comandi Rapidi: esegue una breve sessione BLE
/// senza dover mostrare l'interfaccia di Sanag Control.
struct RipristinaEQB21SIntent: AppIntent {
    static var title: LocalizedStringResource = "Ripristina EQ B21S"
    static var description = IntentDescription("Riconnette le B21S e applica il preset EQ salvato.")
    static var openAppWhenRun: Bool { false }

    // API moderna: il sistema è autorizzato a eseguire l'azione senza UI.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    // Nessun dialogo o errore presentato all'utente: automazione silenziosa.
    // Anche un eventuale fallimento resta visibile nel log B21S.Events.
    func perform() async throws -> some IntentResult {
        _ = await B21SBluetoothManager.shared.applySavedPresetFromShortcut()
        return .result()
    }
}

struct SanagControlShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RipristinaEQB21SIntent(),
            phrases: ["Ripristina EQ con \(.applicationName)", "Applica il preset con \(.applicationName)"],
            shortTitle: "Ripristina EQ B21S",
            systemImageName: "headphones"
        )
    }
}
