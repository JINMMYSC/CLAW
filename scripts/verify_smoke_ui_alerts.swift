// Fail closed when a system permission dialog obscures a CLAW startup/UI screenshot.
// Run on the macOS GitHub Actions runner: swift scripts/verify_smoke_ui_alerts.swift <png...>
// Vision is built into macOS; no network service or OCR upload is involved.
import Foundation
import ImageIO
import Vision
import Darwin

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
  fputs("::error::No smoke screenshots supplied for visual alert verification\n", stderr)
  exit(2)
}

var failures: [String] = []
for path in paths {
  let url = URL(fileURLWithPath: path)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    failures.append("\(path): cannot decode PNG")
    continue
  }

  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = false
  request.recognitionLanguages = ["en-US"]
  do {
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
  } catch {
    failures.append("\(path): native Vision OCR failed")
    continue
  }

  let recognized = (request.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string }
  guard recognized.count >= 3 else {
    failures.append("\(path): insufficient readable UI to establish visibility")
    continue
  }

  // Join lines before normalization: Apple's dialog splits its title and
  // explanatory sentence across multiple OCR observations.
  let letters = recognized.joined(separator: " ").lowercased()
    .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
  if letters.contains("speechrecognit") || letters.contains("wouldliketoaccess")
      || (letters.contains("dontallow") && letters.contains("allow")) {
    failures.append("\(path): system authorization dialog obscures the UI")
  } else {
    print("Visible smoke screenshot: \(path) (\(recognized.count) text regions)")
  }
}

if !failures.isEmpty {
  for failure in failures { fputs("::error::\(failure)\n", stderr) }
  exit(1)
}
print("All \(paths.count) smoke screenshots passed the native Vision dialog check")
