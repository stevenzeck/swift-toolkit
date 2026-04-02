//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import UIKit

public enum URLAuthenticationChallengeResponse {
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
    /// an error.
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
        consume: @escaping (Data, Double?) -> HTTPResult<Void>
    ) async -> HTTPResult<HTTPResponse> {
        let result = await request.httpRequest()
            .asyncFlatMap(willStartRequest)
            .asyncFlatMap { request in
                await startTask(for: request, onReceiveResponse: onReceiveResponse, consume: consume)
                    .asyncRecover { error in
                        await recover(request, from: error)
                            .asyncFlatMap { newRequest in
                                await stream(request: newRequest, onReceiveResponse: onReceiveResponse, consume: consume)
                            }
                    }
            }

        if case let .failure(error) = result, let request = try? await request.httpRequest() {
            delegate?.httpClient(self, request: request, didFailWithError: error)
        }

        return result
    }

    /// Creates and starts an async byte stream for the `request`.
    private func startTask(
        for request: HTTPRequest,
        onReceiveResponse: ((HTTPResponse) async -> HTTPResult<Void>)?,
        consume: @escaping (Data, Double?) -> HTTPResult<Void>
    ) async -> HTTPResult<HTTPResponse> {
        var request = request
        if request.userAgent == nil {
            request.userAgent = userAgent
        }

        let taskDelegate = TaskDelegate(
            request: request,
            clientDelegate: delegate,
            client: self,
            onReceiveResponse: onReceiveResponse,
            consume: consume
        )

        let task = session.dataTask(with: request.urlRequest)
        task.delegate = taskDelegate

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                taskDelegate.responseContinuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
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
    private final class TaskDelegate: NSObject, URLSessionDataDelegate {
        let request: HTTPRequest
        weak var clientDelegate: DefaultHTTPClientDelegate?
        weak var client: DefaultHTTPClient?
        var authTask: Task<Void, Never>?

        var onReceiveResponse: ((HTTPResponse) async -> HTTPResult<Void>)?
        var consume: ((Data, Double?) -> HTTPResult<Void>)?
        var responseContinuation: CheckedContinuation<HTTPResult<HTTPResponse>, Never>?

        var httpResponse: HTTPResponse?
        var readBytes: Int64 = 0
        var expectedBytes: Int64?
        var errorData = Data()
        var consumeError: HTTPError?

        init(
            request: HTTPRequest,
            clientDelegate: DefaultHTTPClientDelegate?,
            client: DefaultHTTPClient,
            onReceiveResponse: ((HTTPResponse) async -> HTTPResult<Void>)?,
            consume: @escaping (Data, Double?) -> HTTPResult<Void>
        ) {
            self.request = request
            self.clientDelegate = clientDelegate
            self.client = client
            self.onReceiveResponse = onReceiveResponse
            self.consume = consume
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            authTask?.cancel()
            
            if let consumeError = consumeError {
                responseContinuation?.resume(returning: .failure(consumeError))
            } else if let error = error {
                let isCancelled = (error is CancellationError) || ((error as? URLError)?.code == .cancelled)
                let httpError: HTTPError = isCancelled ? .cancelled : (.wrap(error) ?? .other(error))
                responseContinuation?.resume(returning: .failure(httpError))
            } else if let httpResponse = httpResponse {
                if !httpResponse.status.isSuccess {
                    responseContinuation?.resume(returning: .failure(.errorResponse(HTTPFetchResponse(response: httpResponse, body: errorData))))
                } else {
                    responseContinuation?.resume(returning: .success(httpResponse))
                }
            } else {
                responseContinuation?.resume(returning: .failure(.other(URLError(.unknown))))
            }
            responseContinuation = nil
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let httpURLResponse = response as? HTTPURLResponse, let url = httpURLResponse.url?.httpURL else {
                responseContinuation?.resume(returning: .failure(.malformedResponse(nil)))
                responseContinuation = nil
                completionHandler(.cancel)
                return
            }

            let httpResponse = HTTPResponse(request: request, response: httpURLResponse, url: url)
            self.httpResponse = httpResponse
            client?.delegate?.httpClient(client!, request: request, didReceiveResponse: httpResponse)

            guard httpResponse.status.isSuccess else {
                completionHandler(.allow)
                return
            }

            if request.hasHeader("Range"), !httpResponse.acceptsByteRanges {
                log(.error, "Streaming ranges requires the remote HTTP server to support byte range requests: \(url)")
                responseContinuation?.resume(returning: .failure(.rangeNotSupported))
                responseContinuation = nil
                completionHandler(.cancel)
                return
            }

            readBytes = httpResponse.contentRangeOffset
            expectedBytes = httpResponse.fullContentLength

            if let onReceive = onReceiveResponse {
                Task {
                    let result = await onReceive(httpResponse)
                    if case let .failure(error) = result {
                        self.responseContinuation?.resume(returning: .failure(error))
                        self.responseContinuation = nil
                        completionHandler(.cancel)
                    } else {
                        completionHandler(.allow)
                    }
                }
            } else {
                completionHandler(.allow)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            if let httpResponse = httpResponse, !httpResponse.status.isSuccess {
                if errorData.count < 1024 * 1024 {
                    errorData.append(data)
                }
                return
            }

            readBytes += Int64(data.count)
            let progress = expectedBytes.map { Double(min(readBytes, $0)) / Double($0) }
            
            if let consume = consume {
                if case let .failure(error) = consume(data, progress) {
                    self.consumeError = error
                    dataTask.cancel()
                }
            }
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
