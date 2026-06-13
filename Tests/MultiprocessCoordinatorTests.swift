import XCTest
import CoreGraphics
import PDFKit
import AppKit
@testable import AVOCRLib

final class MultiprocessCoordinatorTests: XCTestCase {
    func testWorkerLineBufferParsesFragmentedLinesWithoutDroppingRemainder() throws {
        var buffer = WorkerLineBuffer()

        XCTAssertTrue(buffer.append(Data(#"{"id":0}"#.utf8)).isEmpty)

        let firstLines = buffer.append(Data("\n{\"id\":1".utf8))
        XCTAssertEqual(firstLines.map { String(decoding: $0, as: UTF8.self) }, [#"{"id":0}"#])

        let secondLines = buffer.append(Data("}\n\n".utf8))
        XCTAssertEqual(secondLines.map { String(decoding: $0, as: UTF8.self) }, [#"{"id":1}"#])
    }

    func testFailFastStopsAssigningNewTasksAfterFirstWorkerError() throws {
        let harness = WorkerHarness()
        let spawner = MockProcessSpawner()
        spawner.spawnHandler = { _, _ in harness.spawnedProcess() }

        harness.respondToTasks { task in
            WorkerMessage.error(WorkerErrorPayload(
                id: task.id,
                path: task.path,
                page: task.page,
                message: "failed"
            ))
        }

        var args = makeMultiprocessArgs()
        args.failFast = true

        let result = try MultiprocessCoordinator.runMultiprocess(
            files: makeImageURLs(count: 3),
            args: args,
            dependencies: makeDependencies(processSpawner: spawner)
        )

        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(harness.receivedTaskIDs, [0])
    }

    func testMaxErrorsStopsAssigningNewTasksAtThreshold() throws {
        let harness = WorkerHarness()
        let spawner = MockProcessSpawner()
        spawner.spawnHandler = { _, _ in harness.spawnedProcess() }

        harness.respondToTasks { task in
            WorkerMessage.error(WorkerErrorPayload(
                id: task.id,
                path: task.path,
                page: task.page,
                message: "failed"
            ))
        }

        var args = makeMultiprocessArgs()
        args.maxErrors = 1

        let result = try MultiprocessCoordinator.runMultiprocess(
            files: makeImageURLs(count: 3),
            args: args,
            dependencies: makeDependencies(processSpawner: spawner)
        )

        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(harness.receivedTaskIDs, [0])
    }

    func testWorkerEOFMarksInflightTasksFailedAndReturns() {
        let harness = WorkerHarness()
        let spawner = MockProcessSpawner()
        spawner.spawnHandler = { _, _ in
            harness.closeWorkerOutput()
            return harness.spawnedProcess()
        }

        var args = makeMultiprocessArgs()
        args.gracefulTimeout = 0

        let expectation = expectation(description: "multiprocess returns after worker EOF")
        var result: ProcessingResult?
        var thrownError: Error?

        DispatchQueue.global().async {
            do {
                result = try MultiprocessCoordinator.runMultiprocess(
                    files: Self.makeImageURLs(count: 1),
                    args: args,
                    dependencies: Self.makeDependencies(processSpawner: spawner)
                )
            } catch {
                thrownError = error
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        XCTAssertNil(thrownError)
        XCTAssertEqual(result?.failed, 1)
    }

    func testStdoutMultipagePDFResultsStayInPageOrderWhenWorkersFinishOutOfOrder() throws {
        let pdfURL = try Self.createMultiPagePDF(pageCount: 2)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let firstWorker = WorkerHarness()
        let secondWorker = WorkerHarness()
        let spawner = MockProcessSpawner()
        var spawnCount = 0
        spawner.spawnHandler = { _, _ in
            defer { spawnCount += 1 }
            return spawnCount == 0 ? firstWorker.spawnedProcess() : secondWorker.spawnedProcess()
        }

        firstWorker.respondToTasks { task in
            Thread.sleep(forTimeInterval: 0.15)
            return WorkerMessage.result(WorkerResultPayload(
                id: task.id,
                path: task.path,
                page: task.page,
                text: "first page",
                blocks: []
            ))
        }
        secondWorker.respondToTasks { task in
            WorkerMessage.result(WorkerResultPayload(
                id: task.id,
                path: task.path,
                page: task.page,
                text: "second page",
                blocks: []
            ))
        }

        var args = makeMultiprocessArgs()
        args.workers = JobsValue(argument: "2")
        args.noHeaders = true
        let output = InMemoryOutputStream()

        let result = try MultiprocessCoordinator.runMultiprocess(
            files: [pdfURL],
            args: args,
            dependencies: makeDependencies(output: output, processSpawner: spawner)
        )

        XCTAssertEqual(result.completed, 2)
        let text = output.text
        let firstRange = try XCTUnwrap(text.range(of: "first page"))
        let secondRange = try XCTUnwrap(text.range(of: "second page"))
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
    }

    private static func makeImageURLs(count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/input-\($0).jpg") }
    }

    private func makeImageURLs(count: Int) -> [URL] {
        Self.makeImageURLs(count: count)
    }

    private func makeMultiprocessArgs() -> CLIArgs {
        var args = CLIArgs()
        args.inputs = ["/tmp"]
        args.workers = JobsValue(argument: "1")
        args.prefetch = 1
        args.output = nil
        args.stdout = true
        args.noProgress = true
        args.progress = false
        args.progressFormat = .quiet
        return args
    }

    private static func makeDependencies(
        output: OutputStreamProtocol = InMemoryOutputStream(),
        processSpawner: ProcessSpawnerProtocol
    ) -> RuntimeDependencies {
        RuntimeDependencies(
            output: output,
            errorOutput: InMemoryOutputStream(),
            processSpawner: processSpawner,
            logger: NullLogger()
        )
    }

    private func makeDependencies(
        output: OutputStreamProtocol = InMemoryOutputStream(),
        processSpawner: ProcessSpawnerProtocol
    ) -> RuntimeDependencies {
        Self.makeDependencies(output: output, processSpawner: processSpawner)
    }

    private static func createMultiPagePDF(pageCount: Int) throws -> URL {
        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        let image = makeTestImage(width: 100, height: 100)
        let nsImage = NSImage(cgImage: image, size: NSSize(width: 100, height: 100))
        let document = PDFDocument()
        for pageIndex in 0..<pageCount {
            if let page = PDFPage(image: nsImage) {
                document.insert(page, at: pageIndex)
            }
        }
        guard let data = document.dataRepresentation() else {
            throw OCRError.ocrFailed("Unable to create PDF")
        }
        try data.write(to: pdfURL)
        return pdfURL
    }

    private static func makeTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

private final class WorkerHarness {
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let lock = NSLock()
    private var tasks: [WorkerTask] = []

    var receivedTaskIDs: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return tasks.map(\.id)
    }

    func spawnedProcess() -> SpawnedProcess {
        SpawnedProcess(
            process: MockRunningProcess(),
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading
        )
    }

    func closeWorkerOutput() {
        try? stdoutPipe.fileHandleForWriting.close()
    }

    func respondToTasks(_ response: @escaping (WorkerTask) -> WorkerMessage) {
        let reader = stdinPipe.fileHandleForReading
        let writer = stdoutPipe.fileHandleForWriting
        DispatchQueue.global().async {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            var buffer = Data()

            while true {
                let data = reader.availableData
                if data.isEmpty {
                    try? writer.close()
                    return
                }

                buffer.append(data)
                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: 0..<newlineIndex)
                    buffer.removeSubrange(0...newlineIndex)
                    guard !lineData.isEmpty,
                          let task = try? decoder.decode(WorkerTask.self, from: lineData)
                    else { continue }

                    self.lock.lock()
                    self.tasks.append(task)
                    self.lock.unlock()

                    if let outputData = try? encoder.encode(response(task)) {
                        writer.write(outputData)
                        writer.write(Data([0x0A]))
                    }
                }
            }
        }
    }
}

private final class MockRunningProcess: ProcessProtocol {
    var processIdentifier: Int32 { 0 }
    func terminate() {}
    func waitUntilExit() {}
}
