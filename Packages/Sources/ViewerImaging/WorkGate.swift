import Foundation

/// Lets at most `limit` jobs run at once; the rest wait, newest first (a grid being scrolled wants the cells in view
/// now, not the ones it passed), and a waiter whose task is cancelled leaves the queue.
///
/// Thumbnails used to start one detached decode per cell, however many were asked for: in a folder of a thousand
/// compressed DNGs the decodes piled up (each one a full ImageIO raw decode, hundreds of MB and several file
/// descriptors) until memory or the process's descriptor limit ran out and nothing else could load.
public actor WorkGate {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var running = 0
    private var waiters: [Waiter] = []
    private var nextID: UInt64 = 0

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Waits for a free slot. False when the calling task was cancelled first: then there is no slot to give back.
    public func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if running < limit {
            running += 1
            return true
        }
        let id = nextID
        nextID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    /// Gives a slot back (after a successful `acquire`).
    public func release() {
        if let next = waiters.popLast() {
            next.continuation.resume(returning: true)  // the slot passes on
        } else {
            running -= 1
        }
    }

    /// Runs [work] in a slot; nil when cancelled while waiting.
    public func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T? {
        guard await acquire() else { return nil }
        let result = await work()
        release()
        return result
    }

    /// Jobs running now.
    public var active: Int { running }

    /// Jobs waiting.
    public var waiting: Int { waiters.count }

    private func cancel(_ id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
