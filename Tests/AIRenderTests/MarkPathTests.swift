import AICore
import AIRender
import CoreGraphics
import Testing

@Test func boxMapsIntoTheCropSpace() {
    let mark = Mark(id: 1, kind: .box, intent: .change, x: 0.5, y: 0.5, w: 0.25, h: 0.25, x0: 0.5, y0: 0.5, x1: 0.75, y1: 0.75)
    let mapping = StageMapping(crop: NormRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5), width: 100, height: 200)
    #expect(MarkPath.rect(for: mark, mapping: mapping) == CGRect(x: 0, y: 0, width: 50, height: 100))
}

@Test func boxAndOvalStrokePathsStayInsideTheirBounds() {
    let mapping = StageMapping(crop: .full, width: 100, height: 100)
    for kind in [MarkKind.box, .oval] {
        let mark = Mark(id: 1, kind: kind, intent: .bug, x: 0.1, y: 0.2, w: 0.4, h: 0.3, x0: 0.1, y0: 0.2, x1: 0.5, y1: 0.5)
        let bounds = MarkPath.path(for: mark, mapping: mapping, inset: 1).boundingBoxOfPath
        #expect(abs(bounds.minX - 11) < 0.001)
        #expect(abs(bounds.minY - 21) < 0.001)
        #expect(abs(bounds.maxX - 49) < 0.001)
        #expect(abs(bounds.maxY - 49) < 0.001)
    }
}
