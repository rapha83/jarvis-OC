import Foundation
@preconcurrency import Vision

final class ScreenOCRService {
    enum OCRError: LocalizedError {
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .recognitionFailed(let message):
                return message
            }
        }
    }

    func recognizeText(in image: CGImage, maxCharacters: Int = 2800) async throws -> String {
        let lines: [String] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let output = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                continuation.resume(returning: output)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["pt-BR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                }
            }
        }

        return Self.compact(lines: lines, maxCharacters: maxCharacters)
    }

    private static func compact(lines: [String], maxCharacters: Int) -> String {
        var seen = Set<String>()
        var output: [String] = []

        for line in lines {
            let normalized = line
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            output.append(line)
        }

        let joined = output.joined(separator: "\n")
        guard joined.count > maxCharacters else {
            return joined
        }
        let index = joined.index(joined.startIndex, offsetBy: maxCharacters)
        return String(joined[..<index]) + "\n[OCR truncado]"
    }
}
