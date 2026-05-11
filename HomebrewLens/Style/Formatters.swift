import Foundation
import AppKit

// MARK: - Formatters & Helpers

enum AppFormatters {
    static func size(_ value: Int64?) -> String {
        guard let value else {
            return "unknown"
        }

        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        byteFormatter.countStyle = .file
        return byteFormatter.string(fromByteCount: value)
    }

    static func duration(_ value: Duration?) -> String {
        guard let value else {
            return "--"
        }

        let components = value.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return String(format: "%.2fs", seconds)
    }

    static func date(_ value: Date?) -> String {
        guard let value else {
            return "unknown"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: value)
    }

    static func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
