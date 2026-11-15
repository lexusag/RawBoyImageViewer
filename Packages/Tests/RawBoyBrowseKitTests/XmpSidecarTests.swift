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
