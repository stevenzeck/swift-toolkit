//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
#if canImport(UIKit)
    import UIKit
#endif

public enum URLAuthenticationChallengeResponse: Sendable {
    /// Use the specified credential.
    case useCredential(URLCredential)
    /// Use the default handling for the challenge as though this delegate method were not implemented.
    case performDefaultHandling
    /// Cancel the entire request.
    case cancelAuthenticationChallenge
    /// Reject this challenge, and call the authentication delegate method again with the next
    /// authentication protection space.
    case rejectProtectionSpace
}

/// Delegate protocol for `DefaultHTTPClient`.
public protocol DefaultHTTPClientDelegate: AnyObject {
    /// Tells the delegate that the HTTP client will start a new `request`.
    ///
    /// You can modify the `request`, for example by adding additional HTTP headers or redirecting to a different URL,
    /// before returning the new request.
    ///
    /// - Note: If this method returns a failure, the request is aborted immediately and `httpClient(_:request:didFailWithError:)`
    /// is NOT called.
    func httpClient(_ httpClient: DefaultHTTPClient, willStartRequest request: HTTPRequest) async -> HTTPResult<HTTPRequestConvertible>

    /// Asks the delegate to recover from an `error` received for the given `request`.
    ///
    /// This can be used to implement custom authentication flows, for example.
    ///
    /// You can return either:
    ///   * a new request to start
    ///   * the `error` argument, if you cannot recover from it
    ///   * a new `HTTPError` to provide additional information
    func httpClient(_ httpClient: DefaultHTTPClient, recoverRequest request: HTTPRequest, fromError error: HTTPError) async -> HTTPResult<HTTPRequestConvertible>

    /// Tells the delegate that we received an HTTP response for the given `request`.
    ///
    /// You do not need to do anything with this `response`, which the HTTP client will handle. This is merely for
    /// informational purposes. For example, you could implement this to confirm that request credentials were
    /// successful.
    func httpClient(_ httpClient: DefaultHTTPClient, request: HTTPRequest, didReceiveResponse response: HTTPResponse)

    /// Tells the delegate that a `request` failed with the given `error`.
    ///
    /// You do not need to do anything with this `response`, which the HTTP client will handle. This is merely for
    /// informational purposes.
    ///
    /// This will be called only if `httpClient(_:recoverRequest:fromError:)` is not implemented, or returns
    /// an error. It is also NOT called if `httpClient(_:willStartRequest:)` fails and aborts the request.
    func httpClient(_ httpClient: DefaultHTTPClient, request: HTTPRequest, didFailWithError error: HTTPError)

    /// Requests credentials from the delegate in response to an authentication request from the remote server.
    func httpClient(
        _ httpClient: DefaultHTTPClient,
        request: HTTPRequest,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> URLAuthenticationChallengeResponse
}

public extension DefaultHTTPClientDelegate {
    func httpClient(_ httpClient: DefaultHTTPClient, willStartRequest request: HTTPRequest) async -> HTTPResult<HTTPRequestConvertible> {
        .success(request)
    }

    func httpClient(_ httpClient: DefaultHTTPClient, recoverRequest request: HTTPRequest, fromError error: HTTPError) async -> HTTPResult<HTTPRequestConvertible> {
        .failure(error)
    }

    func httpClient(_ httpClient: DefaultHTTPClient, request: HTTPRequest, didReceiveResponse response: HTTPResponse) {}
    func httpClient(_ httpClient: DefaultHTTPClient, request: HTTPRequest, didFailWithError error: HTTPError) {}

    func httpClient(
        _ httpClient: DefaultHTTPClient,
        request: HTTPRequest,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> URLAuthenticationChallengeResponse {
        .performDefaultHandling
    }
}

/// An implementation of `HTTPClient` using native APIs.
public final class DefaultHTTPClient: HTTPClient, Loggable {
    /// Returns the default user agent used when issuing requests.
    ///
    /// For example, TestApp/1.3 x86_64 iOS/15.0 CFNetwork/1312 Darwin/20.6.0
    public static var defaultUserAgent: String = {
        var sysinfo = utsname()
        uname(&sysinfo)

        let darwinVersion = String(bytes: Data(bytes: &sysinfo.release, count: Int(_SYS_NAMELEN)), encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters)
            ?? "0"

        let deviceName = String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters)
            ?? "0"

        let cfNetworkVersion = Bundle(identifier: "com.apple.CFNetwork")?
            .infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0"

        let appInfo = Bundle.main.infoDictionary
        let appName = appInfo?["CFBundleName"] as? String ?? "Unknown App"
        let appVersion = appInfo?["CFBundleShortVersionString"] as? String ?? "0"
        let device = UIDevice.current

        return "\(appName)/\(appVersion) \(deviceName) \(device.systemName)/\(device.systemVersion) CFNetwork/\(cfNetworkVersion) Darwin/\(darwinVersion)"
    }()

    public weak var delegate: DefaultHTTPClientDelegate?

    private let session: URLSession
    private let userAgent: String

    /// Creates a `DefaultHTTPClient` with common configuration settings.
    ///
    /// - Parameters:
    ///   - userAgent: Default user agent issued with requests.
    ///   - cachePolicy: Determines the request caching policy used by HTTP tasks.
    ///   - ephemeral: When true, uses no persistent storage for caches, cookies, or credentials.
    ///   - additionalHeaders: A dictionary of additional headers to send with requests. For example, `User-Agent`.
    ///   - requestTimeout: The timeout interval to use when waiting for additional data.
    ///   - resourceTimeout: The maximum amount of time that a resource request should be allowed to take.
    ///   - delegate: An optional delegate to handle common HTTP events.
    ///   - configure: Callback used to configure further the `URLSessionConfiguration` object.
    public convenience init(
        userAgent: String? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil,
        ephemeral: Bool = false,
        additionalHeaders: [String: String]? = nil,
        requestTimeout: TimeInterval? = nil,
        resourceTimeout: TimeInterval? = nil,
        delegate: DefaultHTTPClientDelegate? = nil,
        configure: ((URLSessionConfiguration) -> Void)? = nil
    ) {
        let config: URLSessionConfiguration = ephemeral ? .ephemeral : .default
        config.httpAdditionalHeaders = additionalHeaders
        if let cachePolicy = cachePolicy {
            config.requestCachePolicy = cachePolicy
        }
        if let requestTimeout = requestTimeout {
            config.timeoutIntervalForRequest = requestTimeout
        }
        if let resourceTimeout = resourceTimeout {
            config.timeoutIntervalForResource = resourceTimeout
        }
        if let configure = configure {
            configure(config)
        }

        self.init(configuration: config, userAgent: userAgent, delegate: delegate)
    }

    /// Creates a `DefaultHTTPClient` with a custom configuration.
    ///
    /// - Parameters:
    ///   - configuration: The `URLSessionConfiguration` to use for all requests.
    ///   - userAgent: Default user agent issued with requests.
    ///   - delegate: An optional delegate to handle common HTTP events.
    public init(
        configuration: URLSessionConfiguration,
        userAgent: String? = nil,
        delegate: DefaultHTTPClientDelegate? = nil
    ) {
        self.userAgent = userAgent ?? DefaultHTTPClient.defaultUserAgent
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func stream(
        request: any HTTPRequestConvertible,
        onReceiveResponse: ((HTTPResponse) async -> HTTPResult<Void>)? = nil,
        consume: @Sendable (Data, Double?) -> HTTPResult<Void>
    ) async -> HTTPResult<HTTPResponse> {
        await request.httpRequest()
            .asyncFlatMap(willStartRequest)
            .asyncFlatMap { request in
                let result = await startTask(for: request, onReceiveResponse: onReceiveResponse, consume: consume)
                    .asyncRecover { error in
                        await recover(request, from: error)
                            .asyncFlatMap { newRequest in
                                await streamOnce(request: newRequest, onReceiveResponse: onReceiveResponse, consume: consume)
                            }
                    }

                if case let .failure(error) = result {
                    delegate?.httpClient(self, request: request, didFailWithError: error)
                }

                return result
            }
    }

    private func streamOnce(
        request: any HTTPRequestConvertible,
        onReceiveResponse: ((HTTPResponse) async -> HTTPResult<Void>)?,
        consume: @Sendable (Data, Double?) -> HTTPResult<Void>
    ) async -> HTTPResult<HTTPResponse> {
        await request.httpRequest()
            .asyncFlatMap { request in
                await startTask(for: request, onReceiveResponse: onReceiveResponse, consume: consume)
            }
    }

    /// Creates and starts an async byte stream for the `request`.
    private func startTask(
        for request: HTTPRequest,
        onReceiveResponse: ((HTTPResponse) async -> HTTPResult<Void>)?,
        consume: @Sendable (Data, Double?) -> HTTPResult<Void>
    ) async -> HTTPResult<HTTPResponse> {
        var request = request
        if request.userAgent == nil {
            request.userAgent = userAgent
        }

        let taskDelegate = TaskDelegate(
            request: request,
            clientDelegate: delegate,
            client: self
        )

        do {
            let task = session.dataTask(with: request.urlRequest)
            task.delegate = taskDelegate

            let (stream, response) = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(AsyncThrowingStream<Data, Error>, URLResponse), Error>) in
                    taskDelegate.responseContinuation = continuation
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }

            guard let httpURLResponse = response as? HTTPURLResponse, let url = httpURLResponse.url?.httpURL else {
                return .failure(.malformedResponse(nil))
            }

            let httpResponse = HTTPResponse(request: request, response: httpURLResponse, url: url)
            delegate?.httpClient(self, request: request, didReceiveResponse: httpResponse)

            if !httpResponse.status.isSuccess {
                let capacity = min(1024 * 1024, Int(httpResponse.fullContentLength ?? 1024))
                var errorData = Data()

                for try await chunk in stream {
                    if errorData.count < capacity {
                        errorData.append(chunk)
                    } else {
                        task.cancel()
                        break
                    }
                }
                errorData = errorData.prefix(capacity)
                return .failure(.errorResponse(HTTPFetchResponse(response: httpResponse, body: errorData)))
            }

            if request.hasHeader("Range"), !httpResponse.acceptsByteRanges {
                log(.error, "Streaming ranges requires the remote HTTP server to support byte range requests: \(url)")
                task.cancel()
                return .failure(.rangeNotSupported)
            }

            if let onReceive = onReceiveResponse {
                let result = await onReceive(httpResponse)
                if case let .failure(error) = result {
                    task.cancel()
                    return .failure(error)
                }
            }

            let expectedBytes = httpResponse.fullContentLength
            var readBytes: Int64 = httpResponse.contentRangeOffset

            for try await chunk in stream {
                readBytes += Int64(chunk.count)
                let progress = expectedBytes.map { $0 > 0 ? Double(min(readBytes, $0)) / Double($0) : 1.0 }
                if case let .failure(error) = consume(chunk, progress) {
                    task.cancel()
                    return .failure(error)
                }
            }

            return .success(httpResponse)

        } catch {
            if (error is CancellationError) || ((error as? URLError)?.code == .cancelled) {
                return .failure(.cancelled)
            }
            return .failure(.wrap(error) ?? .other(error))
        }
    }

    /// Lets the `delegate` customize the `request` if needed, before actually starting it.
    private func willStartRequest(_ request: HTTPRequest) async -> HTTPResult<HTTPRequest> {
        guard let delegate = delegate else {
            return .success(request)
        }
        return await delegate.httpClient(self, willStartRequest: request)
            .flatMap { $0.httpRequest() }
    }

    /// Attempts to recover from an `error` by asking the `delegate` for a new request.
    private func recover(_ request: HTTPRequest, from error: HTTPError) async -> HTTPResult<HTTPRequestConvertible> {
        if let delegate = delegate {
            return await delegate.httpClient(self, recoverRequest: request, fromError: error)
        } else {
            return .failure(error)
        }
    }

    /// Isolated proxy to pass challenges back to the `DefaultHTTPClientDelegate`.
    /// URLSession guarantees its delegate callbacks are serialized, so the mutable `authTask` is safe.
    /// Both `urlSession(_:task:didCompleteWithError:)` and `urlSession(_:task:didReceiveChallenge:completionHandler:)`
    /// run on the same serial delegate queue.
    private final class TaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let request: HTTPRequest
        weak var clientDelegate: DefaultHTTPClientDelegate?
        weak var client: DefaultHTTPClient?
        var authTask: Task<Void, Never>?

        var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        var responseContinuation: CheckedContinuation<(AsyncThrowingStream<Data, Error>, URLResponse), Error>?

        init(
            request: HTTPRequest,
            clientDelegate: DefaultHTTPClientDelegate?,
            client: DefaultHTTPClient
        ) {
            self.request = request
            self.clientDelegate = clientDelegate
            self.client = client
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            authTask?.cancel()
            if let responseContinuation = responseContinuation {
                self.responseContinuation = nil
                if let error = error {
                    responseContinuation.resume(throwing: error)
                } else {
                    // If there's no error but no response was received, the server closed the connection prematurely.
                    responseContinuation.resume(throwing: URLError(.badServerResponse))
                }
            } else {
                if let error = error {
                    streamContinuation?.finish(throwing: error)
                } else {
                    streamContinuation?.finish()
                }
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if let responseContinuation = responseContinuation {
                self.responseContinuation = nil

                var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation!
                let stream = AsyncThrowingStream<Data, Error> { cont in
                    streamContinuation = cont
                }
                self.streamContinuation = streamContinuation

                responseContinuation.resume(returning: (stream, response))
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            streamContinuation?.yield(data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard let client = client else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            authTask?.cancel()
            authTask = Task {
                if Task.isCancelled {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }

                if let delegate = clientDelegate {
                    let response = await delegate.httpClient(client, request: request, didReceive: challenge)

                    if Task.isCancelled {
                        completionHandler(.cancelAuthenticationChallenge, nil)
                        return
                    }

                    switch response {
                    case let .useCredential(credential):
                        completionHandler(.useCredential, credential)
                    case .performDefaultHandling:
                        completionHandler(.performDefaultHandling, nil)
                    case .cancelAuthenticationChallenge:
                        completionHandler(.cancelAuthenticationChallenge, nil)
                    case .rejectProtectionSpace:
                        completionHandler(.rejectProtectionSpace, nil)
                    }
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            }
        }
    }
}

private extension HTTPRequest {
    var urlRequest: URLRequest {
        var request = URLRequest(url: url.url)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = headers

        if let timeoutInterval = timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }

        if let body = body {
            switch body {
            case let .data(data):
                request.httpBody = data
            case let .file(url):
                request.httpBodyStream = InputStream(url: url)
            }
        }

        return request
    }
}

private extension HTTPResponse {
    init(request: HTTPRequest, response: HTTPURLResponse, url: HTTPURL) {
        var headers: [String: String] = [:]
        for (k, v) in response.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                headers[ks] = vs
            }
        }
        self.init(
            request: request,
            url: url,
            status: HTTPStatus(rawValue: response.statusCode),
            headers: headers,
            mediaType: response.mimeType.flatMap { MediaType($0) }
        )
    }
}
