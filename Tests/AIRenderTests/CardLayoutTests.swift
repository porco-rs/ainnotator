import AICore
@testable import AIRender
import CoreGraphics
import Testing

@Test func cardTabsThatOverlapMoveRight() {
    let anchors = [CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 10, y: 26)]
    #expect(CardRenderer.spread(anchors, scale: 1) == [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 50, y: 10), CGPoint(x: 10, y: 26)])
    #expect(CardRenderer.spread([.zero, .zero], scale: 2) == [.zero, CGPoint(x: 40, y: 0)])
}

@Test func labelsFollowTheDisplayAndTheLongEdgeTheModelSees() {
    let retina = Stage(pixelWidth: 3456, pixelHeight: 2234, pointWidth: 1728, pointHeight: 1117)
    #expect(CardRenderer.labelScale(stage: retina, crop: CGSize(width: 1484, height: 1608)) == 2)
    let plain = Stage(pixelWidth: 1920, pixelHeight: 1080, pointWidth: 1920, pointHeight: 1080)
    #expect(CardRenderer.labelScale(stage: plain, crop: CGSize(width: 640, height: 400)) == 1)
    let fiveK = Stage(pixelWidth: 5120, pixelHeight: 2880, pointWidth: 2560, pointHeight: 1440)
    #expect(CardRenderer.labelScale(stage: fiveK, crop: CGSize(width: 5120, height: 2880)) == 5120.0 / 1568)
}

private func canvas(width: Int, height: Int) throws -> CGImage {
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info))
    return try #require(context.makeImage())
}

private func cardState(note: String) -> CaptureState {
    var state = CaptureState()
    state.stage = Stage(pixelWidth: 2000, pixelHeight: 1000, pointWidth: 1000, pointHeight: 500)
    state.sel = .full
    state.marks = [Mark(id: 1, kind: .box, intent: .bug, note: note, x: 0.1, y: 0.1, w: 0.2, h: 0.2, x0: 0.1, y0: 0.1, x1: 0.3, y1: 0.3)]
    return state
}

@Test func longNotesWrapInsteadOfBeingCutOff() throws {
    let image = try canvas(width: 2000, height: 1000)
    let short = try #require(CardRenderer.render(.init(source: .image(image), state: cardState(note: "short"), footer: "")))
    // Narrow enough to wrap: the note column of a 640 px wide card holds well under 140 characters.
    var narrow = cardState(note: String(repeating: "a long note ", count: 11))
    narrow.sel = NormRect(x: 0, y: 0, w: 0.1, h: 1)
    var narrowShort = narrow
    narrowShort.marks[0].note = "short"
    let wrapped = try #require(CardRenderer.render(.init(source: .image(image), state: narrow, footer: "")))
    let single = try #require(CardRenderer.render(.init(source: .image(image), state: narrowShort, footer: "")))
    #expect(short.width == 2000)
    #expect(wrapped.height > single.height)
}

@Test func thePreviewKeepsItsOwnProportions() throws {
    let image = try canvas(width: 2000, height: 1000)
    let preview = try #require(CardRenderer.render(.init(source: .image(image), state: cardState(note: "short"), footer: ""), previewWidth: 640))
    #expect(preview.width == 640)
    // 320 px of image, legend and footer below it. The bound is wide enough for the legend's header line,
    // which wraps to three lines at this width.
    #expect(preview.height > 320 && preview.height < 560)
}

private func legendMark(_ id: Int, _ kind: MarkKind, _ intent: Intent, _ note: String = "") -> Mark {
    Mark(id: id, kind: kind, intent: intent, note: note, x: 0.1, y: 0.1, w: 0.2, h: 0.2, x0: 0.1, y0: 0.1, x1: 0.3, y1: 0.3)
}

/// The marks of the blind test in research/blind-test: two of the five carry no note.
private let probeMarks = [
    legendMark(1, .box, .change, "Move the Export button next to the search field"),
    legendMark(2, .arrow, .bug, "Total is net, should be gross"),
    legendMark(3, .oval, .question),
    legendMark(4, .box, .keep),
    legendMark(5, .pin, .change, "Font too small here"),
    legendMark(6, .redact, .change),
]

/// The same marks with German notes, for the German words of the legend.
private let germanMarks = [
    legendMark(1, .box, .change, "Export-Button links neben die Suche setzen"),
    legendMark(2, .arrow, .bug, "Summe ist netto, soll brutto sein"),
    legendMark(3, .oval, .question),
    legendMark(4, .box, .keep),
    legendMark(5, .pin, .change, "Schrift hier zu klein"),
    legendMark(6, .redact, .change),
]

/// The German legend. A target may get nothing but the image, so the image has to say which marks are the user's
/// and what each one means, also where no note was typed.
@Test func theLegendListsEveryMarkAndSaysWhichMarksAreTheUsers() throws {
    let legend = try #require(CardRenderer.legend(for: germanMarks, language: .de))
    #expect(legend.header == "5 ANMERKUNGEN DES NUTZERS · nummerierte Marken sind nachträglich gesetzt, alles andere gehört zum Bildschirm")
    #expect(legend.rows.map { "\($0.number) \($0.intent.payloadWord) \($0.shape) \($0.note)" } == [
        "1 CHANGE Kasten Export-Button links neben die Suche setzen",
        "2 BUG Pfeil Summe ist netto, soll brutto sein",
        "3 QUESTION Oval (ohne Notiz)",
        "4 KEEP Kasten (ohne Notiz)",
        "5 CHANGE Punkt Schrift hier zu klein",
    ])
    #expect(legend.rows.map(\.hasNote) == [true, true, false, false, true])
    #expect(legend.hidden == 0)
    #expect(
        CardRenderer.footer(context: "Chrome · lagerwerk.example/bestellungen · shop@main", crop: CGSize(width: 2400, height: 1400), redactions: 1, language: .de)
            == "Chrome · lagerwerk.example/bestellungen · shop@main · 2400×1400 · 1 Bereich geschwärzt (schwarz schraffiert)"
    )
}

/// The PNG is all a target gets, so it lists every mark. The receipt keeps to nine legend rows and
/// then says "+ n more".
@Test func thePNGListsAllMarksAndTheReceiptPreviewStopsAfterNine() throws {
    let marks = (1...12).map { legendMark($0, .box, .change, "Note \($0)") }
    let full = try #require(CardRenderer.legend(for: marks, language: .de))
    #expect(full.rows.count == 12)
    #expect(full.hidden == 0)
    let preview = try #require(CardRenderer.legend(for: marks, maxRows: 9, language: .de))
    #expect(preview.rows.map(\.number) == Array(1...9))
    #expect(preview.hidden == 3)
    #expect(preview.header.hasPrefix("12 ANMERKUNGEN DES NUTZERS"))
}

@Test func withoutMarksThereIsNoLegendAndOneMarkIsSingular() throws {
    #expect(CardRenderer.legend(for: []) == nil)
    #expect(CardRenderer.legend(for: [legendMark(1, .redact, .change)]) == nil)
    let one = try #require(CardRenderer.legend(for: [legendMark(1, .highlight, .keep)], language: .de))
    #expect(one.header.hasPrefix("1 ANMERKUNG DES NUTZERS · "))
    #expect(one.rows.map(\.shape) == ["Textmarker"])
    #expect(CardRenderer.footer(context: "", crop: CGSize(width: 800, height: 600), redactions: 0) == "800×600")
    #expect(CardRenderer.footer(context: "Ghostty", crop: CGSize(width: 800, height: 600), redactions: 2, language: .de) == "Ghostty · 800×600 · 2 Bereiche geschwärzt (schwarz schraffiert)")
}

/// English is the default. These are the words three models read blind and understood (research/blind-test).
@Test func theLegendSpeaksEnglishByDefault() throws {
    let legend = try #require(CardRenderer.legend(for: probeMarks))
    #expect(legend.header == "5 ANNOTATIONS BY THE USER · numbered marks were added afterwards, everything else belongs to the screen")
    #expect(legend.rows.map { "\($0.number) \($0.intent.payloadWord) \($0.shape) \($0.note)" } == [
        "1 CHANGE box Move the Export button next to the search field",
        "2 BUG arrow Total is net, should be gross",
        "3 QUESTION oval (no note)",
        "4 KEEP box (no note)",
        "5 CHANGE point Font too small here",
    ])
    #expect(CardRenderer.footer(context: "Chrome", crop: CGSize(width: 2400, height: 1400), redactions: 1) == "Chrome · 2400×1400 · 1 area redacted (black hatching)")
    #expect(CardRenderer.footer(context: "", crop: CGSize(width: 800, height: 600), redactions: 2) == "800×600 · 2 areas redacted (black hatching)")
    #expect(CardRenderer.Input(source: .image(try canvas(width: 4, height: 4)), state: CaptureState(), footer: "").language == .en)
}

@Test func theEnglishLegendIsSingularForOneMarkAndNamesEveryShape() throws {
    let one = try #require(CardRenderer.legend(for: [legendMark(1, .highlight, .keep)]))
    #expect(one.header.hasPrefix("1 ANNOTATION BY THE USER · "))
    let shapes = try #require(CardRenderer.legend(for: [.box, .oval, .arrow, .highlight, .pin].enumerated().map { legendMark($0.offset + 1, $0.element, .bug) }))
    #expect(shapes.rows.map(\.shape) == ["box", "oval", "arrow", "highlight", "point"])
}

@Test func theHiddenRowsAreCountedInBothLanguages() {
    #expect(CardRenderer.Words(.en).more(3) == "+ 3 more")
    #expect(CardRenderer.Words(.de).more(3) == "+ 3 weitere")
}

/// The row of a mark without a note is really drawn: the card grows by it.
@Test func aMarkWithoutANoteAddsALegendToTheCard() throws {
    let image = try canvas(width: 2000, height: 1000)
    var state = cardState(note: "")
    let marked = try #require(CardRenderer.render(.init(source: .image(image), state: state, footer: "")))
    state.marks = []
    let bare = try #require(CardRenderer.render(.init(source: .image(image), state: state, footer: "")))
    #expect(marked.height > bare.height)
}
