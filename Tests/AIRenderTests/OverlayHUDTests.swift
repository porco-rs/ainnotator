import AICore
import AIRender
import CoreGraphics
import Testing

/// The HUD is as wide as its words, so the positions below are those of the German one.
@Test @MainActor func hudHitTestingAndCursor() {
    let scene = OverlayScene(size: CGSize(width: 1288, height: 638), scale: 2, language: .de)
    var state = CaptureState()
    state.mode = .annotate
    state.stage = Stage(pixelWidth: 2576, pixelHeight: 1276, pointWidth: 1288, pointHeight: 638)
    state.sel = .full
    scene.apply(state, isActive: true)
    #expect(scene.action(at: CGPoint(x: 315, y: 20)) == .chooseIntent(.bug))
    #expect(scene.action(at: CGPoint(x: 1000, y: 20)) == .copy)
    #expect(scene.containsHUD(CGPoint(x: 210, y: 20)))
    #expect(!scene.containsHUD(CGPoint(x: 210, y: 100)))
    state.cursor = NormPoint(x: 315.0 / 1288, y: 20.0 / 638)
    scene.apply(state, isActive: true)
    #expect(scene.wantsArrowCursor)
    scene.apply(state, isActive: false)
    #expect(!scene.wantsArrowCursor)
}

/// On a display with a camera housing the top strip is partly hidden, so the toolbar starts below it. Seen on
/// a notched MacBook display, where the toolbar sat behind the housing.
@Test @MainActor func theToolbarStartsBelowTheCameraHousing() {
    var state = CaptureState()
    state.mode = .annotate
    state.stage = Stage(pixelWidth: 2576, pixelHeight: 1276, pointWidth: 1288, pointHeight: 638)
    state.sel = .full
    state.help = true
    let plain = OverlayScene(size: CGSize(width: 1288, height: 638), scale: 2)
    plain.apply(state, isActive: true)
    let notched = OverlayScene(size: CGSize(width: 1288, height: 638), scale: 2, topInset: 38)
    notched.apply(state, isActive: true)
    let before = plain.accessibilityItems.filter { $0.action != nil }
    let after = notched.accessibilityItems.filter { $0.action != nil }
    #expect(!after.isEmpty)
    #expect(after.count == before.count)
    for (old, new) in zip(before, after) {
        #expect(new.frame == old.frame.offsetBy(dx: 0, dy: 38))
        #expect(new.frame.minY >= 38)
        #expect(notched.action(at: CGPoint(x: new.frame.midX, y: new.frame.midY)) == new.action)
    }
    // Nothing of the toolbar is left in the hidden strip.
    #expect(!notched.containsHUD(CGPoint(x: 644, y: 20)))
    #expect(notched.containsHUD(CGPoint(x: 644, y: 58)))
}

/// While choosing the area the bar read "AREA ?": a mode name and a bare help button side by side, which looked like
/// a question. Now the name says what to do and the button carries its own word, so the bar is as wide as both.
@Test @MainActor func theAreaStepNamesItsHelpButton() throws {
    for language in Language.allCases {
        let scene = OverlayScene(size: CGSize(width: 1288, height: 638), scale: 2, language: language)
        var state = CaptureState()
        state.mode = .select
        scene.apply(state, isActive: true)
        let items = scene.accessibilityItems
        let toolbar = try #require(items.first { $0.action == nil })
        let help = try #require(items.first { $0.action == .toggleHelp })
        // The old bar was 112 points wide with a 26 point button.
        #expect(toolbar.frame.width > 150)
        #expect(help.frame.width > 50)
        #expect(toolbar.frame.contains(help.frame))
        #expect(scene.action(at: CGPoint(x: help.frame.midX, y: help.frame.midY)) == .toggleHelp)
    }
}

@Test @MainActor func accessibilityNamesAreEnglishByDefault() {
    let scene = OverlayScene(size: CGSize(width: 1288, height: 638), scale: 2)
    var state = CaptureState()
    state.mode = .select
    scene.apply(state, isActive: true)
    #expect(scene.accessibilityItems.map(\.name) == ["Annotate", "Keyboard shortcuts"])
    state.mode = .annotate
    state.marks = [Mark(id: 1, kind: .box, intent: .question, note: "Test", x: 0.1, y: 0.2, w: 0.3, h: 0.4, x0: 0.1, y0: 0.2, x1: 0.4, y1: 0.6)]
    scene.apply(state, isActive: true)
    #expect(scene.accessibilityItems.map(\.name) == ["Annotate", "Bug", "Change", "Keep", "Question", "Box", "Oval", "Arrow", "Highlight", "Redact", "Crop", "Keyboard shortcuts", "Copy", "Mark 1, Question, Test"])
    for item in scene.accessibilityItems where item.action != nil {
        #expect(scene.action(at: CGPoint(x: item.frame.midX, y: item.frame.midY)) == item.action)
    }
}

@Test @MainActor func accessibilityReflectsVisibleControlsAndMarks() {
    let scene = OverlayScene(size: CGSize(width: 1288, height: 638), scale: 2, language: .de)
    var state = CaptureState()
    state.mode = .select
    scene.apply(state, isActive: true)
    #expect(scene.accessibilityItems.map(\.name) == ["Annotieren", "Tastenkürzel"])
    state.mode = .annotate
    state.marks = [Mark(id: 1, kind: .box, intent: .question, note: "Test", x: 0.1, y: 0.2, w: 0.3, h: 0.4, x0: 0.1, y0: 0.2, x1: 0.4, y1: 0.6)]
    scene.apply(state, isActive: true)
    let items = scene.accessibilityItems
    #expect(items.map(\.name) == ["Annotieren", "Bug", "Ändern", "Behalten", "Frage", "Box", "Kreis", "Pfeil", "Textmarker", "Schwärzen", "Zuschneiden", "Tastenkürzel", "Kopieren", "Markierung 1, Frage, Test"])
    for item in items where item.action != nil {
        #expect(scene.action(at: CGPoint(x: item.frame.midX, y: item.frame.midY)) == item.action)
    }
    #expect(items.first { $0.name == "Ändern" }?.selected == true)
    scene.apply(state, isActive: false)
    #expect(scene.accessibilityItems.isEmpty)
}
