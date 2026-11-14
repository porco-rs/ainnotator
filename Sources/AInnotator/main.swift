import AICore
import AIRender
import AppKit

// Decided once here and passed down: the bundle only reports a language it ships a localization for.
let launchLanguage = Language.choose(from: Bundle.main.preferredLocalizations)

Theme.monoProvider = { size, weight in
    let appKitWeight: NSFont.Weight = switch weight {
    case .regular: .regular
    case .medium: .medium
    case .semibold: .semibold
    }
    return NSFont.monospacedSystemFont(ofSize: size, weight: appKitWeight) as CTFont
}

// Developer commands begin with `--`. Any other argument, such as the `-NSDocumentRevisionsDebugMode YES` Xcode passes,
// starts the app as usual.
let arguments = CommandLine.arguments
let isDeveloperCommand = arguments.dropFirst().first?.hasPrefix("--") == true
if isDeveloperCommand {
    // The offscreen self-test needs no window server, so it also runs where none is available.
    _ = DevCommands.run(arguments: arguments, language: launchLanguage)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = isDeveloperCommand ? nil : AppController(language: launchLanguage)
app.delegate = controller
app.run()
