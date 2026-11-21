import RawBoyBrowseKit
import Testing

struct PhotoGroupsTests {
    @Test func rawAndJpegPairIsOnePhotoWithRawAsMain() {
        let groups = PhotoGroups.group(["DSCF1.JPG", "DSCF1.RAF", "notes.txt"])
        #expect(groups == [PhotoGroup(stem: "DSCF1", main: "DSCF1.RAF", companions: ["DSCF1.JPG"], sidecars: [])])
    }

    @Test func videoIsNeverMainWhenAPictureSharesItsName() {
        let groups = PhotoGroups.group(["IMG_1.AVI", "IMG_1.HEIC", "clip.mp4"])
        #expect(groups.map(\.main) == ["clip.mp4", "IMG_1.HEIC"])
        #expect(groups[1].companions == ["IMG_1.AVI"])
    }

    @Test func namesCompareCaseInsensitively() {
        let groups = PhotoGroups.group(["img_1.jpg", "IMG_1.ARW"])
        #expect(groups.count == 1)
        #expect(groups[0].main == "IMG_1.ARW")
    }

    @Test func naturalOrder() {
        let mains = PhotoGroups.group(["IMG_10.jpg", "IMG_2.jpg", "IMG_1.jpg"]).map(\.main)
        #expect(mains == ["IMG_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
    }

    @Test func sidecarsOfEveryKind() {
        let groups = PhotoGroups.group([
            "IMG_1.CR2", "IMG_1.xmp", "IMG_1.CR2.xmp", "IMG_1_01.CR2.xmp", "IMG_2.jpg", "orphan.xmp",
        ])
        #expect(groups.map(\.main) == ["IMG_1.CR2", "IMG_2.jpg"])
        #expect(groups[0].sidecars == ["IMG_1.CR2.xmp", "IMG_1.xmp", "IMG_1_01.CR2.xmp"])
        #expect(groups[1].sidecars.isEmpty)
    }

    @Test func numberedPhotoIsNotADuplicate() {
        // IMG_1_01.CR2 exists itself, so its sidecar is its own, not a darktable duplicate of IMG_1.CR2.
        let groups = PhotoGroups.group(["IMG_1.CR2", "IMG_1_01.CR2", "IMG_1_01.CR2.xmp"])
        #expect(groups.first { $0.main == "IMG_1_01.CR2" }?.sidecars == ["IMG_1_01.CR2.xmp"])
        #expect(groups.first { $0.main == "IMG_1.CR2" }?.sidecars == [])
    }

    @Test func stem() {
        #expect(PhotoGroups.stem(of: "IMG_1.CR2.xmp") == "IMG_1.CR2")
        #expect(PhotoGroups.stem(of: ".hidden") == ".hidden")
        #expect(PhotoGroups.stem(of: "plain") == "plain")
    }
}
