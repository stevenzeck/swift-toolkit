//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Initialize the Logger.
/// Default logger is the `LoggerStub` class
///
/// - Parameters:
///   - level: The minimum severity level for logs to be processed.
///   - customLogger: The Logger that will be used for printing logs.
///     Defaults to a `LoggerStub` which may perform no-op logging.
public func ReadiumEnableLog(withMinimumSeverityLevel level: SeverityLevel, customLogger: LoggerType = LoggerStub()) {
    Logger.sharedInstance.setupLogger(logger: customLogger)
    Logger.sharedInstance.setMinimumSeverityLevel(at: level)

    print("\(SeverityLevel.info.symbol) Readium 2 Log enabled with minimum severity level of [\(level)].")
}

/// The Logger protocol.
public protocol LoggerType: Sendable {
    func log(level: SeverityLevel, value: String?, file: String, line: Int)
}

/// Logger singleton.
public final class Logger: @unchecked Sendable {
    /// The active logger is responsible for displaying the log message
    /// throughout the framework. There is a default implementation `LoggerStub`
    /// available. You can define your own implementation by applying the
    /// `Loggable` protocol to your xLogger class.
    var activeLogger: LoggerType?

    /// The minimum severity level for logs to be displayed.
    var minimumSeverityLevel: SeverityLevel?

    private let lock = NSLock()

    private(set) static var sharedInstance = Logger()

    // MARK: - Public methods.

    /// Setup the active logger, and optionally the minimumSeverityLevel.
    /// See `activeLogger` for more informations.
    ///
    /// - Parameters:
    ///   - logger: The logger to be used as the `activeLogger`.
    ///   - severityLevel: The minimum severity level of displayed logs.
    public func setupLogger(logger: LoggerType,
                            withMinimumSeverityLevel severityLevel: SeverityLevel? = .warning)
    {
        lock.lock()
        defer { lock.unlock() }
        activeLogger = logger
        minimumSeverityLevel = severityLevel
    }

    /// Allow the framework user to set the minimum severity level for the logs
    /// being displayed.
    ///
    /// - Parameter severityLevel: The value from the `SeverityLevel` enum.
    public func setMinimumSeverityLevel(at severityLevel: SeverityLevel?) {
        guard let severityLevel else { return }
        lock.lock()
        defer { lock.unlock() }
        minimumSeverityLevel = severityLevel
    }

    // MARK: - Internal methods.

    func log(_ value: String?, at level: SeverityLevel, file: String, line: Int) {
        lock.lock()
        defer { lock.unlock() }
        if let minimumSeverityLevel {
            guard level.numericValue >= minimumSeverityLevel.numericValue else { return }
        }
        activeLogger?.log(level: level, value: value, file: file, line: line)
    }
}
