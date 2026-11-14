/// What the shell has to do after a reducer step. The reducer itself never touches the system.
public enum Effect: Equatable, Sendable {
    /// Close the overlay and produce no output (Esc).
    case cancel
    /// Close the overlay at once and deliver the output (⏎, ⌘C).
    case finish
    /// Close the receipt (Esc or ⏎ while it shows).
    case dismissReceipt
    /// Space while choosing the area: find the window under this point and answer with `Event.selectWindow`.
    case pickWindow(NormPoint)
}
