import XCTest
@testable import AVOCRLib

final class WorkerMessageTests: XCTestCase {
    func testWorkerMessageResultRoundTrip() throws {
        let payload = WorkerResultPayload(
            id: 1,
            path: "/test/doc.pdf",
            page: 2,
            text: "Hello",
            blocks: []
        )
        let message = WorkerMessage.result(payload)

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WorkerMessage.self, from: data)

        switch decoded {
        case .result(let decodedPayload):
            XCTAssertEqual(decodedPayload.id, payload.id)
            XCTAssertEqual(decodedPayload.path, payload.path)
            XCTAssertEqual(decodedPayload.page, payload.page)
            XCTAssertEqual(decodedPayload.text, payload.text)
        case .error:
            XCTFail("Expected result payload")
        }
    }

    func testWorkerMessageErrorRoundTrip() throws {
        let payload = WorkerErrorPayload(
            id: 9,
            path: "/test/doc.pdf",
            page: nil,
            message: "Failure"
        )
        let message = WorkerMessage.error(payload)

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WorkerMessage.self, from: data)

        switch decoded {
        case .result:
            XCTFail("Expected error payload")
        case .error(let decodedPayload):
            XCTAssertEqual(decodedPayload.id, payload.id)
            XCTAssertEqual(decodedPayload.path, payload.path)
            XCTAssertNil(decodedPayload.page)
            XCTAssertEqual(decodedPayload.message, payload.message)
        }
    }
}
