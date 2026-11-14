import RawBoyBrowseKit
import Testing

struct PhotoFileTypeTests {
    @Test(arguments: ["DSCF0001.RAF", "a.dng", "IMG_1.CR3", "x.Arw"])
    func raws(_ name: String) {
        #expect(PhotoFileType(fileName: name) == .raw)
    }

    @Test(arguments: ["a.jpg", "B.JPEG", "c.heic", "d.tif", "e.png"])
    func displayFiles(_ name: String) {
        #expect(PhotoFileType(fileName: name) == .display)
    }

    @Test(arguments: ["IMG_1.xmp", "notes.txt", "noextension", ".jpg", "a.jpg.part"])
    func ignored(_ name: String) {
        #expect(PhotoFileType(fileName: name) == nil)
    }
}
