import AICore
import CoreGraphics

/// Every string of the overlay in one language: HUD, hints, shortcut overview and accessibility names.
struct OverlayCopy: Sendable {
    /// Header of the HUD while selecting an area, annotating, typing a note and with a mark selected.
    var modeArea: String, modeAnnotate: String, modeNote: String, modeSelected: String
    /// Intent names in the HUD, in `Intent.allCases` order.
    var intents: [String]
    /// The same names for note chips and accessibility, in `Intent.allCases` order.
    var intentNames: [String]
    /// In `Tool.allCases` order.
    var toolNames: [String]
    var toolbar: String, shortcuts: String, copy: String
    /// The help button while choosing the area. There it stands next to the mode name, where a bare question mark
    /// read like a question about that name.
    var helpButton: String
    /// Unit behind the number of marks in the readout.
    var marksUnit: String
    /// Placeholder behind the intent while a note is empty.
    var typeNote: String
    var markLabel: String
    var selectHint: [(String, String)], markHint: [(String, String)], noteHint: [(String, String)]
    var selectedHint: [(String, String)], cropHint: [(String, String)]
    /// The sixteen rows of the shortcut overview.
    var help: [(String, String)]
    /// Row heights of the two-column overview; a row is taller where one of its descriptions wraps.
    var helpRowHeights: [CGFloat]

    func markName(number: Int, intent: Intent, note: String) -> String {
        "\(markLabel) \(number), \(intentNames[intent.rawValue - 1]), \(note)"
    }

    static func forLanguage(_ language: Language) -> OverlayCopy {
        language == .de ? german : english
    }

    private static let english = OverlayCopy(
        modeArea: "SELECT AREA", modeAnnotate: "ANNOTATE", modeNote: "NOTE", modeSelected: "SELECTED",
        intents: ["BUG", "CHANGE", "KEEP", "QUESTION"],
        intentNames: ["Bug", "Change", "Keep", "Question"],
        toolNames: ["Box", "Oval", "Arrow", "Highlight", "Redact", "Crop"],
        toolbar: "Annotate", shortcuts: "Keyboard shortcuts", copy: "Copy", helpButton: "? Help",
        marksUnit: "MARKS", typeNote: "Type a note", markLabel: "Mark",
        selectHint: [("DRAG", "Area"), ("SPACE", "Window"), ("R", "Last"), ("ESC", "Cancel")],
        markHint: [("CLICK", "Number"), ("DRAG", "Shape"), ("⌘Z", "Undo"), ("⏎", "Copy")],
        noteHint: [("1–4", "Intent"), ("TAB", "Next"), ("⏎", "Done"), ("⏎⏎", "Copy")],
        selectedHint: [("←→", "Move"), ("⌫", "Delete"), ("TAB", "Note"), ("⌘Z", "Undo")],
        cropHint: [("DRAG", "New crop"), ("ESC", "Cancel")],
        help: [
            ("⌥⇧A", "Capture"), ("⌥⇧R", "Repeat last area"), ("Space", "Whole window"), ("Click", "Place a number"),
            ("Drag", "Active tool"), ("B · O · A", "Box · Oval · Arrow"), ("H · X · C", "Highlight · Redact · Crop"),
            ("1 2 3 4", "Bug · Change · Keep · Question"), ("Click on edge", "Select & move"), ("← ↑ ↓ →", "Move · ⇧ ×10"),
            ("⌫", "Delete selection"), ("Tab · ⇧Tab", "Next · previous note"), ("⌘Z · ⇧⌘Z", "Undo · Redo"),
            ("⏎ · ⌘C", "Finish note, then copy · copy now"), ("Esc", "Leave note · cancel"), ("?", "This overview"),
        ],
        helpRowHeights: [28, 28, 28, 43, 28, 28, 43, 28]
    )

    private static let german = OverlayCopy(
        modeArea: "BEREICH WÄHLEN", modeAnnotate: "MARKIEREN", modeNote: "NOTIZ", modeSelected: "AUSWAHL",
        intents: ["BUG", "ÄNDERN", "BEHALTEN", "FRAGE"],
        intentNames: ["Bug", "Ändern", "Behalten", "Frage"],
        toolNames: ["Box", "Kreis", "Pfeil", "Textmarker", "Schwärzen", "Zuschneiden"],
        toolbar: "Annotieren", shortcuts: "Tastenkürzel", copy: "Kopieren", helpButton: "? Hilfe",
        marksUnit: "MK", typeNote: "Notiz tippen", markLabel: "Markierung",
        selectHint: [("ZIEHEN", "Bereich"), ("SPACE", "Fenster"), ("R", "Letzter"), ("ESC", "Abbrechen")],
        markHint: [("KLICK", "Nummer"), ("ZIEHEN", "Form"), ("⌘Z", "Zurück"), ("⏎", "Kopieren")],
        noteHint: [("1–4", "Absicht"), ("TAB", "Nächste"), ("⏎", "Fertig"), ("⏎⏎", "Kopieren")],
        selectedHint: [("←→", "Verschieben"), ("⌫", "Löschen"), ("TAB", "Notiz"), ("⌘Z", "Zurück")],
        cropHint: [("ZIEHEN", "Neuer Ausschnitt"), ("ESC", "Abbrechen")],
        help: [
            ("⌥⇧A", "Aufnehmen"), ("⌥⇧R", "Letzten Bereich wiederholen"), ("Space", "Ganzes Fenster"), ("Klick", "Nummer setzen"),
            ("Ziehen", "Aktives Werkzeug"), ("B · O · A", "Box · Kreis · Pfeil"), ("H · X · C", "Textmarker · Schwärzen · Zuschneiden"),
            ("1 2 3 4", "Bug · Ändern · Behalten · Frage"), ("Klick auf Rand", "Auswählen & verschieben"), ("← ↑ ↓ →", "Verschieben · ⇧ ×10"),
            ("⌫", "Auswahl löschen"), ("Tab · ⇧Tab", "Nächste · vorige Notiz"), ("⌘Z · ⇧⌘Z", "Rückgängig · Wiederherstellen"),
            ("⏎ · ⌘C", "Notiz beenden, dann kopieren · sofort"), ("Esc", "Notiz verlassen · abbrechen"), ("?", "Diese Übersicht"),
        ],
        helpRowHeights: [43, 28, 28, 43, 28, 28, 43, 43]
    )
}
