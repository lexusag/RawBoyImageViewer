import Foundation
import Testing
import ViewerImaging

struct WorkGateTests {
    @Test func neverRunsMoreThanTheLimit() async {
        let gate = WorkGate(limit: 3)
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    _ = await gate.run {
                        await counter.enter()
                        try? await Task.sleep(nanoseconds: 2_000_000)
                        await counter.leave()
                    }
                }
            }
        }
        #expect(await counter.peak <= 3)
        #expect(await counter.total == 40)
        #expect(await gate.active == 0)
    }

    @Test func cancelledWaitersLeaveTheQueue() async {
        let gate = WorkGate(limit: 1)
        #expect(await gate.acquire())
        let waiter = Task { await gate.acquire() }
        while await gate.waiting == 0 { await Task.yield() }
        waiter.cancel()
        #expect(await waiter.value == false)
        #expect(await gate.waiting == 0)
        await gate.release()
        #expect(await gate.active == 0)
    }

    @Test func newestWaiterGoesFirst() async {
        let gate = WorkGate(limit: 1)
        #expect(await gate.acquire())
        let order = Order()
        let first = Task {
            _ = await gate.acquire()
            await order.add(1)
            await gate.release()
        }
        while await gate.waiting < 1 { await Task.yield() }
        let second = Task {
            _ = await gate.acquire()
            await order.add(2)
            await gate.release()
        }
        while await gate.waiting < 2 { await Task.yield() }
        await gate.release()
        await first.value
        await second.value
        #expect(await order.items == [2, 1])
    }
}

private actor Counter {
    private var now = 0
    private(set) var peak = 0
    private(set) var total = 0
    func enter() {
        now += 1
        total += 1
        peak = max(peak, now)
    }
    func leave() { now -= 1 }
}

private actor Order {
    private(set) var items: [Int] = []
    func add(_ n: Int) { items.append(n) }
}
