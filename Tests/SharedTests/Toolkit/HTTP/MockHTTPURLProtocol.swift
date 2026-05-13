//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared

/// A `URLProtocol` subclass that intercepts HTTP requests for testing
/// `DefaultHTTPClient` without hitting the network.
///
/// Configure the static `requestHandler` before each test to control
/// the response returned for intercepted requests.
final class MockHTTPURLProtocol: Foundation.URLProtocol {
    /// Handler called for each intercepted request. Returns the response
    /// configuration to simulate.
    ///
    /// Must be set before starting a request.
    static var requestHandler: ((URLRequest) -> MockResponse)? {
        get { _requestHandler.value }
        set { _requestHandler = UncheckedSendable(newValue) }
    }

    private static var _requestHandler = UncheckedSendable<((URLRequest) -> MockResponse)?>(nil)

    /// Describes a mock response to return for an intercepted request.
    indirect enum MockResponse {
        /// A successful response delivered as a sequence of data chunks.
        case success(
            statusCode: Int = 200,
            headers: [String: String] = [:],
            chunks: [Data] = []
        )

        /// A simulated network error.
        case error(URLError)

        /// A response that is delivered after a delay, useful for timeout
        /// testing. Delivery is cancelled early if `stopLoading()` is called.
        case delayed(
            seconds: TimeInterval,
            then: MockResponse
        )

        /// An authentication challenge, followed by a response if the
        /// challenge is resolved.
        case authenticationChallenge(
            host: String = "example.com",
            method: String = NSURLAuthenticationMethodHTTPBasic,
            then: MockResponse
        )

        /// Convenience for a simple success response with a single body.
        static func success(
            statusCode: Int = 200,
            headers: [String: String] = [:],
            body: Data = Data()
        ) -> MockResponse {
            .success(statusCode: statusCode, headers: headers, chunks: [body])
        }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    private actor StoppedState {
        var isStopped = false
        func setStopped() {
            isStopped = true
        }

        func getStopped() -> Bool {
            isStopped
        }
    }

    private let stoppedState = StoppedState()

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("MockHTTPURLProtocol.requestHandler is not set.")
        }

        let mockResponse = handler(request)
        deliver(mockResponse)
    }

    override func stopLoading() {
        Task { await stop() }
    }

    private func stop() async {
        await stoppedState.setStopped()
    }

    private func isStopped() async -> Bool {
        await stoppedState.getStopped()
    }

    // MARK: - Private

    private func deliver(_ response: MockResponse) {
        switch response {
        case let .success(statusCode, headers, chunks):
            deliverSuccess(statusCode: statusCode, headers: headers, chunks: chunks)

        case let .error(urlError):
            client?.urlProtocol(self, didFailWithError: urlError)

        case let .delayed(seconds, then):
            // Poll in short intervals so that `stopLoading()` can interrupt
            // the wait without blocking the thread for the full duration.
            let pollInterval: TimeInterval = 0.05
            var elapsed: TimeInterval = 0

            Task {
                while elapsed < seconds, await !isStopped() {
                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                    elapsed += pollInterval
                }
                if await !isStopped() {
                    deliver(then)
                }
            }

        case let .authenticationChallenge(host, method, then):
            let protectionSpace = URLProtectionSpace(
                host: host,
                port: 443,
                protocol: "https",
                realm: "Test",
                authenticationMethod: method
            )
            let challenge = URLAuthenticationChallenge(
                protectionSpace: protectionSpace,
                proposedCredential: nil,
                previousFailureCount: 0,
                failureResponse: nil,
                error: nil,
                sender: MockAuthChallengeSender()
            )
            client?.urlProtocol(self, didReceive: challenge)

            deliver(then)
        }
    }

    private func deliverSuccess(statusCode: Int, headers: [String: String], chunks: [Data]) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        for chunk in chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }

        client?.urlProtocolDidFinishLoading(self)
    }
}

/// A minimal `URLAuthenticationChallengeSender` implementation required
/// to construct `URLAuthenticationChallenge` objects in tests.
private class MockAuthChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
