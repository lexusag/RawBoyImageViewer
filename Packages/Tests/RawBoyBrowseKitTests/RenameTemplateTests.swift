import RawBoyBrowseKit
import Testing

struct RenameTemplateTests {
    private let ctx = RenameContext(
        fileName: "IMG_1234.CR2", camera: "Canon EOS R5", lens: nil, iso: 400, date: "2026:11:11 14:30:05",
        folder: "Trip", index: 7)

    @Test func hashesAreZeroPaddedCounters() {
        #expect(RenameTemplate.apply("#", ctx) == "7")
        #expect(RenameTemplate.apply("##", ctx) == "07")
        #expect(RenameTemplate.apply("###", ctx) == "007")
        #expect(RenameTemplate.apply("a_###_b_#", ctx) == "a_007_b_7")
    }

    @Test func counterWiderThanItsHashesIsNotCut() {
        var c = ctx
        c.index = 1234
        #expect(RenameTemplate.apply("##", c) == "1234")
    }

    @Test func keywordsAreCaseInsensitive() {
        #expect(RenameTemplate.apply("{NAME}-{Iso}", ctx) == "IMG_1234-400")
        #expect(RenameTemplate.apply("{camera} {folder}", ctx) == "Canon EOS R5 Trip")
    }

    @Test func dateKeywords() {
        #expect(RenameTemplate.apply("{date}_{time}", ctx) == "2026-11-11_14-30-05")
        #expect(RenameTemplate.apply("{yy}{month}{day}-{hour}{minute}{second}", ctx) == "261111-143005")
    }

    @Test func missingValuesAreLeftOutAndUnknownWordsStay() {
        #expect(RenameTemplate.apply("a{lens}b", ctx) == "ab")
        #expect(RenameTemplate.apply("{nmae}", ctx) == "{nmae}")
        var c = ctx
        c.date = nil
        #expect(RenameTemplate.apply("x{date}y", c) == "xy")
    }

    @Test func illegalCharactersBecomeUnderscores() {
        #expect(RenameTemplate.apply("a/b:c", ctx) == "a_b_c")
        #expect(RenameTemplate.sanitize("  .name. ") == "name")
        #expect(RenameTemplate.sanitize("CON") == "_CON")
    }

    @Test func literalNamesKeepHashesAndBraces() {
        #expect(RenameTemplate.apply("Shot #3 {a}", ctx, literal: true) == "Shot #3 {a}")
        #expect(RenameTemplate.apply("a/b", ctx, literal: true) == "a_b")
    }

    @Test func emptyTemplateMeansOriginalName() {
        #expect(RenameTemplate.apply("  ", ctx) == "IMG_1234")
    }

    @Test func nothingLeftIsEmpty() {
        #expect(RenameTemplate.apply("{lens}", ctx) == "")
    }
}

struct RenamePlanTests {
    private func photo(_ files: [String], sidecars: [String] = []) -> (group: PhotoGroup, context: RenameContext) {
        let group = PhotoGroups.group(files + sidecars)[0]
        return (group, RenameContext(fileName: group.main))
    }

    @Test func numbersInOrderFromStart() {
        let items = RenamePlan.make(
            photos: [photo(["A.CR2"]), photo(["B.CR2"])], template: "trip_###", start: 8,
            existing: ["A.CR2", "B.CR2"])
        #expect(items.map(\.newMain) == ["trip_008.CR2", "trip_009.CR2"])
        #expect(RenamePlan.canApply(items))
    }

    @Test func companionsAndSidecarsFollow() {
        let items = RenamePlan.make(
            photos: [photo(["IMG_1.CR2", "IMG_1.JPG"], sidecars: ["IMG_1.CR2.xmp", "IMG_1.xmp", "IMG_1_01.CR2.xmp"])],
            template: "x", start: 1, existing: [])
        #expect(
            items[0].files.map(\.new) == ["x.CR2", "x.JPG", "x.CR2.xmp", "x.xmp", "x_01.CR2.xmp"])
    }

    @Test func takenNameBlocks() {
        let items = RenamePlan.make(
            photos: [photo(["A.CR2"])], template: "B", start: 1, existing: ["A.CR2", "B.CR2"])
        #expect(items[0].status == .conflict("B.CR2 already exists"))
        #expect(!RenamePlan.canApply(items))
    }

    @Test func sameNameForTwoPhotosBlocks() {
        let items = RenamePlan.make(
            photos: [photo(["A.CR2"]), photo(["B.CR2"])], template: "same", start: 1, existing: ["A.CR2", "B.CR2"])
        #expect(items.allSatisfy { $0.status == .conflict("Same name as another photo") })
    }

    @Test func shiftingNamesWithinTheSelectionIsFine() {
        // 1 → 2 and 2 → 3: 2 is taken, but by a photo that moves away.
        let items = RenamePlan.make(
            photos: [photo(["P1.CR2"]), photo(["P2.CR2"])], template: "P#", start: 2, existing: ["P1.CR2", "P2.CR2"])
        #expect(items.map(\.newMain) == ["P2.CR2", "P3.CR2"])
        #expect(RenamePlan.canApply(items))
    }

    @Test func caseOnlyChangeIsAllowed() {
        let items = RenamePlan.make(
            photos: [photo(["img_1.cr2"])], template: "IMG_1", start: 1, existing: ["img_1.cr2"])
        #expect(items[0].status == .ok)
    }

    @Test func unchangedAndEmpty() {
        let items = RenamePlan.make(
            photos: [photo(["A.CR2"])], template: "{name}", start: 1, existing: ["A.CR2"])
        #expect(items[0].status == .unchanged)
        #expect(!RenamePlan.canApply(items))
        let empty = RenamePlan.make(photos: [photo(["A.CR2"])], template: "{lens}", start: 1, existing: ["A.CR2"])
        #expect(empty[0].status == .conflict("Empty name"))
    }

    @Test func plainReplaceIsCaseInsensitiveUnlessAsked() {
        var r = RenameReplace(find: "img", replace: "Trip")
        #expect(r.apply("IMG_1 img_2") == "Trip_1 Trip_2")
        r.caseSensitive = true
        #expect(r.apply("IMG_1 img_2") == "IMG_1 Trip_2")
    }

    @Test func plainReplaceTakesRegexCharactersLiterally() {
        let r = RenameReplace(find: "(1)", replace: "$1")
        #expect(r.apply("a(1)b") == "a$1b")
        #expect(r.error == nil)
    }

    @Test func regexReplaceUsesGroups() {
        let r = RenameReplace(find: #"IMG_(\d+)"#, replace: "Trip-$1", regex: true)
        #expect(r.apply("IMG_0042") == "Trip-0042")
    }

    @Test func invalidRegexIsReportedAndChangesNothing() {
        let r = RenameReplace(find: "(", replace: "x", regex: true)
        #expect(r.error != nil)
        #expect(r.apply("a(b") == "a(b")
        // Plain text may hold the same characters.
        #expect(RenameReplace(find: "(", replace: "x").error == nil)
    }

    @Test func emptyFindDoesNothing() {
        #expect(!RenameReplace(find: "", replace: "x").isActive)
        #expect(RenameReplace(find: "", replace: "x").apply("abc") == "abc")
    }

    @Test func replaceOnTheResultOrOnTheOriginalName() {
        let result = RenamePlan.make(
            photos: [photo(["IMG_1.CR2"])], template: "{name}_{date}", start: 1, existing: [],
            replace: RenameReplace(find: "IMG", replace: "Trip", target: .result))
        #expect(result[0].newMain == "Trip_1_.CR2")
        // On the original name only: the template's own text is left alone.
        let original = RenamePlan.make(
            photos: [photo(["IMG_1.CR2"])], template: "IMG-{name}", start: 1, existing: [],
            replace: RenameReplace(find: "IMG", replace: "Trip", target: .original))
        #expect(original[0].newMain == "IMG-Trip_1.CR2")
    }

    @Test func replacedOriginalNameKeepsDotsInTheStem() {
        let items = RenamePlan.make(
            photos: [photo(["IMG_1.CR2"])], template: "{name}", start: 1, existing: [],
            replace: RenameReplace(find: "IMG_", replace: "v1.2-", target: .original))
        #expect(items[0].newMain == "v1.2-1.CR2")
    }

    @Test func replaceCombinesWithNumbersAndStillBlocksCollisions() {
        let items = RenamePlan.make(
            photos: [photo(["A1.CR2"]), photo(["A2.CR2"])], template: "{name}", start: 1, existing: [],
            replace: RenameReplace(find: #"\d"#, replace: "", regex: true))
        #expect(items.allSatisfy { $0.status == .conflict("Same name as another photo") })
        let single = RenamePlan.make(
            photos: [photo(["A1.CR2"])], template: "A1", start: 1, existing: ["A1.CR2"], literal: true,
            replace: RenameReplace(find: "A", replace: "B"))
        #expect(single[0].newMain == "B1.CR2")
    }

    @Test func badRegexLeavesThePlanAlone() {
        let items = RenamePlan.make(
            photos: [photo(["A.CR2"])], template: "x", start: 1, existing: [],
            replace: RenameReplace(find: "[", replace: "y", regex: true))
        #expect(items[0].newMain == "x.CR2")
    }

    @Test func replaceResultIsSanitised() {
        let items = RenamePlan.make(
            photos: [photo(["A.CR2"])], template: "a-b", start: 1, existing: [],
            replace: RenameReplace(find: "-", replace: "/"))
        #expect(items[0].newMain == "a_b.CR2")
    }
}
