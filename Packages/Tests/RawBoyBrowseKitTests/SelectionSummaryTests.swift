import Foundation
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

    @Test func sizeIsShownWhenFilesAreSelected() {
        let one = ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file)
        let three = ByteCountFormatter.string(fromByteCount: 48_200_000, countStyle: .file)
        #expect(SelectionSummary.text(files: 1, folders: 0, bytes: 1_500_000) == "1 file selected · \(one)")
        #expect(SelectionSummary.text(files: 3, folders: 0, bytes: 48_200_000) == "3 files selected · \(three)")
        #expect(
            SelectionSummary.text(files: 3, folders: 1, bytes: 48_200_000)
                == "3 files, 1 folder selected · \(three)")
        #expect(SelectionSummary.text(files: 0, folders: 0, bytes: 0) == "0 files selected")
        #expect(SelectionSummary.text(files: 0, folders: 2, bytes: 1_500_000) == "2 folders selected")
        #expect(SelectionSummary.text(files: 2, folders: 0, bytes: nil) == "2 files selected")
    }
}
