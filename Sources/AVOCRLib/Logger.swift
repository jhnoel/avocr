import Foundation

public enum LogLevel: Int, CaseIterable, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3

    var label: String {
        switch self {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warn:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }

    var prefix: String? {
        switch self {
        case .debug:
            return "Debug"
        case .info:
            return nil
        case .warn:
            return "Warning"
        case .error:
            return "Error"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum LogFormat: String, Sendable {
    case text
    case json
}

public protocol Logger: AnyObject {
    func log(_ level: LogLevel, message: String, metadata: [String: String]?)
}

public extension Logger {
    func debug(_ message: String, metadata: [String: String]? = nil) {
        log(.debug, message: message, metadata: metadata)
    }

    func info(_ message: String, metadata: [String: String]? = nil) {
        log(.info, message: message, metadata: metadata)
    }

    func warn(_ message: String, metadata: [String: String]? = nil) {
        log(.warn, message: message, metadata: metadata)
    }

    func error(_ message: String, metadata: [String: String]? = nil) {
        log(.error, message: message, metadata: metadata)
    }
}

public final class ConsoleLogger: Logger {
    private let output: OutputStreamProtocol
    private let minimumLevel: LogLevel

    public init(output: OutputStreamProtocol = StandardErrorStream(), minimumLevel: LogLevel = .info) {
        self.output = output
        self.minimumLevel = minimumLevel
    }

    public func log(_ level: LogLevel, message: String, metadata: [String: String]?) {
        guard level >= minimumLevel else { return }
        var line = formatLine(level: level, message: message, metadata: metadata)
        if !line.hasSuffix("\n") {
            line.append("\n")
        }
        output.write(line)
    }

    private func formatLine(level: LogLevel, message: String, metadata: [String: String]?) -> String {
        var line = message
        if let prefix = level.prefix {
            line = "\(prefix): \(message)"
        }
        if let metadata = metadata, !metadata.isEmpty {
            let suffix = metadata.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            line = "\(line) \(suffix)"
        }
        return line
    }
}

public final class JSONLogger: Logger {
    private struct Record: Encodable {
        let timestamp: String
        let level: String
        let message: String
        let metadata: [String: String]?
    }

    private let output: OutputStreamProtocol
    private let minimumLevel: LogLevel
    private let encoder: JSONEncoder
    private let timestampProvider: () -> Date

    public init(
        output: OutputStreamProtocol = StandardErrorStream(),
        minimumLevel: LogLevel = .info,
        timestampProvider: @escaping () -> Date = Date.init
    ) {
        self.output = output
        self.minimumLevel = minimumLevel
        self.timestampProvider = timestampProvider
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func log(_ level: LogLevel, message: String, metadata: [String: String]?) {
        guard level >= minimumLevel else { return }
        let formatter = ISO8601DateFormatter()
        let record = Record(
            timestamp: formatter.string(from: timestampProvider()),
            level: level.label.lowercased(),
            message: message,
            metadata: metadata
        )
        guard let data = try? encoder.encode(record) else { return }
        output.write(data: data)
        output.write(data: Data([0x0A]))
    }
}

public final class NullLogger: Logger {
    public init() {}

    public func log(_ level: LogLevel, message: String, metadata: [String: String]?) {}
}

enum LoggerFactory {
    static func minimumLevel(isVerbose: Bool) -> LogLevel {
        isVerbose ? .debug : .info
    }

    static func makeLogger(format: LogFormat, isVerbose: Bool, output: OutputStreamProtocol) -> Logger {
        let minimumLevel = minimumLevel(isVerbose: isVerbose)
        switch format {
        case .text:
            return ConsoleLogger(output: output, minimumLevel: minimumLevel)
        case .json:
            return JSONLogger(output: output, minimumLevel: minimumLevel)
        }
    }
}
