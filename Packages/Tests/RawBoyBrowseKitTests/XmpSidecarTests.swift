import Foundation
import RawBoyBrowseKit
import Testing

/// The cases of RawBoy's browse.test.ts "XMP sidecars" and "Rating a selection".
struct XmpSidecarTests {
    @Test func writesANewSidecarThatReadsBack() throws {
        for r in [Rating(stars: 3), Rating(stars: 0, flag: .reject), Rating(stars: 5, flag: .pick)] {
            let text = try XmpSidecar.write(nil, r)
            #expect(XmpSidecar.read(text) == r)
            #expect(text.contains(#"xmlns:xmp="http://ns.adobe.com/xap/1.0/""#))
        }
    }

    @Test func rejectsAreRatingMinusOne() throws {
        #expect(try XmpSidecar.write(nil, Rating(stars: 4, flag: .reject)).contains(#"xmp:Rating="-1""#))
        #expect(XmpSidecar.read(#"<rdf:Description xmp:Rating="-1"/>"#) == Rating(stars: 0, flag: .reject))
    }

    @Test func changesOnlyTheRatingInAnotherAppsSidecar() throws {
        let lr = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
             <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about=""
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
               xmp:Rating="2"
               crs:Exposure2012="+0.35">
               <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
              </rdf:Description>
             </rdf:RDF>
            </x:xmpmeta>
            """
        #expect(XmpSidecar.read(lr) == Rating(stars: 2))
        let out = try XmpSidecar.write(lr, Rating(stars: 4, flag: .pick))
        let back = out.replacingOccurrences(of: #"xmp:Rating="4""#, with: #"xmp:Rating="2""#)
            .replacingOccurrences(
                of: #"\n\s+xmlns:rawboy="[^"]+"\n\s+rawboy:Pick="1""#, with: "", options: .regularExpression)
        #expect(back == lr)
        #expect(XmpSidecar.read(out) == Rating(stars: 4, flag: .pick))
        let unpicked = try XmpSidecar.write(out, Rating(stars: 4))
        #expect(XmpSidecar.read(unpicked) == Rating(stars: 4))
        #expect(!unpicked.contains("rawboy:Pick"))
    }

    @Test func updatesElementRatingsAndDeclaresXmpWhereMissing() throws {
        let dt =
            #"<rdf:Description rdf:about="" xmlns:darktable="http://darktable.sf.net/"><xmp:Rating>1</xmp:Rating></rdf:Description>"#
        #expect(XmpSidecar.read(try XmpSidecar.write(dt, Rating(stars: 5))) == Rating(stars: 5))
        #expect(try XmpSidecar.write(dt, Rating(stars: 5)).contains("<xmp:Rating>5</xmp:Rating>"))
        let bare = #"<rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" tiff:Make="X"/>"#
        let out = try XmpSidecar.write(bare, Rating(stars: 1))
        #expect(out.contains(#"xmlns:xmp="http://ns.adobe.com/xap/1.0/""#))
        #expect(out.hasSuffix(#"xmp:Rating="1"/>"#))
    }

    @Test func refusesTextThatIsNoSidecar() {
        #expect(throws: XmpSidecar.WriteError.notASidecar) { try XmpSidecar.write("hello", Rating(stars: 2)) }
    }
}

/// What RawBoy's own `XmpSidecar.swift` (iOS/Desktop engine) tests: the Develop and Auto fields, escaping, orientation
/// deltas and the file handling. The engine's names are the same ones here.
struct XmpSidecarEngineTests {
    private let lightroom = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
           xmp:Rating="2"
           crs:Exposure2012="+0.35">
           <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """

    @Test func engineNamesRoundTripRatings() throws {
        for r in [XmpSidecar.Rating(stars: 3), .init(stars: 0, flag: .reject), .init(stars: 5, flag: .pick)] {
            #expect(XmpSidecar.readRating(try XmpSidecar.writeRating(nil, r)) == r)
        }
        #expect(try XmpSidecar.writeRating(nil, .init(stars: 4, flag: .reject)).contains(#"xmp:Rating="-1""#))
    }

    @Test func developOnlyAddsItsOwnFieldToAnotherAppsSidecar() throws {
        let json = #"{"format":"rawboy-edit","version":1,"values":{"exposure":0.5}}"#
        let out = try XmpSidecar.writeDevelop(lightroom, json)
        #expect(XmpSidecar.readDevelop(out) == json)
        let back = out.replacingOccurrences(
            of: #"\n\s+xmlns:rawboy="[^"]+"\n\s+rawboy:Develop="[^"]*""#, with: "", options: .regularExpression)
        #expect(back == lightroom)
        #expect(XmpSidecar.readDevelop(try XmpSidecar.writeDevelop(out, nil)) == nil)
        #expect(XmpSidecar.readRating(out) == .init(stars: 2))
    }

    @Test func developReplacesInPlaceAndEscapesJson() throws {
        let first = try XmpSidecar.writeDevelop(nil, #"{"a":"x & <y> \"z\" 'q'"}"#)
        #expect(!first.contains("<y>"))
        #expect(XmpSidecar.readDevelop(first) == #"{"a":"x & <y> \"z\" 'q'"}"#)
        let second = try XmpSidecar.writeDevelop(first, "{}")
        #expect(second.components(separatedBy: "rawboy:Develop").count - 1 == 1)
        #expect(XmpSidecar.readDevelop(second) == "{}")
        // The element form (darktable writes elements) is changed in place.
        let el =
            #"<rdf:Description rdf:about=""><rawboy:Develop>{&quot;x&quot;:1}</rawboy:Develop></rdf:Description>"#
        #expect(XmpSidecar.readDevelop(el) == #"{"x":1}"#)
        #expect(
            try XmpSidecar.writeDevelop(el, "{}")
                == #"<rdf:Description rdf:about=""><rawboy:Develop>{}</rawboy:Develop></rdf:Description>"#)
        // Numeric entities and mixed-case names.
        #expect(XmpSidecar.readDevelop(#"<rdf:Description rawboy:Develop="&#65;&#x42;&AMP;&bogus;"/>"#) == "AB&&bogus;")
    }

    @Test func autoSettingsAreAFieldOfTheirOwn() throws {
        let json = #"{"format":"rawboy-auto","mode":"film"}"#
        let out = try XmpSidecar.writeAuto(lightroom, json)
        #expect(XmpSidecar.readAuto(out) == json)
        #expect(XmpSidecar.readDevelop(out) == nil)
        #expect(XmpSidecar.readAuto(try XmpSidecar.writeAuto(out, nil)) == nil)
        #expect(XmpSidecar.readAuto(lightroom) == nil)
        #expect(XmpSidecar.readAuto(#"<rdf:Description rawboy:Auto=""/>"#) == nil)
    }

    @Test func refusesTextThatIsNoSidecar() {
        #expect(throws: XmpSidecar.WriteError.notASidecar) { try XmpSidecar.writeDevelop("hello", "{}") }
        #expect(throws: XmpSidecar.WriteError.notASidecar) { try XmpSidecar.writeAuto("hello", "{}") }
    }

    @Test func orientationAndDelta() throws {
        #expect(XmpSidecar.readOrientation(try XmpSidecar.writeOrientation(nil, 6)) == 6)
        #expect(XmpSidecar.readOrientation(#"<rdf:Description tiff:Orientation="9"/>"#) == nil)
        // A sidecar saying "turned clockwise" on a photo whose file is already turned (6): up turns it back.
        #expect(ExifOrientation.delta(file: 1, sidecar: 6) == ExifOrientation(quarterTurns: 1))
        #expect(ExifOrientation.delta(file: 6, sidecar: 6) == ExifOrientation())
        #expect(ExifOrientation.delta(file: 6, sidecar: 1) == ExifOrientation(quarterTurns: 3))
        #expect(ExifOrientation.delta(file: 1, sidecar: 2) == ExifOrientation(mirrored: true))
        #expect(ExifOrientation.delta(file: 8, sidecar: 3) == ExifOrientation(quarterTurns: 3))
    }

    // MARK: Files

    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "rawboy-xmp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func sidecarChoiceFollowsTheWebsOrder() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("IMG_1.RAF")
        #expect(PhotoSidecar(photo: photo).url.lastPathComponent == "IMG_1.xmp")  // new
        try "x".write(to: dir.appendingPathComponent("IMG_1.RAF.xmp"), atomically: true, encoding: .utf8)
        #expect(PhotoSidecar(photo: photo).url.lastPathComponent == "IMG_1.RAF.xmp")  // darktable's
        try "x".write(to: dir.appendingPathComponent("img_1.XMP"), atomically: true, encoding: .utf8)
        #expect(PhotoSidecar(photo: photo).url.lastPathComponent == "img_1.XMP")  // NAME.xmp wins, any case
    }

    @Test func writeDevelopCreatesEditsAtomicallyAndKeepsTheRest() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let side = PhotoSidecar(photo: dir.appendingPathComponent("IMG_2.DNG"))
        try side.writeDevelop(nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("IMG_2.xmp").path))  // no file
        let json = #"{"format":"rawboy-edit","version":1,"values":{"contrast":5}}"#
        try side.writeDevelop(json)
        #expect(side.readDevelop() == json)
        try side.writeAuto(#"{"format":"rawboy-auto"}"#)
        #expect(side.readAuto() == #"{"format":"rawboy-auto"}"#)
        #expect(side.readDevelop() == json)
        // Another app's data in a darktable-style sidecar survives.
        try lightroom.write(to: dir.appendingPathComponent("IMG_3.DNG.xmp"), atomically: true, encoding: .utf8)
        let other = PhotoSidecar(photo: dir.appendingPathComponent("IMG_3.DNG"))
        try other.writeDevelop("{}")
        try other.writeDevelop(nil)
        let text = try #require(other.readText())
        #expect(text.contains(#"crs:Exposure2012="+0.35""#))
        #expect(text.contains("<crs:ToneCurvePV2012>"))
        // No temporary files left behind.
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["IMG_2.xmp", "IMG_3.DNG.xmp"])
    }
}

/// The sidecars in `Fixtures/Xmp`, shared with RawBoy's engine tests (`ios/EngineTests/Fixtures/Xmp`, same files and
/// same expectations): what darktable, Lightroom and RawBoy's web write must read the same in both Swift copies.
struct XmpSidecarFixtureTests {
    struct Expected {
        var rating: Rating
        var orientation: Int?
        var develop: String?
        var auto: String?
    }

    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Xmp")

    static func load() throws -> [(name: String, text: String, expected: Expected)] {
        let data = try Data(contentsOf: dir.appendingPathComponent("expected.json"))
        let all = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        return try all.keys.sorted().map { name in
            let e = all[name]!
            let flag: Flag? = (e["flag"] as? String).flatMap { Flag(rawValue: $0) }
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let expected = Expected(
                rating: Rating(stars: e["stars"] as! Int, flag: flag), orientation: e["orientation"] as? Int,
                develop: e["develop"] as? String, auto: e["auto"] as? String)
            return (name, text, expected)
        }
    }

    @Test func everyFixtureReadsAsExpected() throws {
        let fixtures = try Self.load()
        #expect(fixtures.count >= 5)
        for f in fixtures {
            #expect(XmpSidecar.readRating(f.text) == f.expected.rating, "\(f.name) rating")
            #expect(XmpSidecar.readOrientation(f.text) == f.expected.orientation, "\(f.name) orientation")
            #expect(XmpSidecar.readDevelop(f.text) == f.expected.develop, "\(f.name) develop")
            #expect(XmpSidecar.readAuto(f.text) == f.expected.auto, "\(f.name) auto")
        }
    }

    @Test func writingWhatIsThereChangesNothing() throws {
        for f in try Self.load() {
            let e = f.expected
            #expect(try XmpSidecar.writeRating(f.text, e.rating) == f.text, "\(f.name) rating")
            #expect(try XmpSidecar.writeOrientation(f.text, e.orientation) == f.text, "\(f.name) orientation")
            #expect(try XmpSidecar.writeDevelop(f.text, e.develop) == f.text, "\(f.name) develop")
            #expect(try XmpSidecar.writeAuto(f.text, e.auto) == f.text, "\(f.name) auto")
        }
    }

    @Test func aRatingChangeTouchesOnlyTheRating() throws {
        for f in try Self.load() {
            let e = f.expected
            let other = Rating(stars: e.rating.stars == 3 ? 4 : 3, flag: e.rating.flag == .reject ? nil : e.rating.flag)
            let changed = try XmpSidecar.writeRating(f.text, other)
            #expect(XmpSidecar.readRating(changed) == other, "\(f.name)")
            #expect(XmpSidecar.readOrientation(changed) == e.orientation, "\(f.name)")
            #expect(XmpSidecar.readDevelop(changed) == e.develop, "\(f.name)")
            #expect(XmpSidecar.readAuto(changed) == e.auto, "\(f.name)")
            #expect(try XmpSidecar.writeRating(changed, e.rating) == f.text, "\(f.name) back")
        }
    }

    @Test func developAndAutoWrittenIntoAnotherAppsSidecarLeaveTheRestAlone() throws {
        let json = #"{"format":"rawboy-edit","version":1,"values":{"exposure":0.5}}"#
        for f in try Self.load() where f.expected.develop == nil && f.expected.auto == nil {
            let out = try XmpSidecar.writeAuto(XmpSidecar.writeDevelop(f.text, json), "{}")
            #expect(XmpSidecar.readDevelop(out) == json, "\(f.name)")
            #expect(XmpSidecar.readRating(out) == f.expected.rating, "\(f.name)")
            let back = out.replacingOccurrences(
                of: #"\n\s+(rawboy:(Develop|Auto)|xmlns:rawboy)="[^"]*""#, with: "", options: .regularExpression)
            #expect(back == f.text, "\(f.name)")
            #expect(try XmpSidecar.writeDevelop(out, nil).contains("rawboy:Develop") == false, "\(f.name)")
        }
    }

    @Test func geometryOfAWebWrittenSidecarKeepsEveryOtherKeyByteForByte() throws {
        let web = try #require(try Self.load().first { $0.name == "web-develop.xmp" })
        let json = try #require(XmpSidecar.readDevelop(web.text))
        var g = try #require(DevelopEdits.geometry(json))
        #expect(g.rotation == 1 && g.crop == CropRect(left: 0.1, top: 0.05, right: 0.9, bottom: 0.8))
        // Writing what is there changes nothing.
        #expect(DevelopEdits.write(json, g) == json)
        // A new crop and turn: the other keys, in the sidecar too, are the same bytes.
        g.rotation = 3
        g.mirrored = true
        g.crop = CropRect(left: 0.2, top: 0, right: 1, bottom: 0.7)
        let out = try #require(DevelopEdits.write(json, g))
        #expect(DevelopEdits.geometry(out) == g)
        let kept = [
            #""toneMapper":"filmic","exposure":0.7,"#,
            #""masks":[{"name":"Sky & <sea>","enabled":true,"opacity":100,"invert":false,"shape":{"kind":"brush"},"strokes":[{"erase":false,"auto":true,"radius":0.04,"hardness":60,"flow":80,"points":[0.12346,0.2,0.33333,0.4,0.5,0.6]},{"erase":true,"radius":1e-7,"points":[0.30000000000000004,1.0]}]}],"#,
            #""healSpots":[{"x":0.4,"y":0.5,"radius":0.0004,"source":null,"path":[]}],"#,
            #""lut":"portra400""#,
        ]
        for k in kept { #expect(out.contains(k), "\(k)") }
        #expect(out.hasPrefix(#"{"format":"rawboy-edit","version":1,"values":{"#))
        // Taking the geometry away leaves exactly the other keys.
        let bare = try #require(DevelopEdits.write(out, DevelopGeometry()))
        for k in kept { #expect(bare.contains(k), "\(k)") }
        for key in ["rotation", "flipHorizontal", "crop"] { #expect(!bare.contains(key), "\(key)") }
        #expect(DevelopEdits.geometry(bare) == DevelopGeometry())
        // And through the sidecar text, the rest of the sidecar is untouched too.
        let text = try XmpSidecar.writeDevelop(web.text, out)
        #expect(XmpSidecar.readDevelop(text) == out)
        #expect(XmpSidecar.readAuto(text) == web.expected.auto)
        #expect(XmpSidecar.readRating(text) == web.expected.rating)
    }
}

struct RatingTests {
    @Test func starsSetOrClearTogetherAndUnreject() {
        let rs = [Rating(stars: 3), Rating(stars: 1, flag: .reject)]
        #expect(Rating.withStars(rs, 3) == [Rating(stars: 3), Rating(stars: 3)])
        #expect(Rating.withStars([Rating(stars: 3), Rating(stars: 3)], 3) == [Rating(), Rating()])
    }

    @Test func flagsSetOrClearTogether() {
        let rs = [Rating(flag: .pick), Rating()]
        #expect(Rating.withFlag(rs, .pick) == [Rating(flag: .pick), Rating(flag: .pick)])
        #expect(Rating.withFlag([Rating(flag: .pick)], .pick) == [Rating()])
        #expect(Rating.withFlag([Rating(stars: 2, flag: .pick)], .reject) == [Rating(stars: 2, flag: .reject)])
    }

    @Test func filters() {
        #expect(FlagFilter.picks.passes(Rating(stars: 3, flag: .pick), minStars: 2))
        #expect(!FlagFilter.picks.passes(Rating(stars: 1, flag: .pick), minStars: 2))
        #expect(FlagFilter.unflagged.passes(Rating(), minStars: 0))
        #expect(!FlagFilter.rejects.passes(Rating(flag: .pick), minStars: 0))
    }

    @Test func flagCounts() {
        let rs = [
            Rating(stars: 3, flag: .pick), Rating(), Rating(stars: 1), Rating(flag: .reject), Rating(flag: .pick),
        ]
        let counts = FlagFilter.counts(rs)
        #expect(counts[.all] == 5)
        #expect(counts[.picks] == 2)
        #expect(counts[.unflagged] == 2)
        #expect(counts[.rejects] == 1)
        #expect(FlagFilter.counts([])[.picks] == 0)
    }

    @Test func suffixKeepsSidecarsMatched() {
        #expect(PhotoGroups.withSuffix("IMG_1.CR2.xmp", stem: "IMG_1", suffix: "-2") == "IMG_1-2.CR2.xmp")
        #expect(PhotoGroups.withSuffix("img_1.jpg", stem: "IMG_1", suffix: "-1") == "img_1-1.jpg")
        #expect(PhotoGroups.withSuffix("other.xmp", stem: "IMG_1", suffix: "-1") == "other-1.xmp")
    }
}
