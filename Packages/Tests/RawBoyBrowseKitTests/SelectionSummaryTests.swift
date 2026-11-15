import Testing

@testable import RawBoyBrowseKit

struct SelectionSummaryTests {
    @Test func filesOnly() {
        #expect(SelectionSummary.text(files: 0, folders: 0) == "0 files selected")
        #expect(SelectionSummary.text(files: 1, folders: 0) == "1 file selected")
        #expect(SelectionSummary.text(files: 3, folders: 0) == "3 files selected")
    }

    @Test func foldersAreNamedOnlyWhenSelected() {
        #expect(SelectionSummary.text(files: 3, folders: 1) == "3 files, 1 folder selected")
        #expect(SelectionSummary.text(files: 1, folders: 2) == "1 file, 2 folders selected")
        #expect(SelectionSummary.text(files: 0, folders: 2) == "2 folders selected")
    }
}
