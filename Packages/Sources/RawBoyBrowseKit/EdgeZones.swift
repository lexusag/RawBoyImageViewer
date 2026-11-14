/// The screen edges that reveal panels. The bottom is the previous/next band (`BottomBand`), not a panel.
public enum PanelEdge: String, CaseIterable, Hashable, Sendable {
    /// Actions.
    case left
    /// Photo details.
    case right
    /// The folder's filmstrip.
    case top
}

/// Timings and sizes of the edge zones, in points and seconds (PLAN.md §2).
public struct EdgeZoneConfig: Equatable, Sendable {
    /// How close to an edge the pointer must be to start opening its panel.
    public var triggerWidth = 8.0
    /// How long the pointer must rest there, so passing over an edge doesn't flicker a panel open.
    public var dwell = 0.12
    /// How far outside an open panel the pointer may stray without closing it.
    public var grace = 24.0
    /// How long after the pointer leaves a panel (and its grace margin) it closes.
    public var closeDelay = 0.3
    /// Corners that open nothing, so two panels never open together.
    public var cornerDeadZone = 24.0

    public init() {}
}

/// Which edge panels show, from the pointer, the keys and the pins. Pure logic with the time passed in, so it is
/// tested without timers; the view calls `update` on pointer moves and again at `nextDeadline`.
///
/// Coordinates are the viewer's, y down. Only one unpinned panel shows at a time.
public struct EdgeZones: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case closed
        /// The pointer reached the edge at `since`; the panel opens after the dwell.
        case arming(since: Double)
        /// Opened by the pointer: stays while the pointer is over it or near it.
        case open
        /// The pointer left at `since`; the panel closes after the close delay unless it comes back.
        case closing(since: Double)
        /// Opened by a key or a touch swipe: stays until closed the same way, or another panel opens.
        case held
    }

    public var config: EdgeZoneConfig
    public private(set) var phases: [PanelEdge: Phase] = [:]
    /// Pinned panels always show (unless the chrome is hidden) and the photo fits beside them.
    public private(set) var pinned: Set<PanelEdge>
    /// Tab: pinned panels hidden too, for a clean look at the photo. Edges still reveal their panels.
    public private(set) var chromeHidden = false

    public init(config: EdgeZoneConfig = EdgeZoneConfig(), pinned: Set<PanelEdge> = []) {
        self.config = config
        self.pinned = pinned
    }

    public func phase(_ edge: PanelEdge) -> Phase { phases[edge] ?? .closed }

    /// The panels to show.
    public var visible: Set<PanelEdge> {
        var edges = chromeHidden ? Set<PanelEdge>() : pinned
        for edge in PanelEdge.allCases where !pinned.contains(edge) {
            switch phase(edge) {
            case .open, .closing, .held: edges.insert(edge)
            case .closed, .arming: break
            }
        }
        return edges
    }

    /// Pinned panels that take room from the photo.
    public var reservedEdges: Set<PanelEdge> { chromeHidden ? [] : pinned }

    /// The edge whose trigger strip holds [p], if any: none in the corners.
    public func hotEdge(at p: Point2D, in size: Size2D) -> PanelEdge? {
        let t = config.triggerWidth
        let c = config.cornerDeadZone
        let nearLeft = p.x <= t
        let nearRight = p.x >= size.width - t
        let nearTop = p.y <= t
        let inCornerColumn = p.x <= c || p.x >= size.width - c
        let inCornerRow = p.y <= c || p.y >= size.height - c
        if nearTop && !inCornerColumn { return .top }
        if (nearLeft || nearRight) && !inCornerRow { return nearLeft ? .left : .right }
        return nil
    }

    /// Updates the phases for the pointer at [pointer] (nil: outside the viewer) at time [now]. [panels] are the
    /// frames of the panels as they show, for the grace margin.
    public mutating func update(pointer: Point2D?, size: Size2D, panels: [PanelEdge: Rect2D], now: Double) {
        let hot = pointer.flatMap { hotEdge(at: $0, in: size) }
        for edge in PanelEdge.allCases where !pinned.contains(edge) {
            let isHot = hot == edge
            let isOver =
                pointer.map { p in panels[edge].map { $0.expanded(by: config.grace).contains(p) } ?? false } ?? false
            switch phase(edge) {
            case .closed:
                if isHot { phases[edge] = .arming(since: now) }
            case .arming(let since):
                if !isHot {
                    phases[edge] = .closed
                } else if now - since >= config.dwell {
                    open(edge, as: .open)
                }
            case .open:
                if !isHot && !isOver { phases[edge] = .closing(since: now) }
            case .closing(let since):
                if isHot || isOver {
                    phases[edge] = .open
                } else if now - since >= config.closeDelay {
                    phases[edge] = .closed
                }
            case .held:
                break
            }
        }
    }

    /// When `update` must run again even if the pointer doesn't move (a dwell or close delay ends), or nil.
    public var nextDeadline: Double? {
        phases.values.compactMap { phase -> Double? in
            switch phase {
            case .arming(let since): since + config.dwell
            case .closing(let since): since + config.closeDelay
            case .closed, .open, .held: nil
            }
        }.min()
    }

    /// A key (or a swipe in from the edge): shows the panel until asked again; a pinned panel is unpinned and closed.
    public mutating func toggle(_ edge: PanelEdge) {
        if pinned.contains(edge) {
            pinned.remove(edge)
            phases[edge] = .closed
            return
        }
        if chromeHidden { chromeHidden = false }
        switch phase(edge) {
        case .open, .closing, .held: phases[edge] = .closed
        case .closed, .arming: open(edge, as: .held)
        }
    }

    /// Pins a showing panel, or unpins it (it then stays open while the pointer is there).
    public mutating func togglePin(_ edge: PanelEdge) {
        if pinned.remove(edge) != nil {
            phases[edge] = .open
        } else {
            pinned.insert(edge)
            phases[edge] = .closed
            chromeHidden = false
        }
    }

    /// Tab: hides every panel, pinned ones included; again shows the pinned ones.
    public mutating func toggleChrome() {
        chromeHidden.toggle()
        if chromeHidden { closeUnpinned() }
    }

    /// Closes every unpinned panel. Returns whether one was showing (Esc closes panels before the viewer).
    @discardableResult
    public mutating func closeUnpinned() -> Bool {
        let wasShowing = !visible.subtracting(pinned).isEmpty
        for edge in PanelEdge.allCases where !pinned.contains(edge) { phases[edge] = .closed }
        return wasShowing
    }

    private mutating func open(_ edge: PanelEdge, as phase: Phase) {
        for other in PanelEdge.allCases where other != edge && !pinned.contains(other) { phases[other] = .closed }
        phases[edge] = phase
    }
}
