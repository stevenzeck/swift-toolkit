//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import Testing
@testable import ReadiumShared

@Suite("HTTPResource")
struct HTTPResourceTests {
    private let url = HTTPURL(string: "http://example.com/book.epub")!

    class MockHTTPClient: HTTPClient {
        var fetchResults: [String: HTTPResult<HTTPResponse>] = [:]
        var fetchCount = 0

        func stream(
            request: HTTPRequestConvertible,
            consume: @escaping (Data, Double?) -> HTTPResult<Void>
        ) async -> HTTPResult<HTTPResponse> {
            let req = try! request.httpRequest().get()
            let key = "\(req.method.rawValue) \(req.url.string)"
            fetchCount += 1
            
            if let result = fetchResults[key] {
                if case let .success(response) = result, let body = response.body {
                    _ = consume(body, 1.0)
                }
                return result
            }
            return .failure(.cancelled)
        }
    }

    @Test func headResponseIsCached() async throws {
        let client = MockHTTPClient()
        let resource = HTTPResource(url: url, client: client)
        
        client.fetchResults["HEAD \(url.string)"] = .success(HTTPResponse(
            request: HTTPRequest(url: url),
            url: url,
            status: .ok,
            headers: ["Content-Length": "1024"],
            mediaType: .epub,
            body: nil
        ))

        let length1 = await resource.estimatedLength()
        try #expect(length1.get() == 1024)
        #expect(client.fetchCount == 1)

        let length2 = await resource.estimatedLength()
        try #expect(length2.get() == 1024)
        #expect(client.fetchCount == 1) // Should be cached
    }

    @Test func headResponseFallbackOnMethodNotAllowed() async throws {
        let client = MockHTTPClient()
        let resource = HTTPResource(url: url, client: client)
        
        let response = HTTPResponse(
            request: HTTPRequest(url: url, method: .head),
            url: url,
            status: .methodNotAllowed,
            headers: [:],
            mediaType: nil,
            body: nil
        )
        client.fetchResults["HEAD \(url.string)"] = .failure(.errorResponse(response))

        let length = await resource.estimatedLength()
        try #expect(length.get() == nil)
        #expect(client.fetchCount == 1)
    }

    @Test func streamWithRange() async throws {
        let client = MockHTTPClient()
        let resource = HTTPResource(url: url, client: client)
        
        client.fetchResults["GET \(url.string)"] = .success(HTTPResponse(
            request: HTTPRequest(url: url),
            url: url,
            status: .partialContent,
            headers: ["Content-Range": "bytes 0-9/100"],
            mediaType: .epub,
            body: "0123456789".data(using: .utf8)
        ))

        var streamedData = Data()
        let result = await resource.stream(range: 0..<10, consume: { streamedData.append($0) })
        
        try result.get()
        #expect(streamedData == "0123456789".data(using: .utf8))
    }
}
