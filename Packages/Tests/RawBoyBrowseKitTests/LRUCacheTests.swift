import RawBoyBrowseKit
import Testing

struct LRUCacheTests {
    @Test func evictsLeastRecentOverBudget() {
        var cache = LRUCache<String, Int>(budget: 10)
        cache.insert(1, for: "a", cost: 4)
        cache.insert(2, for: "b", cost: 4)
        _ = cache.value(for: "a")  // "b" is now the least recent
        cache.insert(3, for: "c", cost: 4)
        #expect(cache.contains("a"))
        #expect(!cache.contains("b"))
        #expect(cache.contains("c"))
        #expect(cache.totalCost == 8)
    }

    @Test func keepsAnOversizedNewValue() {
        var cache = LRUCache<String, Int>(budget: 10)
        cache.insert(1, for: "a", cost: 4)
        cache.insert(2, for: "big", cost: 50)
        #expect(cache.count == 1)
        #expect(cache.contains("big"))
    }

    @Test func replacingUpdatesTheCost() {
        var cache = LRUCache<String, Int>(budget: 10)
        cache.insert(1, for: "a", cost: 4)
        cache.insert(2, for: "a", cost: 6)
        #expect(cache.totalCost == 6)
        #expect(cache.peek("a") == 2)
    }

    @Test func manyTouchesKeepOrderAndStayBounded() {
        var cache = LRUCache<Int, Int>(budget: 100)
        for i in 0..<100 { cache.insert(i, for: i, cost: 1) }
        for _ in 0..<1000 { for i in 0..<50 { _ = cache.value(for: i) } }  // 50..99 are the least recent
        cache.insert(0, for: 1000, cost: 10)  // over by 10: 50...59 go
        for i in 50..<60 { #expect(!cache.contains(i)) }
        for i in 0..<50 { #expect(cache.contains(i)) }
        for i in 60..<100 { #expect(cache.contains(i)) }
        #expect(cache.totalCost == 100)
    }

    @Test func removedKeysAreNotEvictedTwice() {
        var cache = LRUCache<String, Int>(budget: 8)
        cache.insert(1, for: "a", cost: 4)
        cache.insert(2, for: "b", cost: 4)
        cache.remove("a")
        cache.insert(3, for: "a", cost: 4)  // a stale pair for "a" sits ahead of "b"
        cache.insert(4, for: "c", cost: 4)  // over: "b" is the least recent live entry
        #expect(!cache.contains("b"))
        #expect(cache.contains("a") && cache.contains("c"))
        #expect(cache.totalCost == 8)
    }
}
