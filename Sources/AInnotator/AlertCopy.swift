import AICore

/// The texts of the error alerts. The permission message is the one of the settings window.
struct AlertCopy {
    var captureFailed: String
    var saveFailed: String
    var saveFailedImageKept: String
    var ok: String
    var shortcutTaken: ([String]) -> String

    static func forLanguage(_ language: Language) -> AlertCopy {
        switch language {
        case .en:
            AlertCopy(
                captureFailed: "The screen could not be captured. Try again.",
                saveFailed: "The capture could not be saved.",
                saveFailedImageKept: "The capture could not be saved. The image is still on the clipboard.",
                ok: "OK",
                shortcutTaken: { shortcuts in
                    shortcuts.count == 1
                        ? "The shortcut \(shortcuts[0]) is already in use. The action is still available from the menu."
                        : "The shortcuts \(shortcuts.joined(separator: " and ")) are already in use. The actions are still available from the menu."
                }
            )
        case .de:
            AlertCopy(
                captureFailed: "Der Bildschirm konnte nicht aufgenommen werden. Versuche es noch einmal.",
                saveFailed: "Die Aufnahme konnte nicht gespeichert werden.",
                saveFailedImageKept: "Die Aufnahme konnte nicht gespeichert werden. Das Bild liegt trotzdem in der Zwischenablage.",
                ok: "OK",
                shortcutTaken: { shortcuts in
                    "Der Kurzbefehl \(shortcuts.joined(separator: " und ")) ist bereits belegt. Die Aktion bleibt über das Menü verfügbar."
                }
            )
        }
    }
}
