import RawBoyBrowseKit
import Testing

struct PrefetchPlanTests {
    @Test func forwardLoadsAheadFirst() {
        #expect(PrefetchPlan.order(current: 5, count: 72, forward: true) == [6, 7, 8, 4])
    }

    @Test func backwardLoadsBehindFirst() {
        #expect(PrefetchPlan.order(current: 5, count: 72, forward: false) == [4, 3, 2, 6])
    }

    @Test func staysInRange() {
        #expect(PrefetchPlan.order(current: 70, count: 72, forward: true) == [71, 69])
        #expect(PrefetchPlan.order(current: 0, count: 1, forward: true) == [])
    }
}
