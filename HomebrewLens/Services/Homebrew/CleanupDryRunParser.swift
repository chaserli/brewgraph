import Foundation

struct CleanupDryRunParser {
    static func parse(_ output: String) -> CleanupSummary {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return CleanupSummary(
            lines: lines,
            reclaimText: lines.compactMap(reclaimText).last
        )
    }

    private static func reclaimText(from line: String) -> String? {
        let lowercased = line.lowercased()
        guard lowercased.contains("would free") || lowercased.contains("will free") || lowercased.contains("reclaim") else {
            return nil
        }

        let pattern = #"(?i)(\d+(?:\.\d+)?\s*(?:B|KB|MB|GB|TB))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.matches(in: line, range: range).last,
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        return String(line[valueRange])
    }
}
