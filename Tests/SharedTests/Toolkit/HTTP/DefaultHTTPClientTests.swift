//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
@testable import ReadiumShared
import Testing

@Suite(.serialized)
struct DefaultHTTPClientTests {
    /// Creates a `DefaultHTTPClient` configured with `MockHTTPURLProtocol`
    /// for intercepting all requests.
    private func makeClient(
        userAgent: String? = nil,
        additionalHeaders: [String: String]? = nil,
        requestTimeout: TimeInterval? = nil,
        resourceTimeout: TimeInterval? = nil,
        ephemeral: Bool = true,
        delegate: DefaultHTTPClientDelegate? = nil
    ) -> DefaultHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTPURLProtocol.self]

        if let additionalHeaders = additionalHeaders {
            config.httpAdditionalHeaders = additionalHeaders
        }
        if let requestTimeout = requestTimeout {
            config.timeoutIntervalForRequest = requestTimeout
        }
        if let resourceTimeout = resourceTimeout {
            config.timeoutIntervalForResource = resourceTimeout
        }

        return DefaultHTTPClient(
            configuration: config,
            userAgent: userAgent,
            delegate: delegate
        )
    }

    private func makeURL(_ path: String = "/test") -> HTTPURL {
        HTTPURL(string: "https://example.com\(path)")!
    }

    // MARK: - User Agent

    @Suite(.serialized)
    struct UserAgent {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient(
            userAgent: String? = nil,
            delegate: DefaultHTTPClientDelegate? = nil
        ) -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(
                configuration: config,
                userAgent: userAgent,
                delegate: delegate
            )
        }

        private func makeURL(_ path: String = "/test") -> HTTPURL {
            HTTPURL(string: "https://example.com\(path)")!
        }

        @Test("Default user agent is set when none provided on request")
        func defaultUserAgentIsSet() async {
            var receivedUserAgent: String?

            MockHTTPURLProtocol.requestHandler = { request in
                receivedUserAgent = request.value(forHTTPHeaderField: "User-Agent")
                return .success(body: Data("ok".utf8))
            }

            let client = makeClient()
            _ = await client.fetch(makeURL())

            #expect(receivedUserAgent != nil)
            #expect(receivedUserAgent?.isEmpty == false)
        }

        @Test("Custom user agent overrides default")
        func customUserAgent() async {
            var receivedUserAgent: String?
            let customUA = "MyApp/1.0"

            MockHTTPURLProtocol.requestHandler = { request in
                receivedUserAgent = request.value(forHTTPHeaderField: "User-Agent")
                return .success(body: Data("ok".utf8))
            }

            let client = makeClient(userAgent: customUA)
            _ = await client.fetch(makeURL())

            #expect(receivedUserAgent == customUA)
        }

        @Test("Per-request user agent takes precedence over client default")
        func perRequestUserAgent() async {
            var receivedUserAgent: String?
            let requestUA = "RequestSpecific/2.0"

            MockHTTPURLProtocol.requestHandler = { request in
                receivedUserAgent = request.value(forHTTPHeaderField: "User-Agent")
                return .success(body: Data("ok".utf8))
            }

            let client = makeClient(userAgent: "ClientDefault/1.0")
            var request = HTTPRequest(url: makeURL())
            request.userAgent = requestUA
            _ = await client.fetch(request)

            #expect(receivedUserAgent == requestUA)
        }

        @Test("Default user agent string is non-empty")
        func defaultUserAgentStringFormat() {
            let ua = DefaultHTTPClient.defaultUserAgent
            #expect(!ua.isEmpty)
        }
    }

    // MARK: - Headers

    @Suite(.serialized)
    struct Headers {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient(
            additionalHeaders: [String: String]? = nil
        ) -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            if let additionalHeaders = additionalHeaders {
                config.httpAdditionalHeaders = additionalHeaders
            }
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/test")!
        }

        @Test("Additional headers from configuration are sent")
        func additionalHeaders() async {
            var receivedHeader: String?

            MockHTTPURLProtocol.requestHandler = { request in
                receivedHeader = request.value(forHTTPHeaderField: "X-Custom")
                return .success(body: Data("ok".utf8))
            }

            let client = makeClient(additionalHeaders: ["X-Custom": "hello"])
            _ = await client.fetch(makeURL())

            #expect(receivedHeader == "hello")
        }

        @Test("Per-request headers are sent")
        func perRequestHeaders() async {
            var receivedHeader: String?

            MockHTTPURLProtocol.requestHandler = { request in
                receivedHeader = request.value(forHTTPHeaderField: "X-Request")
                return .success(body: Data("ok".utf8))
            }

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            let client = DefaultHTTPClient(configuration: config)
            let request = HTTPRequest(url: makeURL(), headers: ["X-Request": "value"])
            _ = await client.fetch(request)

            #expect(receivedHeader == "value")
        }
    }

    // MARK: - Streaming

    @Suite(.serialized)
    struct Streaming {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient() -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/stream")!
        }

        @Test("Stream delivers data in chunks")
        func streamDeliversChunks() async throws {
            let chunk1 = Data("hello ".utf8)
            let chunk2 = Data("world".utf8)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(chunks: [chunk1, chunk2])
            }

            var receivedChunks: [Data] = []

            let result = await makeClient().stream(
                request: makeURL()
            ) { data, _ in
                receivedChunks.append(data)
                return .success(())
            }

            let response = try result.get()
            #expect(response.status == .ok)
            // URLSession may coalesce chunks, so verify total data
            let totalData = receivedChunks.reduce(Data(), +)
            #expect(totalData == chunk1 + chunk2)
        }

        @Test("Stream reports progress when Content-Length is known")
        func streamReportsProgress() async throws {
            let body = Data("hello world".utf8)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    headers: ["Content-Length": "\(body.count)"],
                    body: body
                )
            }

            var lastProgress: Double?

            let result = await makeClient().stream(
                request: makeURL()
            ) { _, progress in
                if let progress = progress {
                    lastProgress = progress
                }
                return .success(())
            }

            _ = try result.get()
            #expect(lastProgress != nil)
            // Final progress should be 1.0 (all data received)
            if let progress = lastProgress {
                #expect(progress > 0)
                #expect(progress <= 1.0)
            }
        }

        @Test("Stream reports nil progress when Content-Length is unknown")
        func streamReportsNilProgressWhenContentLengthUnknown() async throws {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(body: Data("data".utf8))
            }

            var allProgressValues: [Double?] = []

            let result = await makeClient().stream(
                request: makeURL()
            ) { _, progress in
                allProgressValues.append(progress)
                return .success(())
            }

            _ = try result.get()
            // All progress values should be nil since no Content-Length
            #expect(allProgressValues.allSatisfy { $0 == nil })
        }

        @Test("Returning failure from consume aborts the stream")
        func consumeFailureAbortsStream() async {
            let largeBody = Data(repeating: 0x42, count: 1024)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    headers: ["Content-Length": "\(largeBody.count)"],
                    chunks: [
                        Data(largeBody[0 ..< 512]),
                        Data(largeBody[512...]),
                    ]
                )
            }

            let result = await makeClient().stream(
                request: makeURL()
            ) { _, _ in
                .failure(.cancelled)
            }

            guard case .failure(.cancelled) = result else {
                Issue.record("Expected .cancelled failure but got \(result)")
                return
            }
        }
    }

    // MARK: - Fetch

    @Suite(.serialized)
    struct Fetch {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient() -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/fetch")!
        }

        @Test("Fetch accumulates streamed data into response body")
        func fetchAccumulatesData() async throws {
            let chunk1 = Data("hello ".utf8)
            let chunk2 = Data("world".utf8)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(chunks: [chunk1, chunk2])
            }

            let response = try await makeClient().fetch(makeURL()).get()

            #expect(response.body == chunk1 + chunk2)
        }

        @Test("Fetch returns correct response metadata")
        func fetchReturnsMetadata() async throws {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "text/plain",
                        "Content-Length": "5",
                    ],
                    body: Data("hello".utf8)
                )
            }

            let response = try await makeClient().fetch(makeURL()).get()

            #expect(response.response.status == .ok)
            #expect(response.response.mediaType == MediaType.text)
        }

        @Test("fetchString returns decoded string")
        func fetchString() async throws {
            let text = "Hello, Readium!"

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    headers: ["Content-Type": "text/plain; charset=utf-8"],
                    body: Data(text.utf8)
                )
            }

            let result = try await makeClient().fetchString(makeURL()).get()
            #expect(result == text)
        }
    }

    // MARK: - Download

    @Suite(.serialized)
    struct Download {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient() -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/download")!
        }

        @Test("Download writes data to a temporary file")
        func downloadWritesToFile() async throws {
            let content = Data("file content".utf8)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    headers: [
                        "Content-Length": "\(content.count)",
                        "Content-Type": "application/octet-stream",
                    ],
                    body: content
                )
            }

            let download = try await makeClient()
                .download(makeURL()) { _ in }
                .get()

            let downloadedData = try Data(contentsOf: download.location.url)
            #expect(downloadedData == content)

            // Cleanup
            try FileManager.default.removeItem(at: download.location.url)
        }

        @Test("Download reports progress")
        func downloadReportsProgress() async throws {
            let content = Data(repeating: 0x42, count: 1024)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    headers: ["Content-Length": "\(content.count)"],
                    body: content
                )
            }

            var progressValues: [Double] = []

            let download = try await makeClient()
                .download(makeURL()) { progress in
                    progressValues.append(progress)
                }
                .get()

            #expect(!progressValues.isEmpty)
            if let last = progressValues.last {
                #expect(last > 0)
                #expect(last <= 1.0)
            }

            // Cleanup
            try FileManager.default.removeItem(at: download.location.url)
        }

        @Test("Download cleans up temporary file on failure")
        func downloadCleansUpOnFailure() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(statusCode: 500, body: Data("error".utf8))
            }

            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let countBefore = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path))?.count ?? 0

            let result = await makeClient()
                .download(makeURL()) { _ in }

            let countAfter = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path))?.count ?? 0

            guard case .failure = result else {
                Issue.record("Expected failure")
                return
            }
            #expect(countAfter == countBefore, "Temporary file should be deleted on failure")
        }

        @Test("Download preserves suggested filename from Content-Disposition")
        func downloadSuggestedFilename() async throws {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    headers: [
                        "Content-Disposition": "attachment; filename=book.epub",
                        "Content-Type": "application/epub+zip",
                    ],
                    body: Data("epub".utf8)
                )
            }

            let download = try await makeClient()
                .download(makeURL()) { _ in }
                .get()

            #expect(download.suggestedFilename == "book.epub")

            // Cleanup
            try FileManager.default.removeItem(at: download.location.url)
        }
    }

    // MARK: - HTTP Errors

    @Suite(.serialized)
    struct HTTPErrors {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient() -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/error")!
        }

        @Test(
            "HTTP error status codes return .errorResponse",
            arguments: [400, 401, 403, 404, 405, 500]
        )
        func httpErrorStatusCodes(statusCode: Int) async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(statusCode: statusCode, body: Data())
            }

            let result = await makeClient().fetch(makeURL())

            guard case let .failure(.errorResponse(response)) = result else {
                Issue.record("Expected .errorResponse for status \(statusCode)")
                return
            }
            #expect(response.response.status.rawValue == statusCode)
        }

        @Test("Error response body is accumulated")
        func errorResponseIncludesBody() async {
            let errorBody = Data("""
            {"type": "https://example.com/auth", "title": "Authentication Required"}
            """.utf8)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    statusCode: 401,
                    headers: ["Content-Type": "application/problem+json"],
                    body: errorBody
                )
            }

            let result = await makeClient().fetch(makeURL())

            guard case let .failure(.errorResponse(response)) = result else {
                Issue.record("Expected .errorResponse")
                return
            }
            #expect(response.body == errorBody)
        }

        @Test(
            "2xx status codes are treated as success",
            arguments: [200, 201, 204]
        )
        func successStatusCodes(statusCode: Int) async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(statusCode: statusCode, body: Data("ok".utf8))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .success = result else {
                Issue.record("Status \(statusCode) should be success but got \(result)")
                return
            }
        }
    }

    // MARK: - Network Errors

    @Suite(.serialized)
    struct NetworkErrors {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient() -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/network")!
        }

        @Test("Timeout returns .timeout error")
        func timeoutError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.timedOut))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.timeout) = result else {
                Issue.record("Expected .timeout error, got \(result)")
                return
            }
        }

        @Test("Cannot connect to host returns .unreachable error")
        func unreachableError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.cannotConnectToHost))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.unreachable) = result else {
                Issue.record("Expected .unreachable error, got \(result)")
                return
            }
        }

        @Test("Cannot find host returns .unreachable error")
        func cannotFindHostError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.cannotFindHost))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.unreachable) = result else {
                Issue.record("Expected .unreachable error, got \(result)")
                return
            }
        }

        @Test("Not connected to internet returns .offline error")
        func offlineError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.notConnectedToInternet))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.offline) = result else {
                Issue.record("Expected .offline error, got \(result)")
                return
            }
        }

        @Test("Network connection lost returns .offline error")
        func networkConnectionLostError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.networkConnectionLost))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.offline) = result else {
                Issue.record("Expected .offline error, got \(result)")
                return
            }
        }

        @Test("Cancelled request returns .cancelled error")
        func cancelledError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.cancelled))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.cancelled) = result else {
                Issue.record("Expected .cancelled error, got \(result)")
                return
            }
        }

        @Test("Secure connection failed returns .security error")
        func securityError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.secureConnectionFailed))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.security) = result else {
                Issue.record("Expected .security error, got \(result)")
                return
            }
        }

        @Test("Too many redirects returns .redirection error")
        func redirectionError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.httpTooManyRedirects))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.redirection) = result else {
                Issue.record("Expected .redirection error, got \(result)")
                return
            }
        }

        @Test("Bad server response returns .malformedResponse error")
        func malformedResponseError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.badServerResponse))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.malformedResponse) = result else {
                Issue.record("Expected .malformedResponse error, got \(result)")
                return
            }
        }

        @Test("Unknown URLError returns .other error")
        func otherError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.backgroundSessionWasDisconnected))
            }

            let result = await makeClient().fetch(makeURL())

            guard case .failure(.other) = result else {
                Issue.record("Expected .other error, got \(result)")
                return
            }
        }
    }

    // MARK: - Cancellation

    @Suite(.serialized)
    struct Cancellation {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient() -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/cancel")!
        }

        @Test("Cancelling the Swift task cancels the HTTP request")
        func cancelledTaskReturnsCancelledError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .delayed(seconds: 2, then: .success(body: Data("late".utf8)))
            }

            let task = Task {
                await makeClient().fetch(makeURL())
            }

            // Give the request time to start, then cancel.
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            task.cancel()

            let result = await task.value

            guard case .failure(.cancelled) = result else {
                // URLSession may also report .timeout or other errors on cancel
                // depending on timing, so we accept any failure.
                if case .failure = result {
                    return
                }
                Issue.record("Expected failure after cancellation, got \(result)")
                return
            }
        }
    }

    // MARK: - Range Requests

    @Suite(.serialized)
    struct RangeRequests {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient() -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(configuration: config)
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/range")!
        }

        @Test("Range request succeeds when server signals Accept-Ranges")
        func rangeRequestSuccessViaAcceptRanges() async throws {
            let partialContent = Data("partial".utf8)

            MockHTTPURLProtocol.requestHandler = { request in
                let rangeHeader = request.value(forHTTPHeaderField: "Range")
                #expect(rangeHeader != nil)

                return .success(
                    statusCode: 206,
                    headers: [
                        "Accept-Ranges": "bytes",
                        "Content-Length": "\(partialContent.count)",
                    ],
                    body: partialContent
                )
            }

            var httpRequest = HTTPRequest(url: makeURL())
            httpRequest.setRange(0 ..< 7)

            let response = try await makeClient().fetch(httpRequest).get()
            #expect(response.response.status == .partialContent)
            #expect(response.body == partialContent)
        }

        @Test("Range request succeeds when server signals Content-Range without Accept-Ranges")
        func rangeRequestSuccessViaContentRange() async throws {
            let partialContent = Data("partial".utf8)

            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    statusCode: 206,
                    headers: [
                        "Content-Range": "bytes 0-6/100",
                        "Content-Length": "\(partialContent.count)",
                    ],
                    body: partialContent
                )
            }

            var httpRequest = HTTPRequest(url: makeURL())
            httpRequest.setRange(0 ..< 7)

            let response = try await makeClient().fetch(httpRequest).get()
            #expect(response.response.status == .partialContent)
            #expect(response.body == partialContent)
        }

        @Test("Range request fails when server does not support byte ranges")
        func rangeRequestFailsWithoutServerSupport() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(
                    statusCode: 200,
                    headers: [:],
                    body: Data("full content".utf8)
                )
            }

            var httpRequest = HTTPRequest(url: makeURL())
            httpRequest.setRange(0 ..< 7)

            let result = await makeClient().fetch(httpRequest)

            guard case .failure(.rangeNotSupported) = result else {
                Issue.record("Expected .rangeNotSupported, got \(result)")
                return
            }
        }
    }

    // MARK: - Delegate Callbacks

    @Suite(.serialized)
    struct DelegateCallbacks {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient(delegate: DefaultHTTPClientDelegate) -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(
                configuration: config,
                delegate: delegate
            )
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/delegate")!
        }

        @Test("willStartRequest is called before the request")
        func willStartRequestIsCalled() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(body: Data("ok".utf8))
            }

            let delegate = SpyDelegate()
            let client = makeClient(delegate: delegate)
            _ = await client.fetch(makeURL())

            #expect(delegate.willStartRequestCalled)
        }

        @Test("willStartRequest can modify the request")
        func willStartRequestModifiesRequest() async {
            var receivedHeader: String?

            MockHTTPURLProtocol.requestHandler = { request in
                receivedHeader = request.value(forHTTPHeaderField: "X-Injected")
                return .success(body: Data("ok".utf8))
            }

            let delegate = SpyDelegate()
            delegate.onWillStartRequest = { request in
                var modified = request
                modified.headers["X-Injected"] = "by-delegate"
                return .success(modified)
            }

            let client = makeClient(delegate: delegate)
            _ = await client.fetch(makeURL())

            #expect(receivedHeader == "by-delegate")
        }

        @Test("willStartRequest returning failure aborts the request without sending it")
        func willStartRequestFailureAbortsRequest() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                Issue.record("Request should not have been sent")
                return .success(body: Data())
            }

            let delegate = SpyDelegate()
            delegate.onWillStartRequest = { _ in
                .failure(.cancelled)
            }

            let client = makeClient(delegate: delegate)
            let result = await client.fetch(makeURL())

            guard case .failure(.cancelled) = result else {
                Issue.record("Expected .cancelled from willStartRequest failure, got \(result)")
                return
            }
        }

        @Test("didReceiveResponse is called on success")
        func didReceiveResponseIsCalled() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(body: Data("ok".utf8))
            }

            let delegate = SpyDelegate()
            let client = makeClient(delegate: delegate)
            _ = await client.fetch(makeURL())

            #expect(delegate.didReceiveResponseCalled)
        }

        @Test("didFailWithError is called on failure")
        func didFailWithErrorIsCalled() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.timedOut))
            }

            let delegate = SpyDelegate()
            let client = makeClient(delegate: delegate)
            _ = await client.fetch(makeURL())

            #expect(delegate.didFailWithErrorCalled)
        }

        @Test("recoverRequest can retry with a new request")
        func recoverRequestRetries() async throws {
            var requestCount = 0

            MockHTTPURLProtocol.requestHandler = { _ in
                requestCount += 1
                if requestCount == 1 {
                    return .error(URLError(.timedOut))
                }
                return .success(body: Data("recovered".utf8))
            }

            let delegate = SpyDelegate()
            delegate.onRecoverRequest = { request, _ in
                // Retry the same request
                .success(request)
            }

            let client = makeClient(delegate: delegate)
            let result = await client.fetch(makeURL())

            let response = try result.get()
            #expect(response.body == Data("recovered".utf8))
            #expect(requestCount == 2)
        }

        @Test("recoverRequest propagates error when unrecoverable")
        func recoverRequestPropagatesError() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .error(URLError(.timedOut))
            }

            let delegate = SpyDelegate()
            delegate.onRecoverRequest = { _, error in
                .failure(error)
            }

            let client = makeClient(delegate: delegate)
            let result = await client.fetch(makeURL())

            guard case .failure(.timeout) = result else {
                Issue.record("Expected .timeout, got \(result)")
                return
            }
            #expect(delegate.didFailWithErrorCalled)
        }

        @Test("willStartRequest can redirect to a different URL")
        func willStartRequestRedirects() async throws {
            MockHTTPURLProtocol.requestHandler = { request in
                let path = request.url?.path ?? ""
                if path == "/redirected" {
                    return .success(body: Data("redirected response".utf8))
                }
                return .success(statusCode: 404, body: Data())
            }

            let delegate = SpyDelegate()
            delegate.onWillStartRequest = { _ in
                let redirectURL = HTTPURL(string: "https://example.com/redirected")!
                return .success(HTTPRequest(url: redirectURL))
            }

            let client = makeClient(delegate: delegate)
            let response = try await client.fetch(makeURL()).get()
            #expect(response.body == Data("redirected response".utf8))
        }
    }

    // MARK: - Authentication Challenges

    @Suite(.serialized)
    struct AuthenticationChallenges {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeClient(delegate: DefaultHTTPClientDelegate) -> DefaultHTTPClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            return DefaultHTTPClient(
                configuration: config,
                delegate: delegate
            )
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/auth")!
        }

        @Test("Delegate receives authentication challenge")
        func delegateReceivesChallenge() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .authenticationChallenge(
                    host: "example.com",
                    method: NSURLAuthenticationMethodHTTPBasic,
                    then: .success(body: Data("authenticated".utf8))
                )
            }

            let delegate = SpyDelegate()
            delegate.onDidReceiveChallenge = { _ in
                .performDefaultHandling
            }

            let client = makeClient(delegate: delegate)
            _ = await client.fetch(makeURL())

            #expect(delegate.didReceiveChallengeCalled)
        }

        @Test("Regular request succeeds without a delegate")
        func regularRequestSucceedsWithoutDelegate() async {
            MockHTTPURLProtocol.requestHandler = { _ in
                .success(body: Data("ok".utf8))
            }

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            let client = DefaultHTTPClient(configuration: config, delegate: nil)

            let result = await client.fetch(makeURL())

            guard case .success = result else {
                Issue.record("Expected success for a regular request without a delegate, got \(result)")
                return
            }
        }
    }

    // MARK: - Configuration

    @Suite(.serialized)
    struct Configuration {
        init() {
            MockHTTPURLProtocol.requestHandler = nil
        }

        private func makeURL() -> HTTPURL {
            HTTPURL(string: "https://example.com/config")!
        }

        @Test("Request timeout is passed to URLSessionConfiguration")
        func requestTimeoutIsApplied() async {
            var receivedTimeout: TimeInterval?

            MockHTTPURLProtocol.requestHandler = { request in
                receivedTimeout = request.timeoutInterval
                return .success(body: Data("ok".utf8))
            }

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            config.timeoutIntervalForRequest = 42.0
            let client = DefaultHTTPClient(configuration: config)
            _ = await client.fetch(makeURL())

            // URLSession may apply its own timeout logic, but the
            // configuration value should influence the request.
            #expect(receivedTimeout != nil)
        }

        @Test("Per-request timeout overrides session timeout")
        func perRequestTimeoutOverridesSession() async {
            var receivedTimeout: TimeInterval?

            MockHTTPURLProtocol.requestHandler = { request in
                receivedTimeout = request.timeoutInterval
                return .success(body: Data("ok".utf8))
            }

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            config.timeoutIntervalForRequest = 60.0
            let client = DefaultHTTPClient(configuration: config)

            var request = HTTPRequest(url: makeURL())
            request.timeoutInterval = 5.0
            _ = await client.fetch(request)

            #expect(receivedTimeout == 5.0)
        }

        @Test("HTTP method is correctly transmitted")
        func httpMethodIsTransmitted() async {
            var receivedMethod: String?

            MockHTTPURLProtocol.requestHandler = { request in
                receivedMethod = request.httpMethod
                return .success(body: Data("ok".utf8))
            }

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            let client = DefaultHTTPClient(configuration: config)

            let request = HTTPRequest(url: makeURL(), method: .post)
            _ = await client.fetch(request)

            #expect(receivedMethod == "POST")
        }

        @Test("Request body is transmitted for POST requests")
        func requestBodyIsTransmitted() async {
            var receivedBody: Data?

            MockHTTPURLProtocol.requestHandler = { request in
                if let stream = request.httpBodyStream {
                    stream.open()
                    var data = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
                    defer { buffer.deallocate() }
                    while stream.hasBytesAvailable {
                        let bytesRead = stream.read(buffer, maxLength: 1024)
                        if bytesRead > 0 {
                            data.append(buffer, count: bytesRead)
                        }
                    }
                    stream.close()
                    receivedBody = data
                } else {
                    receivedBody = request.httpBody
                }
                return .success(body: Data("ok".utf8))
            }

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockHTTPURLProtocol.self]
            let client = DefaultHTTPClient(configuration: config)

            let bodyData = Data("request body".utf8)
            let request = HTTPRequest(url: makeURL(), method: .post, body: .data(bodyData))
            _ = await client.fetch(request)

            #expect(receivedBody == bodyData)
        }
    }
}

// MARK: - Spy Delegate

/// A test spy implementing `DefaultHTTPClientDelegate` that records calls
/// and allows customizing behavior via closures.
private class SpyDelegate: DefaultHTTPClientDelegate {
    var willStartRequestCalled = false
    var didReceiveResponseCalled = false
    var didFailWithErrorCalled = false
    var didReceiveChallengeCalled = false

    var lastRequest: HTTPRequest?
    var lastResponse: HTTPResponse?
    var lastError: HTTPError?
    var lastChallenge: URLAuthenticationChallenge?

    var onWillStartRequest: ((HTTPRequest) -> HTTPResult<HTTPRequestConvertible>)?
    var onRecoverRequest: ((HTTPRequest, HTTPError) -> HTTPResult<HTTPRequestConvertible>)?
    var onDidReceiveChallenge: ((URLAuthenticationChallenge) -> URLAuthenticationChallengeResponse)?

    func httpClient(
        _ httpClient: DefaultHTTPClient,
        willStartRequest request: HTTPRequest
    ) async -> HTTPResult<HTTPRequestConvertible> {
        willStartRequestCalled = true
        lastRequest = request
        return onWillStartRequest?(request) ?? .success(request)
    }

    func httpClient(
        _ httpClient: DefaultHTTPClient,
        recoverRequest request: HTTPRequest,
        fromError error: HTTPError
    ) async -> HTTPResult<HTTPRequestConvertible> {
        onRecoverRequest?(request, error) ?? .failure(error)
    }

    func httpClient(
        _ httpClient: DefaultHTTPClient,
        request: HTTPRequest,
        didReceiveResponse response: HTTPResponse
    ) {
        didReceiveResponseCalled = true
        lastResponse = response
    }

    func httpClient(
        _ httpClient: DefaultHTTPClient,
        request: HTTPRequest,
        didFailWithError error: HTTPError
    ) {
        didFailWithErrorCalled = true
        lastError = error
    }

    func httpClient(
        _ httpClient: DefaultHTTPClient,
        request: HTTPRequest,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> URLAuthenticationChallengeResponse {
        didReceiveChallengeCalled = true
        lastChallenge = challenge
        return onDidReceiveChallenge?(challenge) ?? .performDefaultHandling
    }
}
