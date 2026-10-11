import Foundation
import CoreGraphics
import ImageIO
import Vision

enum BatteryPart: String, CaseIterable, Identifiable, Hashable, Sendable {
    case left, right, caseLevel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: return "左耳"
        case .right: return "右耳"
        case .caseLevel: return "充电盒"
        }
    }
}

struct BatteryCandidate: Identifiable, Sendable {
    let id: UUID
    let text: String
    let value: Int?
    let part: BatteryPart?
    /// Vision normalized coordinates, with the origin at the bottom left.
    let bounds: CGRect
}

enum BatteryOCRService {
    static func recognize(imageData: Data) async throws -> [BatteryCandidate] {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try autoreleasepool {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = false
                var orientation = CGImagePropertyOrientation.up
                if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                   let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                   let value = properties[kCGImagePropertyOrientation as String] as? NSNumber {
                    orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) ?? .up
                }
                let handler = VNImageRequestHandler(data: imageData, orientation: orientation, options: [:])
                try handler.perform([request])
                try Task.checkCancellation()
                let expression = try NSRegularExpression(pattern: "(?<![0-9.,-])([0-9]{1,3})\\s*[%％](?![0-9])")
                return (request.results ?? []).flatMap { observation -> [BatteryCandidate] in
                    guard let recognized = observation.topCandidates(1).first else { return [] }
                    let text = recognized.string.folding(options: .widthInsensitive, locale: nil)
                    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
                    let matches = expression.matches(in: text, range: fullRange)
                    return matches.enumerated().map { index, match in
                        let valueRange = Range(match.range(at: 1), in: text)!
                        let number = Int(text[valueRange])
                        let precedingEnd = index == 0 ? 0 : NSMaxRange(matches[index - 1].range)
                        let labelRange = NSRange(location: precedingEnd, length: match.range.location - precedingEnd)
                        let label = Range(labelRange, in: text).map { String(text[$0]) } ?? ""
                        var suggestion = suggestedPart(in: label)
                        // A trailing label is safe to suggest only when the line has one percentage.
                        if suggestion == nil, matches.count == 1 {
                            let suffixRange = NSRange(location: NSMaxRange(match.range), length: fullRange.length - NSMaxRange(match.range))
                            let suffix = Range(suffixRange, in: text).map { String(text[$0]) } ?? ""
                            suggestion = suggestedPart(in: suffix)
                        }
                        return BatteryCandidate(id: UUID(), text: recognized.string,
                                                value: number.flatMap { (0...100).contains($0) ? $0 : nil },
                                                part: suggestion, bounds: observation.boundingBox)
                    }
                }.sorted {
                    if $0.bounds.midY != $1.bounds.midY { return $0.bounds.midY > $1.bounds.midY }
                    return $0.bounds.minX < $1.bounds.minX
                }
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func suggestedPart(in text: String) -> BatteryPart? {
        let lower = text.lowercased()
        var found: [BatteryPart] = []
        if lower.contains("左") || lower.range(of: "\\bleft\\b|\\bl\\b", options: .regularExpression) != nil { found.append(.left) }
        if lower.contains("右") || lower.range(of: "\\bright\\b|\\br\\b", options: .regularExpression) != nil { found.append(.right) }
        if lower.contains("盒") || lower.range(of: "\\bcase\\b", options: .regularExpression) != nil { found.append(.caseLevel) }
        return found.count == 1 ? found.first : nil
    }
}
