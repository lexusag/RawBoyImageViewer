import Foundation
import ImageIO
import Testing

@testable import ViewerImaging

struct FullMetadataTests {
    @Test func humanisesNames() {
        #expect(FullMetadata.humanise("ExposureTime") == "Exposure Time")
        #expect(FullMetadata.humanise("ISOSpeedRatings") == "ISO Speed Ratings")
        #expect(FullMetadata.humanise("FNumber") == "F Number")
        #expect(FullMetadata.humanise("1234") == "Tag 1234")
        #expect(FullMetadata.humanise("rawboy:Develop") == "rawboy:Develop")
    }

    @Test func formatsValues() {
        #expect(FullMetadata.format("  hello \n") == "hello")
        #expect(FullMetadata.format("") == nil)
        #expect(FullMetadata.format(NSNumber(value: 100)) == "100")
        #expect(FullMetadata.format(NSNumber(value: 2.8)) == "2.8")
        #expect(FullMetadata.format(NSNumber(value: true)) == "Yes")
        #expect(FullMetadata.format([NSNumber(value: 1), NSNumber(value: 2.5)] as [Any]) == "1, 2.5")
        #expect(FullMetadata.format(Data(count: 2048))?.contains("binary") == true)
    }

    @Test func groupsAreOrderedAndNamed() {
        let props: [CFString: Any] = [
            "PixelWidth" as CFString: NSNumber(value: 6000),
            "{Exif}" as CFString: ["FNumber": 2.8, "ExposureTime": 0.004],
            "{TIFF}" as CFString: ["ImageDescription": "merged 8 frames", "Make": "Google"],
            "{MakerFuji}" as CFString: ["1234": 7, "Nested": ["Inner": "x"]],
        ]
        let groups = FullMetadata.groups(props, xmp: [MetadataEntry(name: "rawboy:Pick", value: "1")])
        #expect(groups.map(\.name) == ["Image", "TIFF", "EXIF", "Maker note: Fuji", "XMP"])
        #expect(groups[0].entries == [MetadataEntry(name: "Pixel Width", value: "6000")])
        #expect(groups[1].entries.map(\.name) == ["Image Description", "Make"])
        #expect(groups[3].entries.map(\.name) == ["Nested Inner", "Tag 1234"])
    }

    @Test func filterMatchesNamesAndValues() {
        let groups = [
            MetadataGroup(name: "TIFF", entries: [MetadataEntry(name: "Make", value: "Google")]),
            MetadataGroup(
                name: "EXIF",
                entries: [MetadataEntry(name: "F Number", value: "2.8"), MetadataEntry(name: "ISO", value: "100")]),
        ]
        #expect(FullMetadata.filter(groups, query: "").count == 2)
        #expect(FullMetadata.filter(groups, query: "goog").map(\.name) == ["TIFF"])
        #expect(FullMetadata.filter(groups, query: "iso").first?.entries.count == 1)
        #expect(FullMetadata.filter(groups, query: "exif").first?.entries.count == 2)
        #expect(FullMetadata.filter(groups, query: "zzz").isEmpty)
    }
}
