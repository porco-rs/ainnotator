/// A position relative to the captured display image: 0...1 on both axes, origin top left.
/// Pixel coordinates in the output are derived from these values, so the same input always gives the same bytes.
public struct NormPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct NormRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public static let full = NormRect(x: 0, y: 0, w: 1, h: 1)
}

/// idle = nothing on screen · select = choosing the area · annotate = marking up the area · done = the receipt is showing.
public enum Mode: Equatable, Sendable {
    case idle, select, annotate, done
}

public enum Tool: String, CaseIterable, Sendable {
    case box, oval, arrow, highlight, redact, crop
}

/// The digit a user presses is the raw value.
public enum Intent: Int, CaseIterable, Sendable {
    case bug = 1, change, keep, question

    /// Upper-case word of the intent, as shown in the card legend.
    public var payloadWord: String {
        switch self {
        case .bug: "BUG"
        case .change: "CHANGE"
        case .keep: "KEEP"
        case .question: "QUESTION"
        }
    }

    /// Lower-case value in the JSON output.
    public var jsonValue: String { payloadWord.lowercased() }
}

public enum MarkKind: String, Sendable {
    case box, oval, arrow, highlight, redact, pin
}

/// x/y/w/h is the bounding rectangle, x0/y0 → x1/y1 the drawn gesture (arrows use these).
public struct Mark: Equatable, Sendable {
    public var id: Int
    public var kind: MarkKind
    public var intent: Intent
    public var note: String
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    public init(
        id: Int, kind: MarkKind, intent: Intent, note: String = "",
        x: Double, y: Double, w: Double, h: Double, x0: Double, y0: Double, x1: Double, y1: Double
    ) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.note = note
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }
}

/// A gesture in progress. `movedMark` is set while an existing mark is being dragged.
public struct Drag: Equatable, Sendable {
    public var movedMark: Mark?
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    public init(movedMark: Mark? = nil, x0: Double, y0: Double, x1: Double, y1: Double) {
        self.movedMark = movedMark
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }
}

/// The display the session works on. Pixels address the image, points address pointer distances and hit tolerances.
public struct Stage: Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var pointWidth: Double
    public var pointHeight: Double

    public init(pixelWidth: Int, pixelHeight: Int, pointWidth: Double, pointHeight: Double) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
    }
}

/// Everything the reducer decides on. A value, so undo and background snapshots are plain copies.
public struct HistorySnapshot: Equatable, Sendable {
    public var marks: [Mark]
    public var sel: NormRect?
    public var lastSel: NormRect?

    public init(marks: [Mark], sel: NormRect?, lastSel: NormRect?) {
        self.marks = marks
        self.sel = sel
        self.lastSel = lastSel
    }
}

public struct CaptureState: Equatable, Sendable {
    public var mode: Mode = .idle
    public var stage = Stage(pixelWidth: 1, pixelHeight: 1, pointWidth: 1, pointHeight: 1)
    public var sel: NormRect?
    public var lastSel: NormRect?
    public var marks: [Mark] = []
    public var active: Int?
    public var noteMode = false
    public var tool: Tool = .box
    public var intent: Intent = .change
    public var drag: Drag?
    public var past: [HistorySnapshot] = []
    public var future: [HistorySnapshot] = []
    public var help = false
    public var cursor: NormPoint?
    public var nextID = 1
    public var typingID: Int?

    public init() {}
}

/// Automatic context. Missing parts are left out of the output.
public struct CaptureContext: Equatable, Sendable {
    public var app: String?
    public var window: String?
    public var url: String?
    public var repo: String?
    public var branch: String?

    public init(app: String? = nil, window: String? = nil, url: String? = nil, repo: String? = nil, branch: String? = nil) {
        self.app = app
        self.window = window
        self.url = url
        self.repo = repo
        self.branch = branch
    }
}
