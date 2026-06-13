import Foundation

struct WorkerTask: Codable {
    let id: Int
    let path: String
    let page: Int?
}

struct WorkerBBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct WorkerTextBlock: Codable {
    let text: String
    let confidence: Float
    let bbox: WorkerBBox
}

struct WorkerResultPayload: Codable {
    let id: Int
    let path: String
    let page: Int?
    let text: String
    let blocks: [WorkerTextBlock]
    let usedExistingText: Bool

    init(
        id: Int,
        path: String,
        page: Int?,
        text: String,
        blocks: [WorkerTextBlock],
        usedExistingText: Bool = false
    ) {
        self.id = id
        self.path = path
        self.page = page
        self.text = text
        self.blocks = blocks
        self.usedExistingText = usedExistingText
    }
}

struct WorkerErrorPayload: Codable {
    let id: Int
    let path: String
    let page: Int?
    let message: String
}

enum WorkerMessage: Codable {
    case result(WorkerResultPayload)
    case error(WorkerErrorPayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case path
        case page
        case text
        case blocks
        case usedExistingText
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "result":
            let payload = WorkerResultPayload(
                id: try container.decode(Int.self, forKey: .id),
                path: try container.decode(String.self, forKey: .path),
                page: try container.decodeIfPresent(Int.self, forKey: .page),
                text: try container.decode(String.self, forKey: .text),
                blocks: try container.decode([WorkerTextBlock].self, forKey: .blocks),
                usedExistingText: try container.decodeIfPresent(Bool.self, forKey: .usedExistingText) ?? false
            )
            self = .result(payload)
        case "error":
            let payload = WorkerErrorPayload(
                id: try container.decode(Int.self, forKey: .id),
                path: try container.decode(String.self, forKey: .path),
                page: try container.decodeIfPresent(Int.self, forKey: .page),
                message: try container.decode(String.self, forKey: .message)
            )
            self = .error(payload)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported worker message type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .result(let payload):
            try container.encode("result", forKey: .type)
            try container.encode(payload.id, forKey: .id)
            try container.encode(payload.path, forKey: .path)
            try container.encodeIfPresent(payload.page, forKey: .page)
            try container.encode(payload.text, forKey: .text)
            try container.encode(payload.blocks, forKey: .blocks)
            try container.encode(payload.usedExistingText, forKey: .usedExistingText)
        case .error(let payload):
            try container.encode("error", forKey: .type)
            try container.encode(payload.id, forKey: .id)
            try container.encode(payload.path, forKey: .path)
            try container.encodeIfPresent(payload.page, forKey: .page)
            try container.encode(payload.message, forKey: .message)
        }
    }
}
