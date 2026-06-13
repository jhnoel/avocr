import Foundation
import ArgumentParser

public enum ProgressFormat: String, ExpressibleByArgument {
    case bar
    case quiet
    case json
}

struct ProgressSummary {
    let completed: Int
    let failed: Int
    let skipped: Int
    let duration: TimeInterval
    let throughput: Double
}

protocol ProgressReporter {
    func start(totalPages: Int)
    func update(completedPages: Int, totalPages: Int)
    func finish(summary: ProgressSummary)
}

struct ProgressReporterFactory {
    static func makeReporter(
        format: ProgressFormat,
        enabled: Bool,
        output: OutputStreamProtocol
    ) -> ProgressReporter {
        guard enabled else {
            return QuietProgressReporter()
        }

        switch format {
        case .bar:
            return TerminalProgressReporter(output: output)
        case .quiet:
            return QuietProgressReporter()
        case .json:
            return MachineProgressReporter(output: output)
        }
    }
}

final class TerminalProgressReporter: ProgressReporter {
    private let output: OutputStreamProtocol

    init(output: OutputStreamProtocol) {
        self.output = output
    }

    func start(totalPages: Int) {}

    func update(completedPages: Int, totalPages: Int) {
        let percent = totalPages > 0
            ? min(100, Int((Double(completedPages) / Double(totalPages)) * 100.0))
            : 100
        let barWidth = Constants.progressBarWidth
        let filled = min(barWidth, Int(Double(barWidth) * (Double(percent) / 100.0)))
        let empty = max(0, barWidth - filled)
        let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: empty)
        let line = String(format: "\rProgress: [%@] %3d%% (%d/%d pages)", bar, percent, completedPages, totalPages)
        output.write(line)
        output.flush()
        if completedPages >= totalPages {
            output.write("\n")
        }
    }

    func finish(summary: ProgressSummary) {
        output.write("\n")
        output.write("Completed: \(summary.completed + summary.skipped) pages\n")
        output.write("Errors: \(summary.failed)\n")
        output.write("Duration: \(String(format: "%.1f", summary.duration))s\n")
        output.write("Throughput: \(String(format: "%.2f", summary.throughput)) pages/sec\n")
    }
}

final class QuietProgressReporter: ProgressReporter {
    func start(totalPages: Int) {}
    func update(completedPages: Int, totalPages: Int) {}
    func finish(summary: ProgressSummary) {}
}

final class MachineProgressReporter: ProgressReporter {
    private let output: OutputStreamProtocol

    init(output: OutputStreamProtocol) {
        self.output = output
    }

    func start(totalPages: Int) {
        writeJSON([
            "type": "start",
            "total": totalPages
        ])
    }

    func update(completedPages: Int, totalPages: Int) {
        let percent = totalPages > 0
            ? min(100, Int((Double(completedPages) / Double(totalPages)) * 100.0))
            : 100
        writeJSON([
            "type": "progress",
            "completed": completedPages,
            "total": totalPages,
            "percent": percent
        ])
    }

    func finish(summary: ProgressSummary) {
        writeJSON([
            "type": "summary",
            "completed": summary.completed,
            "failed": summary.failed,
            "skipped": summary.skipped,
            "duration": summary.duration,
            "throughput": summary.throughput
        ])
    }

    private func writeJSON(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        output.write(data: data)
        output.write(data: Data([0x0A]))
        output.flush()
    }
}
