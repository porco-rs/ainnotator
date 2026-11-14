import Foundation
import Testing
@testable import AICore

private let stage = Stage(pixelWidth: 2576, pixelHeight: 1276, pointWidth: 1288, pointHeight: 638)
private func rectMark(_ id: Int, _ kind: MarkKind, _ intent: Intent, _ note: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Mark {
    Mark(id: id, kind: kind, intent: intent, note: note, x: x, y: y, w: w, h: h, x0: x, y0: y, x1: x+w, y1: y+h)
}
private func standard() -> CaptureState {
    var s = CaptureState(); s.mode = .annotate; s.stage = stage
    s.sel = NormRect(x: 0.07, y: 0.03, w: 0.70, h: 0.93); s.lastSel = s.sel
    s.marks = [rectMark(1, .box, .change, "Apply next to the field", 0.28, 0.536, 0.39, 0.226), rectMark(2, .oval, .question, "Real stock?", 0.614, 0.386, 0.064, 0.13), Mark(id: 3, kind: .arrow, intent: .bug, note: "Should be $46.35", x: 0.72, y: 0.58, w: 0, h: 0, x0: 0.72, y0: 0.58, x1: 0.668, y1: 0.49), rectMark(4, .redact, .change, "", 0.716, 0.03, 0.034, 0.05)]
    s.nextID = 5; return s
}
private func key(_ s: inout CaptureState, _ key: Key, shift: Bool = false, command: Bool = false) -> [Effect] { reduce(&s, .key(KeyInput(key: key, shift: shift, command: command))) }
private func gesture(_ s: inout CaptureState, _ a: NormPoint, _ b: NormPoint) {
    _ = reduce(&s, .pointerDown(a)); _ = reduce(&s, .pointerMoved(b, inside: true)); _ = reduce(&s, .pointerUp)
}
private func fixture(_ name: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent("Fixtures/\(name)"), encoding: .utf8)
}
/// The JSON beside the PNG is the contract with whatever reads it: byte for byte, with the address stripped of its query and fragment.
@Test func outputMatchesFixture() throws {
    let s = standard(), context = CaptureContext(app: "Browser", window: "Checkout", url: "https://tinyplant.example/checkout?session=abc#top", repo: "tiny-plant", branch: "main")
    let path = "~/.ainnotator/2026-11-14_1012.png"
    let date = ISO8601DateFormatter().date(from: "2026-11-14T10:12:41+01:00")!
    #expect(Payload.json(s, imagePath: path, context: context, createdAt: date, timeZone: TimeZone(secondsFromGMT: 3600)!) == (try fixture("output.example.json")))
}
@Test(arguments: [Mode.select, .annotate, .done, .idle]) func beginRestarts(mode: Mode) {
    var s = standard(); s.mode = mode; s.active = 1; s.noteMode = true
    _ = reduce(&s, .begin(stage)); #expect(s.mode == .select); #expect(s.marks.isEmpty); #expect(s.lastSel != nil)
}
@Test(arguments: [0, 1, 2, 3]) func repeatOnlyAllowedModes(mode: Int) {
    var s = standard()
    if mode == 0 { s.mode = .select }; if mode == 2 { s.active = 1; s.noteMode = true }; if mode == 3 { s.active = 1 }
    _ = reduce(&s, .repeatLast(stage))
    #expect(s.marks.count == (mode < 2 ? 0 : 4))
}
@Test func selectionAndWindow() {
    var s = CaptureState(); _ = reduce(&s, .begin(stage)); _ = reduce(&s, .pointerMoved(NormPoint(x: 0.2, y: 0.3), inside: true))
    #expect(reduce(&s, .insertText(" ")) == [.pickWindow(NormPoint(x: 0.2, y: 0.3))])
    let r = NormRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4); _ = reduce(&s, .selectWindow(r)); #expect(s.sel == r); #expect(s.mode == .annotate)
    _ = reduce(&s, .begin(stage)); _ = reduce(&s, .insertText("r")); #expect(s.sel == r)
    _ = reduce(&s, .begin(stage)); gesture(&s, .init(x: 0.4, y: 0.4), .init(x: 0.4, y: 0.4)); #expect(s.sel == .full)
    _ = reduce(&s, .begin(stage)); gesture(&s, .init(x: 0.8, y: 0.9), .init(x: 0.2, y: 0.3)); #expect(abs(s.sel!.w - 0.6) < 0.000001)
    _ = reduce(&s, .begin(stage)); _ = reduce(&s, .insertText("?")); #expect(s.help); #expect(key(&s, .escape) == [.cancel])
}
@Test(arguments: [Tool.box, .oval, .arrow, .highlight, .redact, .crop]) func clickMakesPin(tool: Tool) {
    var s = standard(); s.marks = []; s.tool = tool
    gesture(&s, .init(x: 0.5, y: 0.5), .init(x: 0.5, y: 0.5)); #expect(s.marks.first?.kind == .pin); #expect(s.noteMode)
}
@Test(arguments: [("b", Tool.box), ("o", .oval), ("a", .arrow), ("h", .highlight), ("x", .redact), ("c", .crop)]) func toolsAndNoteInput(pair: (String, Tool)) {
    var s = standard(); s.active = 1
    _ = reduce(&s, .insertText(pair.0)); #expect(s.tool == pair.1); #expect(s.active == nil)
    s.active = 1; s.noteMode = true; let previous = s.marks[0].note
    _ = reduce(&s, .insertText(pair.0)); #expect(s.marks[0].note == previous + pair.0)
}
@Test func drawingAndHit() {
    var s = standard(); s.marks = []; s.tool = .oval
    gesture(&s, .init(x: 0.1, y: 0.2), .init(x: 0.3, y: 0.4)); #expect(s.marks.first?.kind == .oval); #expect(s.noteMode)
    _ = key(&s, .escape); gesture(&s, .init(x: 0.1, y: 0.3), .init(x: 0.1, y: 0.3)); #expect(s.active == 5); #expect(s.noteMode)
    gesture(&s, .init(x: 0.1, y: 0.3), .init(x: 0.2, y: 0.3)); #expect(!s.noteMode); #expect(abs(s.marks[0].x - 0.2) < 0.000001)
    _ = key(&s, .character("z"), command: true); #expect(abs(s.marks[0].x - 0.1) < 0.000001)
}
@Test func intentAndText() {
    var s = standard(); s.active = 1; s.noteMode = true; s.marks[0].note = ""
    _ = reduce(&s, .insertText("4")); #expect(s.marks[0].intent == .question); #expect(s.marks[0].note == "")
    _ = reduce(&s, .insertText("2abc ?")); #expect(s.marks[0].note == "2abc ?")
    _ = reduce(&s, .insertText(String(repeating: "ä", count: 200))); #expect(s.marks[0].note.count == 140)
    _ = key(&s, .backspace); #expect(s.marks[0].note.count == 139)
    _ = key(&s, .character("z"), command: true); #expect(s.marks[0].note == "")
    _ = key(&s, .character("z"), shift: true, command: true); #expect(s.marks[0].note.count == 139)
    _ = key(&s, .character("y"), command: true); #expect(s.marks[0].note.count == 139)
    s.active = nil; s.noteMode = false; _ = reduce(&s, .insertText("1")); #expect(s.intent == .bug)
    s.active = 2; _ = reduce(&s, .insertText("3")); #expect(s.marks[1].intent == .keep)
}
@Test func tabAndArrows() {
    var s = standard(); _ = key(&s, .tab, shift: true); #expect(s.active == 3); #expect(s.noteMode)
    _ = key(&s, .tab); #expect(s.active == 1)
    let x = s.marks[0].x; _ = key(&s, .left); #expect(s.marks[0].x == x)
    s.noteMode = false; _ = key(&s, .right); #expect(abs(s.marks[0].x - x - 1 / stage.pointWidth) < 1e-10)
    _ = key(&s, .down, shift: true); #expect(abs(s.marks[0].y - 0.536 - 10 / stage.pointHeight) < 1e-10)
    _ = key(&s, .character("z"), command: true); #expect(s.marks[0].y == 0.536)
}
@Test func cropUndoAndRenumber() throws {
    var s = standard(); let before = s
    s.tool = .crop; gesture(&s, .init(x: 0.25, y: 0.5), .init(x: 0.5, y: 0.8))
    #expect(s.tool == .box); #expect(s.marks.map(\.id) == [1]); #expect(s.sel != before.sel)
    _ = key(&s, .character("z"), command: true); #expect(s.sel == before.sel); #expect(s.marks == before.marks)
    s.active = 1; _ = key(&s, .backspace)
    let json = Payload.json(s, imagePath: "x", context: .init(), createdAt: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let marks = try #require(object["marks"] as? [[String: Any]])
    #expect(marks.map { $0["n"] as? Int } == [1, 2]); #expect(marks.map { $0["intent"] as? String } == ["question", "bug"])
    _ = key(&s, .character("z"), command: true); #expect(s.marks == before.marks)
}
@Test func finishCancelAndReceipt() {
    var s = standard(); #expect(key(&s, .enter) == [.finish]); #expect(s.mode == .done)
    #expect(key(&s, .escape) == [.dismissReceipt]); #expect(s.mode == .idle)
    s = standard(); s.active = 1; s.noteMode = true; _ = key(&s, .escape); #expect(s.active == nil); #expect(s.mode == .annotate)
    _ = reduce(&s, .insertText("?")); #expect(s.help); _ = key(&s, .escape); #expect(!s.help)
    #expect(key(&s, .escape) == [.cancel]); #expect(s.mode == .idle)
    s = standard(); #expect(key(&s, .character("c"), command: true) == [.finish])
}
@Test func emptyAndEscapedOutput() throws {
    var s = CaptureState(); s.stage = stage; s.sel = .full
    let json = Payload.json(s, imagePath: "x\"\n", context: .init(), createdAt: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(object["image"] as? String == "x\"\n"); #expect((object["context"] as? [String: String])?.isEmpty == true)
}

private func inMode(_ mode: Int) -> CaptureState {
    var s = standard()
    if mode == 0 { s.mode = .select; s.active = nil; s.noteMode = false }
    if mode == 2 { s.active = 1; s.noteMode = true }
    if mode == 3 { s.active = 1; s.noteMode = false }
    return s
}
@Test(arguments: [0, 1, 2, 3]) func modeTextCommands(mode: Int) {
    var s = inMode(mode); let old = s
    _ = reduce(&s, .insertText(" "))
    if mode == 2 { #expect(s.marks[0].note == old.marks[0].note + " ") }
    else { #expect(s.marks == old.marks) }
    s = inMode(mode); _ = reduce(&s, .insertText("r"))
    if mode == 0 { #expect(s.mode == .annotate); #expect(s.sel == s.lastSel) }
    else if mode == 2 { #expect(s.marks[0].note.hasSuffix("r")) }
    else { #expect(s == inMode(mode)) }
    s = inMode(mode); _ = reduce(&s, .insertText("?"))
    if mode == 2 { #expect(s.marks[0].note.hasSuffix("?")); #expect(!s.help) }
    else { #expect(s.help) }
    s = inMode(mode); _ = reduce(&s, .insertText("1"))
    if mode == 0 { #expect(s == inMode(mode)) }
    else if mode == 2 { #expect(s.marks[0].note.hasSuffix("1")) }
    else if mode == 3 { #expect(s.marks[0].intent == .bug) }
    else { #expect(s.intent == .bug) }
}
@Test(arguments: [0, 1, 2, 3]) func modeNavigationAndActions(mode: Int) {
    var s = inMode(mode); _ = key(&s, .tab)
    if mode == 0 { #expect(s == inMode(mode)) } else { #expect(s.noteMode); #expect(s.active == (mode == 1 ? 1 : 2)) }
    s = inMode(mode); _ = key(&s, .tab, shift: true)
    if mode == 0 { #expect(s == inMode(mode)) } else { #expect(s.noteMode); #expect(s.active == 3) }
    s = inMode(mode); let effect = key(&s, .enter)
    if mode == 0 { #expect(effect.isEmpty); #expect(s.mode == .select) }
    else if mode == 1 { #expect(effect == [.finish]); #expect(s.mode == .done) }
    else { #expect(effect.isEmpty); #expect(s.mode == .annotate); #expect(s.active == nil); #expect(!s.noteMode) }
    s = inMode(mode); let copy = key(&s, .character("c"), command: true)
    #expect(copy == (mode == 0 ? [] : [.finish]))
    s = inMode(mode); let esc = key(&s, .escape)
    if mode < 2 { #expect(esc == [.cancel]); #expect(s.mode == .idle) }
    else { #expect(esc.isEmpty); #expect(s.active == nil); #expect(!s.noteMode) }
    s = inMode(mode); _ = key(&s, .backspace)
    if mode == 2 { #expect(s.marks[0].note == String(inMode(mode).marks[0].note.dropLast())) }
    else if mode == 3 { #expect(s.marks.map(\.id) == [2,3,4]) }
    else { #expect(s.marks == inMode(mode).marks) }
}
@Test(arguments: [0, 1, 2, 3]) func modePointerGestures(mode: Int) {
    var s = inMode(mode)
    gesture(&s, .init(x: 0.1, y: 0.1), .init(x: 0.2, y: 0.2))
    if mode == 0 { #expect(s.mode == .annotate); #expect(abs(s.sel!.x - 0.1) < 1e-9) }
    else { #expect(s.marks.count == 5); #expect(s.marks.last?.kind == .box); #expect(s.noteMode) }
    s = inMode(mode); gesture(&s, .init(x: 0.1, y: 0.1), .init(x: 0.1, y: 0.1))
    if mode == 0 { #expect(s.sel == .full) } else { #expect(s.marks.last?.kind == .pin) }
    if mode != 0 {
        s = inMode(mode); gesture(&s, .init(x: 0.28, y: 0.6), .init(x: 0.28, y: 0.6)); #expect(s.active == 1); #expect(s.noteMode)
        s = inMode(mode); gesture(&s, .init(x: 0.28, y: 0.6), .init(x: 0.3, y: 0.6)); #expect(s.active == 1); #expect(!s.noteMode); #expect(abs(s.marks[0].x - 0.3) < 1e-9)
    }
}
@Test(arguments: [Key.left, .right, .up, .down]) func arrowDirections(arrow: Key) {
    for mode in 0...3 {
        var s = inMode(mode); let old = s.marks; _ = key(&s, arrow, shift: true)
        if mode == 3 {
            let mark = s.marks[0], original = old[0]
            switch arrow {
            case .left: #expect(abs(mark.x - original.x + 10 / stage.pointWidth) < 1e-10)
            case .right: #expect(abs(mark.x - original.x - 10 / stage.pointWidth) < 1e-10)
            case .up: #expect(abs(mark.y - original.y + 10 / stage.pointHeight) < 1e-10)
            case .down: #expect(abs(mark.y - original.y - 10 / stage.pointHeight) < 1e-10)
            default: Issue.record("Unexpected arrow")
            }
        } else { #expect(s.marks == old) }
    }
}
@Test func historyAndClippedArrows() {
    var s = standard(); s.active = 1
    for _ in 0..<105 { _ = key(&s, .right) }
    #expect(s.past.count == 100)
    _ = key(&s, .character("z"), command: true); #expect(s.future.count == 1)
    _ = reduce(&s, .insertText("b")); gesture(&s, .init(x: 0.1, y: 0.1), .init(x: 0.2, y: 0.2)); #expect(s.future.isEmpty)
    s = standard(); s.tool = .crop
    gesture(&s, .init(x: 0.69, y: 0.5), .init(x: 0.7, y: 0.55))
    #expect(s.marks.contains { $0.id == 3 }); #expect(!s.marks.contains { $0.id == 1 })
    _ = key(&s, .character("z"), command: true); #expect(s.marks == standard().marks)
}
@Test func pureGeometry() {
    let badges = Geometry.spread([.init(x: 0.1, y: 0.1), .init(x: 0.1, y: 0.1)], width: 100, height: 100, step: 20)
    #expect(badges[0].x == 0.1); #expect(badges[1].x == 0.3)
    #expect(Geometry.tokenEstimate(width: 1803, height: 1187) == "≈2.2k tok")
}

@Test(arguments: [0, 1, 2, 3]) func undoRedoInEveryMode(mode: Int) {
    var s = inMode(mode)
    if mode == 0 {
        let before = s
        _ = key(&s, .character("z"), command: true); _ = key(&s, .character("z"), shift: true, command: true)
        #expect(s == before)
        return
    }
    if mode == 1 {
        gesture(&s, .init(x: 0.1, y: 0.1), .init(x: 0.2, y: 0.2)); s.active = nil; s.noteMode = false
    } else if mode == 2 { _ = reduce(&s, .insertText("abc")) }
    else { _ = key(&s, .right) }
    let after = s.marks
    _ = key(&s, .character("z"), command: true); #expect(s.marks != after)
    _ = key(&s, .character("z"), shift: true, command: true); #expect(s.marks == after)
}
@Test(arguments: [0, 1, 2, 3]) func toolsInEveryMode(mode: Int) {
    let pairs: [(String, Tool)] = [("b", .box), ("o", .oval), ("a", .arrow), ("h", .highlight), ("x", .redact), ("c", .crop)]
    for (letter, tool) in pairs {
        var s = inMode(mode); s.tool = .arrow; let before = s
        _ = reduce(&s, .insertText(letter))
        if mode == 0 { #expect(s == before) }
        else if mode == 2 { #expect(s.marks[0].note == before.marks[0].note + letter); #expect(s.tool == .arrow) }
        else { #expect(s.tool == tool); #expect(s.active == nil) }
    }
}
@Test(arguments: [1, 2, 3, 4]) func everyIntent(digit: Int) {
    for mode in 0...3 {
        var s = inMode(mode)
        if mode == 2 { s.marks[0].note = "" }
        _ = reduce(&s, .insertText(String(digit)))
        if mode == 0 { #expect(s.intent == .change) }
        else if mode == 1 { #expect(s.intent == Intent(rawValue: digit)) }
        else { #expect(s.marks[0].intent == Intent(rawValue: digit)); #expect(s.marks[0].note == (mode == 2 ? "" : standard().marks[0].note)) }
    }
}
@Test func redactionAndReceiptControls() {
    var s = standard(); s.marks = []; s.tool = .redact
    gesture(&s, .init(x: 0.1, y: 0.1), .init(x: 0.3, y: 0.3))
    #expect(s.marks.first?.kind == .redact); #expect(s.active == nil); #expect(!s.noteMode)
    s.mode = .done
    #expect(key(&s, .enter) == [.dismissReceipt]); #expect(s.mode == .idle)
}
