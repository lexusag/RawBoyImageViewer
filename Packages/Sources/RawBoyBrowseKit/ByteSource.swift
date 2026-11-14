import Foundation

/// Random access to a file's bytes, so parsers read only what they need (a preview's few kilobytes of markers, not a
/// 60 MB raw). Reads past the end return fewer bytes.
public protocol ByteSource {
    var size: Int { get }
    func read(_ offset: Int, _ length: Int) -> [UInt8]
}

/// Bytes in memory (tests, small files).
public struct BytesSource: ByteSource {
    public let bytes: [UInt8]

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var size: Int { bytes.count }

    public func read(_ offset: Int, _ length: Int) -> [UInt8] {
        guard offset >= 0, length > 0, offset < bytes.count else { return [] }
        return Array(bytes[offset..<min(offset + length, bytes.count)])
    }
}

/// A file, read through 64 KB blocks kept for the source's lifetime (parsers make many small reads close together).
public final class FileSource: ByteSource {
    public let size: Int
    private let handle: FileHandle
    private var blocks: [Int: [UInt8]] = [:]
    private static let blockSize = 1 << 16
    private static let maxBlocks = 64

    public init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url),
            let end = try? handle.seekToEnd()
        else { return nil }
        self.handle = handle
        size = Int(end)
    }

    deinit {
        try? handle.close()
    }

    public func read(_ offset: Int, _ length: Int) -> [UInt8] {
        guard offset >= 0, length > 0, offset < size else { return [] }
        let end = min(offset + length, size)
        // Large reads (a whole preview) go straight to the file.
        if end - offset > Self.blockSize * 4 { return readFile(offset, end - offset) }
        var out: [UInt8] = []
        out.reserveCapacity(end - offset)
        var at = offset
        while at < end {
            let index = at / Self.blockSize
            let block = self.block(index)
            let start = at - index * Self.blockSize
            guard start < block.count else { break }
            let take = min(block.count - start, end - at)
            out.append(contentsOf: block[start..<start + take])
            at += take
        }
        return out
    }

    private func block(_ index: Int) -> [UInt8] {
        if let hit = blocks[index] { return hit }
        if blocks.count >= Self.maxBlocks { blocks.removeAll(keepingCapacity: true) }
        let block = readFile(index * Self.blockSize, Self.blockSize)
        blocks[index] = block
        return block
    }

    private func readFile(_ offset: Int, _ length: Int) -> [UInt8] {
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
            let data = try? handle.read(upToCount: length)
        else { return [] }
        return [UInt8](data)
    }
}

// Reading numbers from byte arrays: out of range reads as 0, so truncated files parse as "nothing found".
extension Array where Element == UInt8 {
    func u8(_ at: Int) -> Int { at >= 0 && at < count ? Int(self[at]) : 0 }

    func u16(_ at: Int, _ le: Bool) -> Int {
        le ? u8(at) | u8(at + 1) << 8 : u8(at) << 8 | u8(at + 1)
    }

    func u32(_ at: Int, _ le: Bool) -> Int {
        le ? u16(at, true) | u16(at + 2, true) << 16 : u16(at, false) << 16 | u16(at + 2, false)
    }

    func u64be(_ at: Int) -> UInt64 { UInt64(u32(at, false)) << 32 | UInt64(u32(at + 4, false)) }

    func ascii(_ from: Int, _ to: Int) -> String {
        guard from >= 0, to <= count, from < to else { return "" }
        return String(decoding: self[from..<to], as: UTF8.self)
    }
}

extension ByteSource {
    func u8(_ at: Int) -> Int { read(at, 1).u8(0) }
    func u16(_ at: Int, _ le: Bool) -> Int { read(at, 2).u16(0, le) }
    func u32(_ at: Int, _ le: Bool) -> Int { read(at, 4).u32(0, le) }
}
