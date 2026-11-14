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
}
