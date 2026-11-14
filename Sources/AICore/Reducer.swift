import Foundation

/// Applies an input without performing platform work.
public func reduce(_ state: inout CaptureState, _ event: Event) -> [Effect] {
    switch event {
    case .begin(let stage):
        let last = state.lastSel, intent = state.intent
        state = CaptureState(); state.stage = stage; state.lastSel = last; state.intent = intent; state.mode = .select
    case .repeatLast(let stage):
        guard (state.mode == .idle || state.mode == .done || (state.mode == .select || (state.mode == .annotate && state.active == nil && !state.noteMode))), let sel = state.lastSel else { break }
        let intent = state.intent
        state = CaptureState(); state.stage = stage; state.lastSel = sel; state.sel = sel; state.intent = intent; state.mode = .annotate
    case .setStage(let stage):
        if state.mode == .select { state.stage = stage }
    case .selectWindow(let rect):
        if state.mode == .select { state.sel = rect; state.lastSel = rect; state.mode = .annotate; state.drag = nil }
    case .chooseIntent(let intent):
        if state.mode == .annotate { setIntent(&state, intent) }
    case .chooseTool(let tool):
        if state.mode == .annotate { state.tool = tool; state.active = nil; state.noteMode = false; state.typingID = nil }
    case .toggleHelp:
        if state.mode == .select || state.mode == .annotate { state.help.toggle() }
    case .copy:
        if state.mode == .annotate { return finish(&state) }
    case .pointerLeft:
        state.cursor = nil
    case .pointerDown(let p):
        guard state.mode == .select || state.mode == .annotate else { break }
        state.help = false
        if state.mode == .annotate && state.tool != .crop, let mark = state.hit(p) {
            state.typingID = nil
            state.drag = Drag(movedMark: mark, x0: p.x, y0: p.y, x1: p.x, y1: p.y)
            state.active = mark.kind == .redact ? nil : mark.id; state.noteMode = false
        } else {
            state.typingID = nil
            state.drag = Drag(x0: p.x, y0: p.y, x1: p.x, y1: p.y)
        }
    case .pointerMoved(let p, let inside):
        guard state.mode == .select || state.mode == .annotate else { break }
        state.cursor = inside || state.drag != nil ? p : nil
        guard var drag = state.drag else { break }
        drag.x1 = p.x; drag.y1 = p.y; state.drag = drag
        if let original = drag.movedMark, let i = state.marks.firstIndex(where: { $0.id == original.id }) {
            state.marks[i] = original.moved(dx: p.x - drag.x0, dy: p.y - drag.y0)
        }
    case .pointerUp:
        guard let drag = state.drag else { break }
        state.drag = nil
        if let original = drag.movedMark {
            if let i = state.marks.firstIndex(where: { $0.id == original.id }) {
                // Below this distance a press is a click, even if a trackpad jittered a little.
                if hypot(drag.x1 - drag.x0, drag.y1 - drag.y0) > 0.003 {
                    let result = state.marks[i]; state.marks[i] = original; state.record(); state.marks[i] = result
                } else {
                    state.marks[i] = original
                    state.noteMode = original.kind != .redact
                }
            }
            break
        }
        let rect = NormRect(x: min(drag.x0, drag.x1), y: min(drag.y0, drag.y1), w: abs(drag.x1 - drag.x0), h: abs(drag.y1 - drag.y0))
        let small = rect.w < 0.008 && rect.h < 0.014
        if state.mode == .select {
            let sel = small ? NormRect.full : rect
            state.sel = sel; state.lastSel = sel; state.mode = .annotate
        } else if state.mode == .annotate {
            if state.tool == .crop && !small {
                state.record(); state.sel = rect; state.lastSel = rect; state.marks.removeAll { !$0.intersects(rect) }
                state.active = nil; state.noteMode = false; state.tool = .box
            } else {
                let kind: MarkKind
                if small { kind = .pin }
                else {
                    switch state.tool {
                    case .box: kind = .box
                    case .oval: kind = .oval
                    case .arrow: kind = .arrow
                    case .highlight: kind = .highlight
                    case .redact: kind = .redact
                    case .crop: kind = .pin
                    }
                }
                if state.tool == .crop { state.tool = .box }
                state.record()
                let mark = Mark(id: state.nextID, kind: kind, intent: state.intent, x: small ? drag.x0 : rect.x, y: small ? drag.y0 : rect.y, w: rect.w, h: rect.h, x0: drag.x0, y0: drag.y0, x1: drag.x1, y1: drag.y1)
                state.nextID += 1; state.marks.append(mark); state.active = kind == .redact ? nil : mark.id; state.noteMode = kind != .redact
            }
        }
    case .insertText(let text):
        if state.mode == .select {
            if text == " " { return [.pickWindow(state.cursor ?? NormPoint(x: 0, y: 0))] }
            if text.lowercased() == "r", let sel = state.lastSel { state.sel = sel; state.mode = .annotate; state.drag = nil }
            else if text == "?" { state.help.toggle() }
        } else if state.mode == .annotate {
            if state.noteMode, let index = state.marks.firstIndex(where: { $0.id == state.active }) {
                if state.marks[index].note.isEmpty, text.count == 1, let n = Int(text), let intent = Intent(rawValue: n) {
                    setIntent(&state, intent)
                } else if !text.isEmpty {
                    let available = max(0, 140 - state.marks[index].note.count)
                    let addition = String(text.prefix(available))
                    if !addition.isEmpty {
                        if state.typingID != state.active { state.record(); state.typingID = state.active }
                        state.marks[index].note += addition
                    }
                }
            } else if text == "?" { state.help.toggle() }
            else if text.count == 1, let n = Int(text), let intent = Intent(rawValue: n) { setIntent(&state, intent) }
            else {
                let tools: [String: Tool] = ["b": .box, "o": .oval, "a": .arrow, "h": .highlight, "x": .redact, "c": .crop]
                if let tool = tools[text.lowercased()] { state.tool = tool; state.active = nil; state.noteMode = false; state.typingID = nil }
            }
        }
    case .key(let input):
        if state.mode == .done {
            if input.key == .escape || input.key == .enter { state.mode = .idle; return [.dismissReceipt] }
            break
        }
        if state.mode == .select {
            if input.key == .escape { state.mode = .idle; state.drag = nil; state.cursor = nil; return [.cancel] }
            break
        }
        guard state.mode == .annotate else { break }
        if input.command && input.key == .character("c") { return finish(&state) }
        if input.key == .enter {
            // ⏎ leaves what is open; only with nothing open does it finish, so a note ends with ⏎⏎ and there is no time window.
            state.typingID = nil
            if state.help { state.help = false; return [] }
            let gestureRunning = state.drag != nil
            if gestureRunning { _ = reduce(&state, .pointerUp) }
            if gestureRunning || state.active != nil || state.noteMode { state.active = nil; state.noteMode = false; return [] }
            return finish(&state)
        }
        if input.command {
            if input.key == .character("z") {
                state.typingID = nil
                if input.shift, let snapshot = state.future.popLast() { state.past.append(state.snapshot); state.restore(snapshot) }
                else if !input.shift, let snapshot = state.past.popLast() { state.future.append(state.snapshot); state.restore(snapshot) }
            }
            break
        }
        switch input.key {
        case .escape:
            state.typingID = nil
            if state.help { state.help = false }
            else if state.active != nil || state.noteMode { state.active = nil; state.noteMode = false }
            else { state.mode = .idle; state.marks = []; state.cursor = nil; return [.cancel] }
        case .tab:
            state.typingID = nil
            let ids = state.marks.filter { $0.kind != .redact }.map(\.id)
            if !ids.isEmpty {
                let index = state.active.flatMap { ids.firstIndex(of: $0) }
                let next = index.map { ($0 + (input.shift ? -1 : 1) + ids.count) % ids.count } ?? (input.shift ? ids.count - 1 : 0)
                state.active = ids[next]; state.noteMode = true
            }
        case .backspace, .delete:
            guard let i = state.marks.firstIndex(where: { $0.id == state.active }) else { break }
            if state.noteMode {
                if input.key == .backspace && !state.marks[i].note.isEmpty {
                    if state.typingID != state.active { state.record(); state.typingID = state.active }
                    state.marks[i].note.removeLast()
                }
            } else { state.record(); state.marks.remove(at: i); state.active = nil; state.typingID = nil }
        case .left, .right, .up, .down:
            guard !state.noteMode, let i = state.marks.firstIndex(where: { $0.id == state.active }), state.stage.pointWidth > 0, state.stage.pointHeight > 0 else { break }
            let step = input.shift ? 10.0 : 1.0
            let dx = input.key == .left ? -step / state.stage.pointWidth : input.key == .right ? step / state.stage.pointWidth : 0
            let dy = input.key == .up ? -step / state.stage.pointHeight : input.key == .down ? step / state.stage.pointHeight : 0
            state.record(); state.marks[i] = state.marks[i].moved(dx: dx, dy: dy)
        default: break
        }
    }
    return []
}

private func finish(_ state: inout CaptureState) -> [Effect] {
    // A gesture still under the pointer counts: the user sees it, and a redaction must never be dropped.
    if state.drag != nil { _ = reduce(&state, .pointerUp) }
    state.mode = .done; state.noteMode = false; state.drag = nil; state.help = false; state.cursor = nil
    return [.finish]
}

private func setIntent(_ state: inout CaptureState, _ intent: Intent) {
    // Not an undo step: only shapes, deletions, moves and note sessions are.
    if let index = state.marks.firstIndex(where: { $0.id == state.active }) {
        state.marks[index].intent = intent
    }
    state.intent = intent
}
