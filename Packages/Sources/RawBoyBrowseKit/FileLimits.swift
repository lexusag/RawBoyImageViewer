import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// The process's open-file limit. GUI apps start with a soft limit of 256 descriptors on macOS, which a folder of a
/// thousand raws opened through ImageIO (several descriptors each while decoding) can use up: opening then fails for
/// everything, thumbnails and photos alike.
public enum FileLimits {
    /// Raises the soft limit to [wanted] (or the hard limit, when lower). Returns the soft limit now in force, or nil
    /// when it can't be read.
    @discardableResult
    public static func raise(to wanted: UInt64 = 10240) -> UInt64? {
        #if canImport(Darwin)
            var limit = rlimit()
            guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return nil }
            let target = min(UInt64(wanted), UInt64(limit.rlim_max))
            if UInt64(limit.rlim_cur) < target {
                limit.rlim_cur = rlim_t(target)
                guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else { return UInt64(limit.rlim_cur) }
            }
            return UInt64(limit.rlim_cur)
        #else
            return nil
        #endif
    }
}
