import Foundation

enum CLIError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case missingValue(String)
    case fileNotFound(String)
    case noSupportedFiles
    case other(String)

    var description: String {
        switch self {
        case .invalidArgument(let msg):
            return msg
        case .missingValue(let msg):
            return msg
        case .fileNotFound(let path):
            return "Path does not exist: \(path)"
        case .noSupportedFiles:
            return "No supported files found"
        case .other(let msg):
            return msg
        }
    }
}
