import AICore

/// The texts of the settings window, and the permission message that the error alert shares with it.
struct SettingsCopy {
    var title: String
    var login: String
    var retention: String
    var shortcuts: String
    var capture: String
    var repeatCapture: String
    var screen: String
    var screenAllowed: String
    var screenDenied: String
    var openSettings: String
    var loginApproval: String
    var loginError: String
    var days: (Int) -> String
    var remoteSection: String
    var remote: String
    var remoteExplanation: String
    var forgetRemotes: String
    var confirmedRemotes: (Int) -> String

    static func forLanguage(_ language: Language) -> SettingsCopy {
        switch language {
        case .en:
            SettingsCopy(
                title: "Settings", login: "Launch at login", retention: "Keep captures", shortcuts: "Shortcuts",
                capture: "Annotate area", repeatCapture: "Repeat last area", screen: "Screen recording",
                screenAllowed: "Allowed",
                screenDenied: "Screen recording is not allowed. Allow it in System Settings under Privacy & Security.",
                openSettings: "Open System Settings", loginApproval: "Approve in System Settings.",
                loginError: "Launch at login could not be changed.",
                days: { $0 == 1 ? "1 day" : "\($0) days" },
                remoteSection: "Other machines", remote: "Copy to remote machines",
                remoteExplanation: "When the front terminal is connected over SSH, the capture is copied to that machine, after you confirm it once.",
                forgetRemotes: "Forget confirmed machines",
                confirmedRemotes: { $0 == 0 ? "None confirmed" : $0 == 1 ? "1 machine confirmed" : "\($0) machines confirmed" }
            )
        case .de:
            SettingsCopy(
                title: "Einstellungen", login: "Beim Anmelden starten", retention: "Aufbewahrung", shortcuts: "Kurzbefehle",
                capture: "Bereich annotieren", repeatCapture: "Letzten Bereich wiederholen", screen: "Bildschirmaufnahme",
                screenAllowed: "Erlaubt",
                screenDenied: "Bildschirmaufnahme ist nicht erlaubt. Erlaube sie in den Systemeinstellungen unter Datenschutz & Sicherheit.",
                openSettings: "Systemeinstellungen öffnen", loginApproval: "In den Systemeinstellungen bestätigen.",
                loginError: "Anmeldung konnte nicht geändert werden.",
                days: { $0 == 1 ? "1 Tag" : "\($0) Tage" },
                remoteSection: "Andere Rechner", remote: "Auf entfernte Rechner kopieren",
                remoteExplanation: "Ist das vordere Terminal per SSH verbunden, wird die Aufnahme auf diesen Rechner kopiert, nachdem du ihn einmal bestätigt hast.",
                forgetRemotes: "Bestätigte Rechner vergessen",
                confirmedRemotes: { $0 == 0 ? "Keiner bestätigt" : $0 == 1 ? "1 Rechner bestätigt" : "\($0) Rechner bestätigt" }
            )
        }
    }
}
