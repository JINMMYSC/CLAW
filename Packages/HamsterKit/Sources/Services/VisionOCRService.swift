import Foundation
import UIKit
import Vision

/// 本地 OCR 服务：识别聊天截图文字（不联网、不花 token）
public class VisionOCRService {
  public static let shared = VisionOCRService()

  public struct OCRLine: Equatable {
    public let text: String
    /// Vision normalized coordinates (origin at lower-left).
    public let boundingBox: CGRect
    public let confidence: Float

    public init(text: String, boundingBox: CGRect, confidence: Float) {
      self.text = text
      self.boundingBox = boundingBox
      self.confidence = confidence
    }
  }

  public enum OCRError: Error {
    case invalidImage
  }

  public func recognizeText(in image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
    recognizeLines(in: image) { result in
      switch result {
      case .success(let lines):
        completion(.success(lines.map(\.text).joined(separator: "\n")))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  /// OCR with geometry, used by screenshot chat ingestion to infer left/right speaker bubbles.
  public func recognizeLines(in image: UIImage, completion: @escaping (Result<[OCRLine], Error>) -> Void) {
    guard let cgImage = image.cgImage else {
      completion(.failure(OCRError.invalidImage))
      return
    }
    let request = VNRecognizeTextRequest { request, error in
      if let error {
        DispatchQueue.main.async { completion(.failure(error)) }
        return
      }
      let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { observation -> OCRLine? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return OCRLine(text: candidate.string, boundingBox: observation.boundingBox, confidence: candidate.confidence)
      } ?? []
      let sorted = lines.sorted {
        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.015 { return $0.boundingBox.midY > $1.boundingBox.midY }
        return $0.boundingBox.minX < $1.boundingBox.minX
      }
      DispatchQueue.main.async { completion(.success(sorted)) }
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async { completion(.failure(error)) }
      }
    }
  }
}
Process exited with code 0.