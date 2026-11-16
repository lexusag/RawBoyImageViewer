import Foundation
import Testing

@testable import RawBoyBrowseKit

@Suite struct AutoImportTests {
    @Test func linkCarriesTheModeAndEveryPath() throws {
        let link = try #require(AutoImport.film.link(["/Photos/a b.RAF", "/Photos/Day & night"]))
        #expect(link.scheme == "rawboy-desktop")
        #expect(link.host == "auto")
        let items = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first == URLQueryItem(name: "as", value: "film"))
        #expect(items.filter { $0.name == "path" }.compactMap(\.value) == ["/Photos/a b.RAF", "/Photos/Day & night"])
    }

    @Test func rawValuesMatchRawBoyDesktop() {
        // RawBoy Desktop's ImportMode: looks, film, plain.
        #expect(AutoImport.allCases.map(\.rawValue) == ["looks", "film", "plain"])
        #expect(AutoImport.allCases.map(\.label) == ["Looks", "Film", "As is"])
    }
}
