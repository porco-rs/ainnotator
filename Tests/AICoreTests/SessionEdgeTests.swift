import AICore
import Testing

private let stage = Stage(pixelWidth: 2000, pixelHeight: 1000, pointWidth: 1000, pointHeight: 500)
private let enter = KeyInput(key: .enter)

private func annotating(tool: Tool = .box) -> CaptureState {
    var state = CaptureState()
    _ = reduce(&state, .begin(stage))
    _ = reduce(&state, .pointerDown(NormPoint(x: 0.1, y: 0.1)))
    _ = reduce(&state, .pointerMoved(NormPoint(x: 0.9, y: 0.9), inside: true))
    _ = reduce(&state, .pointerUp)
    state.tool = tool
    return state
}

/// The user sees the gesture, so it counts. Dropping it would put the pixels under a visible redaction into the output.
@Test func aRedactionStillBeingDraggedIsPartOfTheResult() {
    var state = annotating(tool: .redact)
    _ = reduce(&state, .pointerDown(NormPoint(x: 0.2, y: 0.2)))
    _ = reduce(&state, .pointerMoved(NormPoint(x: 0.5, y: 0.5), inside: true))
    let effects = reduce(&state, .key(KeyInput(key: .character("c"), command: true)))
    #expect(effects == [.finish])
    #expect(state.mode == .done)
    #expect(state.marks.filter { $0.kind == .redact }.count == 1)
}

@Test func enterEndsARunningGestureWithoutFinishingAndKeepsARedaction() {
    var state = annotating(tool: .redact)
    _ = reduce(&state, .pointerDown(NormPoint(x: 0.2, y: 0.2)))
    _ = reduce(&state, .pointerMoved(NormPoint(x: 0.5, y: 0.5), inside: true))
    #expect(reduce(&state, .key(enter)).isEmpty)
    #expect(state.mode == .annotate)
    #expect(state.drag == nil)
    #expect(state.marks.filter { $0.kind == .redact }.count == 1)
    #expect(reduce(&state, .key(enter)) == [.finish])
}

/// The intended flow: note, ⏎, next mark, note, ⏎, ⏎ and done. There is no time window.
@Test func enterLeavesTheNoteAndOnlyTheNextOneFinishes() {
    var state = annotating()
    for (index, note) in ["circle", "arrow"].enumerated() {
        let start = 0.1 + Double(index) * 0.3
        _ = reduce(&state, .pointerDown(NormPoint(x: start, y: 0.2)))
        _ = reduce(&state, .pointerMoved(NormPoint(x: start + 0.2, y: 0.5), inside: true))
        _ = reduce(&state, .pointerUp)
        #expect(state.noteMode)
        _ = reduce(&state, .insertText(note))
        #expect(reduce(&state, .key(enter)).isEmpty)
        #expect(state.mode == .annotate && state.active == nil && !state.noteMode)
    }
    #expect(state.marks.map(\.note) == ["circle", "arrow"])
    #expect(reduce(&state, .key(enter)) == [.finish])
    #expect(state.mode == .done)
}

@Test func enterAfterANoteStartsANewUndoStepForTheNextTyping() {
    var state = annotating()
    _ = reduce(&state, .pointerDown(NormPoint(x: 0.2, y: 0.2)))
    _ = reduce(&state, .pointerMoved(NormPoint(x: 0.5, y: 0.5), inside: true))
    _ = reduce(&state, .pointerUp)
    _ = reduce(&state, .insertText("one"))
    _ = reduce(&state, .key(enter))
    #expect(state.typingID == nil)
}

@Test func enterDeselectsASelectedMarkBeforeItFinishes() {
    var state = annotating()
    _ = reduce(&state, .pointerDown(NormPoint(x: 0.2, y: 0.2)))
    _ = reduce(&state, .pointerMoved(NormPoint(x: 0.5, y: 0.5), inside: true))
    _ = reduce(&state, .pointerUp)
    state.noteMode = false
    #expect(state.active != nil)
    #expect(reduce(&state, .key(enter)).isEmpty)
    #expect(state.active == nil)
    #expect(reduce(&state, .key(enter)) == [.finish])
}

@Test func enterClosesTheOverviewBeforeItFinishes() {
    var state = annotating()
    _ = reduce(&state, .toggleHelp)
    #expect(reduce(&state, .key(enter)).isEmpty)
    #expect(!state.help)
    #expect(state.mode == .annotate)
    #expect(reduce(&state, .key(enter)) == [.finish])
}

@Test func commandCAndTheButtonFinishFromInsideANote() {
    for event in [Event.key(KeyInput(key: .character("c"), command: true)), Event.copy] {
        var state = annotating()
        _ = reduce(&state, .pointerDown(NormPoint(x: 0.2, y: 0.2)))
        _ = reduce(&state, .pointerMoved(NormPoint(x: 0.5, y: 0.5), inside: true))
        _ = reduce(&state, .pointerUp)
        _ = reduce(&state, .insertText("note"))
        #expect(state.noteMode)
        #expect(reduce(&state, event) == [.finish])
        #expect(state.mode == .done)
    }
}

@Test func theRepeatKeyWorksRightAfterACapture() {
    var state = annotating()
    let area = state.lastSel
    _ = reduce(&state, .key(KeyInput(key: .enter)))
    #expect(state.mode == .done)
    _ = reduce(&state, .repeatLast(stage))
    #expect(state.mode == .annotate)
    #expect(state.sel == area)
}
