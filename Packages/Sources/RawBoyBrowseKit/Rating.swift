/// Pick or reject: RawBoy Browser's flags.
public enum Flag: String, Equatable, Hashable, Sendable {
    case pick, reject
}

/// A photo's stars and flag, as RawBoy Browser keeps them (`XmpSidecar.ts`).
public struct Rating: Equatable, Hashable, Sendable {
    /// 0...5.
    public var stars: Int
    public var flag: Flag?

    public init(stars: Int = 0, flag: Flag? = nil) {
        self.stars = stars
        self.flag = flag
    }

    public static let none = Rating()

    public var isRated: Bool { stars > 0 || flag != nil }

    /// [ratings] after [stars] is given to them all: a number every one of them already has clears the stars (as the
    /// same number again does on one photo), and stars take a reject out of the rejects, as in Lightroom.
    public static func withStars(_ ratings: [Rating], _ stars: Int) -> [Rating] {
        let clear = ratings.allSatisfy { $0.stars == stars }
        return ratings.map { Rating(stars: clear ? 0 : stars, flag: $0.flag == .reject ? nil : $0.flag) }
    }

    /// [ratings] after [flag] is toggled on them all: set on each, or cleared when every one already has it.
    public static func withFlag(_ ratings: [Rating], _ flag: Flag) -> [Rating] {
        let clear = ratings.allSatisfy { $0.flag == flag }
        return ratings.map { Rating(stars: $0.stars, flag: clear ? nil : flag) }
    }
}

/// Which photos the grid shows, by flag (RawBoy Browser's `Filter`), with at least some stars.
public enum FlagFilter: String, CaseIterable, Sendable {
    case all, picks, unflagged, rejects

    public func passes(_ rating: Rating, minStars: Int) -> Bool {
        let flagOK =
            switch self {
            case .all: true
            case .picks: rating.flag == .pick
            case .unflagged: rating.flag == nil
            case .rejects: rating.flag == .reject
            }
        return flagOK && rating.stars >= minStars
    }
}

extension FlagFilter {
    /// How many of [ratings] each filter's flag state holds, whatever filter or star minimum is on: the counts shown
    /// on the segments (RawBoy Browser's).
    public static func counts(_ ratings: [Rating]) -> [FlagFilter: Int] {
        var result: [FlagFilter: Int] = [.all: ratings.count, .picks: 0, .unflagged: 0, .rejects: 0]
        for rating in ratings {
            switch rating.flag {
            case .pick: result[.picks, default: 0] += 1
            case .reject: result[.rejects, default: 0] += 1
            case nil: result[.unflagged, default: 0] += 1
            }
        }
        return result
    }
}
