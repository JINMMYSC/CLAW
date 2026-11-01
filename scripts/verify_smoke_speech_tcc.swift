import Foundation

// Startup Smoke never taps a microphone or permission-guide control. Any
// Speech Recognition prompt attributed to the Host is therefore unexpected.
// This checks simulator TCC evidence independently of screenshot OCR.
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  fputs("usage: swift verify_smoke_speech_tcc.swift smoke-system.log\n", stderr)
  exit(2)
}

let log: String
do {
  log = try String(contentsOfFile: arguments[1], encoding: .utf8)
} catch {
  fputs("::error::Speech TCC audit could not read simulator log\n", stderr)
  exit(2)
}
let lines = log.components(separatedBy: .newlines)
guard lines.contains(where: { $0.contains("Hamster[") || $0.contains("app.lgm.7517") }) else {
  fputs("::error::Speech TCC audit has no Host evidence; refusing a false pass\n", stderr)
  exit(2)
}
let prompts = lines.filter {
  $0.contains("AUTHREQ_PROMPTING") &&
  $0.contains("service=kTCCServiceSpeechRecognition") &&
  $0.contains("subject=Sub:{app.lgm.7517}")
}
if prompts.isEmpty {
  print("[claw-smoke] No unsolicited Host Speech Recognition prompt in captured simulator log")
} else {
  for line in prompts {
    let timestamp = String(line.prefix(23))
    fputs("::error::Unsolicited Host Speech Recognition prompt at \(timestamp)\n", stderr)
  }
  exit(1)
}
