import RawBoyBrowseKit
import Testing

struct FileLimitsTests {
    @Test func raisesTheDescriptorLimitAboveTheGUIDefault() throws {
        let limit = try #require(FileLimits.raise())
        #expect(limit > 256)
    }
}
