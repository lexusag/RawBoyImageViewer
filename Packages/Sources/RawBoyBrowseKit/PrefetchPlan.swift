/// Which neighbours of the current photo to load ahead, nearest first.
public enum PrefetchPlan {
    /// Indices to load once [current] shows: [ahead] photos in the browsing direction, then [behind] the other way.
    public static func order(current: Int, count: Int, forward: Bool, ahead: Int = 3, behind: Int = 1) -> [Int] {
        let step = forward ? 1 : -1
        let next = (1...max(ahead, 1)).prefix(ahead).map { current + $0 * step }
        let previous = (1...max(behind, 1)).prefix(behind).map { current - $0 * step }
        return (next + previous).filter { $0 >= 0 && $0 < count && $0 != current }
    }
}
