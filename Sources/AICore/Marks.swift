import Foundation

extension Mark {
    func moved(dx: Double, dy: Double) -> Mark {
        var result = self
        result.x += dx; result.y += dy
        result.x0 += dx; result.y0 += dy; result.x1 += dx; result.y1 += dy
        return result
    }

    func intersects(_ rect: NormRect) -> Bool {
        let left = rect.x, right = rect.x + rect.w, top = rect.y, bottom = rect.y + rect.h
        if kind == .pin { return x >= left && x <= right && y >= top && y <= bottom }
        if kind == .arrow {
            var low = 0.0, high = 1.0
            let dx = x1 - x0, dy = y1 - y0
            for (p, q) in [(-dx, x0 - left), (dx, right - x0), (-dy, y0 - top), (dy, bottom - y0)] {
                if p == 0 { if q < 0 { return false }; continue }
                let t = q / p
                if p < 0 { low = max(low, t) } else { high = min(high, t) }
                if low > high { return false }
            }
            return true
        }
        return x + w >= left && x <= right && y + h >= top && y <= bottom
    }
}

extension CaptureState {
    var snapshot: HistorySnapshot { HistorySnapshot(marks: marks, sel: sel, lastSel: lastSel) }
    mutating func record() {
        past.append(snapshot)
        if past.count > 100 { past.removeFirst(past.count - 100) }
        future = []
    }
    mutating func restore(_ snapshot: HistorySnapshot) {
        marks = snapshot.marks; sel = snapshot.sel; lastSel = snapshot.lastSel
        active = nil; noteMode = false; typingID = nil; drag = nil
    }

    func hit(_ p: NormPoint) -> Mark? {
        let pw = stage.pointWidth, ph = stage.pointHeight
        let px = p.x * pw, py = p.y * ph, tol = 9.0
        for m in marks.reversed() {
            let bx = (m.kind == .arrow ? m.x0 : m.x) * pw
            let by = (m.kind == .arrow ? m.y0 : m.y) * ph
            if m.kind != .redact && hypot(px - bx - 10, py - by + 9) < 14 { return m }
            if m.kind == .pin {
                if hypot(px - m.x * pw, py - m.y * ph) < 14 { return m }
            } else if m.kind == .arrow {
                let ax = m.x0 * pw, ay = m.y0 * ph, dx = (m.x1 - m.x0) * pw, dy = (m.y1 - m.y0) * ph
                let length = dx * dx + dy * dy
                let t = length == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length))
                if hypot(px - ax - t * dx, py - ay - t * dy) < tol { return m }
            } else {
                let x0 = m.x * pw, x1 = (m.x + m.w) * pw, y0 = m.y * ph, y1 = (m.y + m.h) * ph
                if m.kind == .redact || m.kind == .highlight {
                    if px > x0 && px < x1 && py > y0 && py < y1 { return m }
                } else if px > x0 - tol && px < x1 + tol && py > y0 - tol && py < y1 + tol &&
                            (abs(px - x0) < tol || abs(px - x1) < tol || abs(py - y0) < tol || abs(py - y1) < tol) { return m }
            }
        }
        return nil
    }
}
