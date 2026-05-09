import Foundation
import Darwin

public protocol OutputStreamProtocol: AnyObject {
    func write(_ string: String)
    func write(data: Data)
    func flush()
}

public final class StandardOutputStream: OutputStreamProtocol {
    private let fileHandle: FileHandle
    private let filePointer: UnsafeMutablePointer<FILE>

    public init(
        fileHandle: FileHandle = .standardOutput,
        filePointer: UnsafeMutablePointer<FILE> = stdout
    ) {
        self.fileHandle = fileHandle
        self.filePointer = filePointer
    }

    public func write(_ string: String) {
        _ = string.withCString { buffer in
            fputs(buffer, filePointer)
        }
    }

    public func write(data: Data) {
        fileHandle.write(data)
    }

    public func flush() {
        fflush(filePointer)
    }
}

public final class StandardErrorStream: OutputStreamProtocol {
    private let fileHandle: FileHandle
    private let filePointer: UnsafeMutablePointer<FILE>

    public init(
        fileHandle: FileHandle = .standardError,
        filePointer: UnsafeMutablePointer<FILE> = stderr
    ) {
        self.fileHandle = fileHandle
        self.filePointer = filePointer
    }

    public func write(_ string: String) {
        _ = string.withCString { buffer in
            fputs(buffer, filePointer)
        }
    }

    public func write(data: Data) {
        fileHandle.write(data)
    }

    public func flush() {
        fflush(filePointer)
    }
}

public final class InMemoryOutputStream: OutputStreamProtocol {
    public private(set) var data = Data()

    public init() {}

    public func write(_ string: String) {
        if let encoded = string.data(using: .utf8) {
            data.append(encoded)
        }
    }

    public func write(data: Data) {
        self.data.append(data)
    }

    public func flush() {}

    public var text: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

public protocol FileSystemProtocol: AnyObject {
    func fileExists(atPath: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func createDirectory(
        atPath: String,
        withIntermediateDirectories: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator?
    func createFile(atPath: String, contents: Data?) -> Bool
    func openFileForWriting(at url: URL) throws -> FileHandle
    func isExecutableFile(atPath: String) -> Bool
}

public final class RealFileSystem: FileSystemProtocol {
    private let manager: FileManager

    public init(manager: FileManager = .default) {
        self.manager = manager
    }

    public func fileExists(atPath: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        manager.fileExists(atPath: atPath, isDirectory: isDirectory)
    }

    public func createDirectory(
        atPath: String,
        withIntermediateDirectories: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        try manager.createDirectory(
            atPath: atPath,
            withIntermediateDirectories: withIntermediateDirectories,
            attributes: attributes
        )
    }

    public func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        manager.enumerator(at: url, includingPropertiesForKeys: keys, options: options)
    }

    public func createFile(atPath: String, contents: Data?) -> Bool {
        manager.createFile(atPath: atPath, contents: contents)
    }

    public func openFileForWriting(at url: URL) throws -> FileHandle {
        try FileHandle(forWritingTo: url)
    }

    public func isExecutableFile(atPath: String) -> Bool {
        manager.isExecutableFile(atPath: atPath)
    }
}

public final class MockFileSystem: FileSystemProtocol {
    public var fileExistsHandler: ((String, UnsafeMutablePointer<ObjCBool>?) -> Bool)?
    public var createDirectoryHandler: ((String, Bool, [FileAttributeKey: Any]?) throws -> Void)?
    public var enumeratorHandler: ((URL, [URLResourceKey]?, FileManager.DirectoryEnumerationOptions) -> FileManager.DirectoryEnumerator?)?
    public var createFileHandler: ((String, Data?) -> Bool)?
    public var openFileForWritingHandler: ((URL) throws -> FileHandle)?
    public var isExecutableFileHandler: ((String) -> Bool)?

    public init() {}

    public func fileExists(atPath: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        fileExistsHandler?(atPath, isDirectory) ?? false
    }

    public func createDirectory(
        atPath: String,
        withIntermediateDirectories: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        try createDirectoryHandler?(atPath, withIntermediateDirectories, attributes)
    }

    public func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        enumeratorHandler?(url, keys, options)
    }

    public func createFile(atPath: String, contents: Data?) -> Bool {
        createFileHandler?(atPath, contents) ?? false
    }

    public func openFileForWriting(at url: URL) throws -> FileHandle {
        if let handler = openFileForWritingHandler {
            return try handler(url)
        }
        throw NSError(domain: "MockFileSystem", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "openFileForWriting not implemented"
        ])
    }

    public func isExecutableFile(atPath: String) -> Bool {
        isExecutableFileHandler?(atPath) ?? false
    }
}

public protocol ProcessProtocol: AnyObject {
    var processIdentifier: Int32 { get }
    func terminate()
    func waitUntilExit()
}

extension Process: ProcessProtocol {}

public struct SpawnedProcess {
    public let process: ProcessProtocol
    public let stdinHandle: FileHandle
    public let stdoutHandle: FileHandle

    public init(process: ProcessProtocol, stdinHandle: FileHandle, stdoutHandle: FileHandle) {
        self.process = process
        self.stdinHandle = stdinHandle
        self.stdoutHandle = stdoutHandle
    }
}

public protocol ProcessSpawnerProtocol: AnyObject {
    func spawnProcess(executableURL: URL, arguments: [String]) throws -> SpawnedProcess
}

public final class RealProcessSpawner: ProcessSpawnerProtocol {
    public init() {}

    public func spawnProcess(executableURL: URL, arguments: [String]) throws -> SpawnedProcess {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        return SpawnedProcess(
            process: process,
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading
        )
    }
}

public final class MockProcessSpawner: ProcessSpawnerProtocol {
    public var spawnHandler: ((URL, [String]) throws -> SpawnedProcess)?

    public init() {}

    public func spawnProcess(executableURL: URL, arguments: [String]) throws -> SpawnedProcess {
        if let handler = spawnHandler {
            return try handler(executableURL, arguments)
        }
        throw NSError(domain: "MockProcessSpawner", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "spawnProcess not implemented"
        ])
    }
}

public struct AVOCRDependencies {
    public let output: OutputStreamProtocol
    public let errorOutput: OutputStreamProtocol
    public let fileSystem: FileSystemProtocol
    public let logger: Logger

    public init(
        output: OutputStreamProtocol = StandardOutputStream(),
        errorOutput: OutputStreamProtocol = StandardErrorStream(),
        fileSystem: FileSystemProtocol = RealFileSystem(),
        logger: Logger? = nil
    ) {
        self.output = output
        self.errorOutput = errorOutput
        self.fileSystem = fileSystem
        self.logger = logger ?? ConsoleLogger(output: errorOutput, minimumLevel: .info)
    }
}

public struct RuntimeDependencies {
    public let output: OutputStreamProtocol
    public let errorOutput: OutputStreamProtocol
    public let fileSystem: FileSystemProtocol
    public let processSpawner: ProcessSpawnerProtocol
    public let logger: Logger

    public init(
        output: OutputStreamProtocol = StandardOutputStream(),
        errorOutput: OutputStreamProtocol = StandardErrorStream(),
        fileSystem: FileSystemProtocol = RealFileSystem(),
        processSpawner: ProcessSpawnerProtocol = RealProcessSpawner(),
        logger: Logger? = nil
    ) {
        self.output = output
        self.errorOutput = errorOutput
        self.fileSystem = fileSystem
        self.processSpawner = processSpawner
        self.logger = logger ?? ConsoleLogger(output: errorOutput, minimumLevel: .info)
    }

    public var avocrDependencies: AVOCRDependencies {
        AVOCRDependencies(
            output: output,
            errorOutput: errorOutput,
            fileSystem: fileSystem,
            logger: logger
        )
    }
}
