import XCTest
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

    private static func makeDependencies(processSpawner: ProcessSpawnerProtocol) -> RuntimeDependencies {
        RuntimeDependencies(
            output: InMemoryOutputStream(),
            errorOutput: InMemoryOutputStream(),
            processSpawner: processSpawner,
            logger: NullLogger()
        )
    }

    private func makeDependencies(processSpawner: ProcessSpawnerProtocol) -> RuntimeDependencies {
        Self.makeDependencies(processSpawner: processSpawner)
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
