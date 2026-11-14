import Foundation
import RawBoyBrowseKit
import Testing

/// The cases of RawBoy's engine.test.ts crop tests, and its edits format.
struct CropMathTests {
    func close(_ a: CropRect, _ b: [Double], _ tol: Double = 1e-9) -> Bool {
        zip([a.left, a.top, a.right, a.bottom], b).allSatisfy { abs($0 - $1) <= tol }
    }

    @Test func turnsWithThePicture() {
        let r = CropRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.6)
        #expect(close(CropMath.rotate(r, quarterTurns: 1), [0.4, 0.1, 0.8, 0.5]))
        #expect(CropMath.rotate(r, quarterTurns: 4) == r)
        #expect(close(CropMath.rotate(CropMath.rotate(r, quarterTurns: 1), quarterTurns: -1), [0.1, 0.2, 0.5, 0.6]))
    }

    @Test func aspects() {
        #expect([CropAspect.twoOne.label(portrait: false), CropAspect.twoOne.label(portrait: true)] == ["2:1", "1:2"])
        #expect(CropAspect.scope.label(portrait: true) == "1:2.39")
        #expect(abs(CropAspect.twoOne.ratio(frameWidth: 6000, frameHeight: 4000, portrait: true)! - 0.5) < 1e-9)
        let scope = CropMath.withAspect(.full, ratio: 2.39, frameWidth: 6000, frameHeight: 4000)
        #expect(abs(scope.left) < 1e-6 && abs(scope.right - 1) < 1e-6)
        #expect(abs(scope.width * 6000 / (scope.height * 4000) - 2.39) < 1e-5)
    }

    @Test func dragging() {
        let r = CropMath.withAspect(.full, ratio: 1, frameWidth: 6000, frameHeight: 4000)
        #expect(abs(r.width * 6000 / (r.height * 4000) - 1) < 1e-6)
        let d = CropMath.drag(r, .bottomRight, dx: -0.1, dy: 0.3, ratio: 1, frameWidth: 6000, frameHeight: 4000)
        #expect(abs(d.width * 6000 / (d.height * 4000) - 1) < 1e-6)
        #expect(d.bottom <= 1)
        let m = CropMath.drag(
            CropRect(left: 0.2, top: 0.2, right: 0.4, bottom: 0.4), .move, dx: 0.9, dy: -0.5, ratio: nil,
            frameWidth: 6000, frameHeight: 4000)
        #expect(close(m, [0.8, 0, 1, 0.2], 1e-6))
        let free = CropMath.drag(.full, .left, dx: 0.25, dy: 0, ratio: nil, frameWidth: 6000, frameHeight: 4000)
        #expect(close(free, [0.25, 0, 1, 1], 1e-6))
        #expect(CropMath.handle(at: .full, x: 0.01, y: 0.99, tolX: 0.02, tolY: 0.02) == .bottomLeft)
        #expect(CropMath.handle(at: .full, x: 0.5, y: 0.5, tolX: 0.02, tolY: 0.02) == .move)
        #expect(
            CropMath.handle(
                at: CropRect(left: 0.2, top: 0.2, right: 0.4, bottom: 0.4), x: 0.9, y: 0.9, tolX: 0.02, tolY: 0.02)
                == nil)
    }
}

struct DevelopEditsTests {
    @Test func geometryRoundTripsAndKeepsOtherEdits() throws {
        let rawboy = #"{"format":"rawboy-edit","version":1,"values":{"exposure":0.7,"rotation":1}}"#
        let g = try #require(DevelopEdits.geometry(rawboy))
        #expect(g.rotation == 1 && !g.mirrored && g.crop.isFull)
        var edited = g
        edited.crop = CropRect(left: 0.1, top: 0, right: 0.9, bottom: 0.8)
        let out = try #require(DevelopEdits.write(rawboy, edited))
        let values = try #require(
            (try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])?["values"] as? [String: Any])
        #expect(values["exposure"] as? Double == 0.7)
        #expect(values["cropLeft"] as? Double == 0.1)
        #expect(values["cropTop"] == nil)
        #expect(DevelopEdits.geometry(out)?.crop == edited.crop)
        #expect(out.contains(#""cropLeft":0.1,"#))
        #expect(!out.contains("0000000"))
    }

    @Test func noEditsLeftMeansNoJson() {
        #expect(DevelopEdits.write(nil, DevelopGeometry()) == nil)
        #expect(
            DevelopEdits.write(#"{"format":"rawboy-edit","version":1,"values":{"rotation":2}}"#, DevelopGeometry())
                == nil)
        #expect(DevelopEdits.geometry(#"{"format":"other"}"#) == nil)
    }

    @Test func flipVerticalIsAMirrorAndAHalfTurn() throws {
        let g = try #require(
            DevelopEdits.geometry(#"{"format":"rawboy-edit","version":1,"values":{"flipVertical":true}}"#))
        #expect(g.mirrored && g.rotation == 2)
        #expect(
            DevelopEdits.geometry(#"{"format":"rawboy-edit","version":1,"values":{"straighten":1.5}}"#)?
                .isStraightened == true)
    }

    @Test func sidecarKeepsTheJsonEscaped() throws {
        let json = #"{"format":"rawboy-edit","version":1,"values":{"name":"a<b & \"c\""}}"#
        let text = try XmpSidecar.writeDevelop(nil, json)
        #expect(!text.contains("a<b"))
        #expect(XmpSidecar.readDevelop(text) == json)
        #expect(XmpSidecar.readDevelop(try XmpSidecar.writeDevelop(text, nil)) == nil)
    }
}
