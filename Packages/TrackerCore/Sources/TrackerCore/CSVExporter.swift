import Foundation

public enum CSVExporter {
    public static func sessions(_ sessions: [UsageSession], timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        let header = ["记录编号", "设备编号", "开始", "结束", "显示时区", "来源", "状态", "已确认秒数", "标签", "备注", "核对原因"]
        let rows = sessions.map { session -> [String] in
            let duration: String
            if session.status == .confirmed, let start = session.start, let end = session.end, end > start {
                duration = String(Int(end.timeIntervalSince(start)))
            } else { duration = "" }
            return [session.id.uuidString, session.deviceID.uuidString, session.start.map { formatter.string(from: $0) } ?? "", session.end.map { formatter.string(from: $0) } ?? "", timeZone.identifier, session.source == .shortcut ? "自动化" : "手动", statusName(session.status), duration, session.tag ?? "", session.note ?? "", session.issue ?? ""]
        }
        return "\u{FEFF}" + ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    private static func statusName(_ status: SessionStatus) -> String {
        switch status { case .confirmed: return "已确认"; case .awaitingEnd: return "等待断开"; case .needsReview: return "待核对"; case .excluded: return "已排除" }
    }
    private static func escape(_ value: String) -> String {
        // Spreadsheet formulas in user notes must remain text when a CSV is opened in Excel.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = ["=", "+", "-", "@"].contains(where: { trimmed.hasPrefix($0) }) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
