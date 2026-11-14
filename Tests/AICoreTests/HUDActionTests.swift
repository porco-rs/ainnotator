import AICore
import Testing

@Test func hudActionsDuringNoteInput() {
    var state = CaptureState()
    state.mode = .annotate
    state.marks = [Mark(id: 1, kind: .box, intent: .change, note: "existing", x: 0.1, y: 0.1, w: 0.2, h: 0.2, x0: 0.1, y0: 0.1, x1: 0.3, y1: 0.3)]
    state.active = 1; state.noteMode = true
    _ = reduce(&state, .chooseIntent(.bug))
    #expect(state.intent == .bug && state.marks[0].intent == .bug && state.marks[0].note == "existing")
    _ = reduce(&state, .toggleHelp)
    #expect(state.help && state.marks[0].note == "existing")
    _ = reduce(&state, .chooseTool(.arrow))
    #expect(state.tool == .arrow && state.active == nil && !state.noteMode)
    #expect(reduce(&state, .copy) == [.finish])
    #expect(state.mode == .done)
}
