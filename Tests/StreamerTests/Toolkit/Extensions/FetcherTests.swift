//
//  Copyright 2024 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
@testable import ReadiumStreamer
import XCTest

class FetcherTests: XCTestCase {
    func testGuessTitleWithoutDirectories() {
        let fetcher = TestFetcher(hrefs: ["a.txt", "b.png"])
        XCTAssertNil(fetcher.guessTitle())
    }

    func testGuessTitleWithOneRootDirectory() {
        let fetcher = TestFetcher(hrefs: ["Root%20Directory/b.png", "Root%20Directory/dir/c.png"])
        XCTAssertEqual(fetcher.guessTitle(), "Root Directory")
    }

    func testGuessTitleWithOneRootDirectoryButRootFiles() {
        let fetcher = TestFetcher(hrefs: ["a.txt", "Root%20Directory/b.png", "Root%20Directory/dir/c.png"])
        XCTAssertNil(fetcher.guessTitle())
    }

    func testGuessTitleWithOneRootDirectoryButRootFilesWithIgnore() {
        let fetcher = TestFetcher(hrefs: [".hidden", "Root%20Directory/b.png", "Root%20Directory/dir/c.png"])
        XCTAssertEqual(fetcher.guessTitle(ignoring: { $0.href == ".hidden" }), "Root Directory")
    }

    func testGuessTitleWithSeveralDirectories() {
        let fetcher = TestFetcher(hrefs: ["a.txt", "dir1/b.png", "dir2/c.png"])
        XCTAssertNil(fetcher.guessTitle())
    }

    func testGuessTitleIgnoresSingleFiles() {
        let fetcher = TestFetcher(hrefs: ["single"])
        XCTAssertNil(fetcher.guessTitle())
    }
}

private struct TestFetcher: Fetcher {
    init(hrefs: [String]) {
        links = hrefs.map { Link(href: $0) }
    }

    var links: [Link]

    func get(_ link: Link) -> Resource {
        fatalError()
    }

    func close() {}
}
