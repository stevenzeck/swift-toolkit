//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import Testing
@testable import ReadiumShared

@Suite("HTTPResponse")
struct HTTPResponseTests {
    private let request = HTTPRequest(url: HTTPURL(string: "http://example.com")!)
    private let url = HTTPURL(string: "http://example.com")!

    @Test func valueForHeader() {
        let response = HTTPResponse(
            request: request,
            url: url,
            status: .ok,
            headers: ["Content-Type": "application/pdf", "X-Custom": "Value"],
            mediaType: .pdf,
            body: nil
        )

        #expect(response.valueForHeader("Content-Type") == "application/pdf")
        #expect(response.valueForHeader("content-type") == "application/pdf")
        #expect(response.valueForHeader("X-Custom") == "Value")
        #expect(response.valueForHeader("Unknown") == nil)
    }

    @Test func acceptsByteRanges() {
        var response = HTTPResponse(request: request, url: url, status: .ok, headers: ["Accept-Ranges": "bytes"], mediaType: nil, body: nil)
        #expect(response.acceptsByteRanges)

        response = HTTPResponse(request: request, url: url, status: .ok, headers: ["Content-Range": "bytes 0-100/1000"], mediaType: nil, body: nil)
        #expect(response.acceptsByteRanges)

        response = HTTPResponse(request: request, url: url, status: .ok, headers: [:], mediaType: nil, body: nil)
        #expect(!response.acceptsByteRanges)
    }

    @Test func contentLength() {
        let response = HTTPResponse(request: request, url: url, status: .ok, headers: ["Content-Length": "1024"], mediaType: nil, body: nil)
        #expect(response.contentLength == 1024)

        let responseInvalid = HTTPResponse(request: request, url: url, status: .ok, headers: ["Content-Length": "invalid"], mediaType: nil, body: nil)
        #expect(responseInvalid.contentLength == nil)
    }

    @Test func filename() {
        var response = HTTPResponse(request: request, url: url, status: .ok, headers: ["Content-Disposition": "attachment; filename=book.epub"], mediaType: nil, body: nil)
        #expect(response.filename == "book.epub")

        response = HTTPResponse(request: request, url: url, status: .ok, headers: ["Content-Disposition": "filename=image.png"], mediaType: nil, body: nil)
        #expect(response.filename == "image.png")

        response = HTTPResponse(request: request, url: url, status: .ok, headers: ["Content-Disposition": "inline"], mediaType: nil, body: nil)
        #expect(response.filename == nil)
    }
}
