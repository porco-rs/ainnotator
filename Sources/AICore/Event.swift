public enum Key: Equatable, Sendable {
    case enter, escape, tab, backspace, delete, left, right, up, down
    /// A command character resolved through the keyboard layout, so ⌘Z and ? work on QWERTZ. Lower case.
    case character(String)
}

public struct KeyInput: Equatable, Sendable {
    public var key: Key
    public var shift: Bool
    public var command: Bool

    public init(key: Key, shift: Bool = false, command: Bool = false) {
        self.key = key
        self.shift = shift
        self.command = command
    }
}

public enum Event: Equatable, Sendable {
    /// ⌥⇧A: start selecting on this stage.
    case begin(Stage)
    /// ⌥⇧R: repeat the last area on this stage.
    case repeatLast(Stage)
    /// The pointer moved to another display while selecting.
    case setStage(Stage)
    case chooseIntent(Intent)
    case chooseTool(Tool)
    case toggleHelp
    case copy
    case pointerDown(NormPoint)
    case pointerMoved(NormPoint, inside: Bool)
    case pointerUp
    case pointerLeft
    case key(KeyInput)
    /// Finished text from the input method. In note mode it extends the note, otherwise it is a tool or intent key.
    case insertText(String)
    /// Reply to `Effect.pickWindow`: the area of the window under the pointer.
    case selectWindow(NormRect)
}
