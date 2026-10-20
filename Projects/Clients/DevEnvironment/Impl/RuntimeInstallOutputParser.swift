import CommandInterface
import Core
import DevEnvironmentInterface
import Foundation

/// `xcodebuild -downloadPlatform iOS` 출력에서 진행과 결과를 읽는다 (순수, iOS 전용).
/// 실측(Xcode 27.1, 파이프): 모두 stdout. 이미 설치됨이면 `Finding content...`·`Automatically resolved …` 와
/// 설치된 런타임 목록(`iOS 27.1 (<build>) - <UUID>`)만 찍고 exit 0. 내려받기는 `\r` 로 시작하는 줄을 약 1초마다
/// `Downloading <이름> (<build>) (<arch>): <상태>` 로 덮어쓰고(줄 끝 공백 채움, 같은 값 반복), 상태는 빈 문자열 →
/// `Preparing to download...` → `14.9% (558.6 MB of 3.76 GB)` → `Installing...` → `Done.` 순서다.
/// 해석하지 못한 줄은 진행을 바꾸지 않는다. 성공 판정은 종료 코드와 xcodebuild 의 취소 알림
/// (`Download was cancelled.`)으로 한다 (`finish`). `Done.` 같은 진행 문구는 성공으로 보지 않는다.
struct RuntimeInstallOutputParser {
  /// 구분자 없이 이보다 길게 쌓이면 앞을 버린다.
  static let maxLineLength = 65536

  private var stdoutBuffer = Data()
  private var stderrBuffer = Data()
  /// 지금까지 읽은 진행 (phase 는 뒤로 가지 않는다).
  private var current = RuntimeInstallProgress.preparing
  /// 직전에 알린 진행. Impl 이 실행 전에 `.preparing` 을 먼저 알리므로 초기값도 `.preparing`.
  private var lastEmitted = RuntimeInstallProgress.preparing
  /// `Downloading` 으로 시작하는 줄을 봤다 (내려받기를 시작했다. 끝났는지는 종료 코드와 취소 알림으로 본다).
  private(set) var sawDownloadLine = false
  /// xcodebuild 가 `Download was cancelled.` 를 찍었다.
  private(set) var cancelledByTool = false

  /// 조각을 받아 알릴 진행을 순서대로 돌려준다 (바뀐 것만). stdout·stderr 는 각자의 줄 버퍼로 본다.
  /// 끝나지 않은 마지막 줄도 매번 임시로 판정해 지연 없이 알린다 (진행 줄은 `\r` 로 시작해 다음 줄이 와야 끝난다).
  /// 줄 자르기는 시작 인덱스를 옮겨 한 번에 한다 (출력 길이에 선형). Data 슬라이스의 인덱스는 0 부터라고 가정하지 않는다.
  mutating func feed(_ output: CommandOutput) -> [RuntimeInstallProgress] {
    switch output {
    case let .stdout(data):
      var buffer = self.stdoutBuffer
      let emitted = self.feed(data, buffer: &buffer)
      self.stdoutBuffer = buffer
      return emitted
    case let .stderr(data):
      var buffer = self.stderrBuffer
      let emitted = self.feed(data, buffer: &buffer)
      self.stderrBuffer = buffer
      return emitted
    }
  }

  /// 끝난 명령의 전체 출력으로 결과를 정한다 (순수). 새 해석기에 stdout 전체 → stderr 전체를 넣고(진행은 버린다)
  /// `finish` 한 것과 같다. 진행 알림용 해석기가 받지 못한 조각(늦게 온 취소)이 있어도 결과는 전체 출력을 따른다.
  static func outcome(
    stdout: Data,
    stderr: Data,
    exitCode: Int32
  ) -> Result<RuntimeInstallOutcome, RuntimeInstallError> {
    var parser = RuntimeInstallOutputParser()
    _ = parser.feed(.stdout(stdout))
    _ = parser.feed(.stderr(stderr))
    return parser.finish(exitCode: exitCode)
  }

  /// 종료 코드와 지금까지 본 줄로 결과를 정한다 (Impl 이 우리 쪽 취소를 먼저 처리한다).
  /// exit ≠ 0 이거나 xcodebuild 가 취소했다고 알렸으면 `.failed`, 그 밖에 내려받기 줄이 있었으면 `.installed`,
  /// 없었으면 `.alreadyInstalled`.
  mutating func finish(exitCode: Int32) -> Result<RuntimeInstallOutcome, RuntimeInstallError> {
    let remaining: [Data] = [self.stdoutBuffer, self.stderrBuffer]
    self.stdoutBuffer = Data()
    self.stderrBuffer = Data()
    for line in remaining where !line.isEmpty {
      _ = self.judge(line, provisional: false)
    }
    guard exitCode == 0, !self.cancelledByTool else {
      return .failure(.failed)
    }
    return .success(self.sawDownloadLine ? .installed : .alreadyInstalled)
  }

  // MARK: - 줄 나누기

  private mutating func feed(_ data: Data, buffer: inout Data) -> [RuntimeInstallProgress] {
    buffer.append(data)
    var emitted: [RuntimeInstallProgress] = []
    // 바이트에서 `\r`·`\n` 으로 먼저 자른 뒤 디코딩한다 (조각 경계가 UTF-8 글자 가운데여도 깨지지 않는다).
    // 시작 인덱스만 옮기며 줄만 복사하고, 남은 부분은 끝에서 한 번만 복사한다.
    var start = buffer.startIndex
    while let index = buffer[start...].firstIndex(where: { $0 == 0x0D || $0 == 0x0A }) {
      let line = Data(buffer[start ..< index])
      start = buffer.index(after: index)
      if let progress = self.judge(line, provisional: false) {
        emitted.append(progress)
      }
    }
    buffer = Data(buffer[start...])
    if buffer.count > Self.maxLineLength {
      buffer = Data(buffer.suffix(Self.maxLineLength))
    }
    if !buffer.isEmpty, let progress = self.judge(buffer, provisional: true) {
      emitted.append(progress)
    }
    return emitted
  }

  // MARK: - 줄 판정

  /// 줄 하나를 판정해, 알릴 만큼 바뀌었으면 그 진행. UTF-8 이 아닌 줄은 무시한다 (진행 줄은 ASCII 다).
  /// `provisional`: 아직 끝나지 않은 줄. 상태가 `)` 로 끝날 때만 바이트를 쓴다 (잘린 바이트를 쓰지 않는다).
  private mutating func judge(_ bytes: Data, provisional: Bool) -> RuntimeInstallProgress? {
    guard let line = String(bytes: bytes, encoding: .utf8) else {
      return nil
    }
    let leading = line.drop(while: \.isWhitespace)
    guard !leading.isEmpty else {
      return nil
    }
    let candidate: RuntimeInstallProgress?
    if leading.hasPrefix("Downloading") {
      self.sawDownloadLine = true
      candidate = Self.downloadProgress(String(leading), provisional: provisional)
    } else {
      let trimmed = leading.trimmingCharacters(in: .whitespaces)
      if trimmed == "Finding content..." {
        candidate = .preparing
      } else if trimmed == "Download was cancelled." {
        self.cancelledByTool = true
        candidate = nil
      } else {
        candidate = nil
      }
    }
    guard let candidate else {
      return nil
    }
    return self.update(candidate)
  }

  /// 내려받기 줄의 상태 부분. 이름 부분(`iOS 27.1 Simulator (…) (arm64)`)은 읽지 않는다.
  /// 상태는 마지막 `):` 뒤를 앞뒤 공백 제거한 것이고, `):` 가 없으면 줄 전체에서 퍼센트를 찾는다.
  static func downloadProgress(_ line: String, provisional: Bool) -> RuntimeInstallProgress? {
    let status: String
    if let range = line.range(of: "):", options: .backwards) {
      status = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
      if status.isEmpty || status == "Preparing to download..." {
        return .preparing
      }
      if status == "Installing..." || status == "Done." {
        return RuntimeInstallProgress(phase: .installing, fractionCompleted: nil, completedBytes: nil, totalBytes: nil)
      }
    } else {
      status = line.trimmingCharacters(in: .whitespaces)
    }
    return Self.percentProgress(status, provisional: provisional)
  }

  /// `<수>% (<수> <단위> of <수> <단위>)`. 퍼센트를 못 읽으면 nil, 괄호를 못 읽으면 바이트만 nil.
  static func percentProgress(_ text: String, provisional: Bool) -> RuntimeInstallProgress? {
    guard let percentIndex = text.firstIndex(of: "%") else {
      return nil
    }
    var numberStart = percentIndex
    while numberStart > text.startIndex {
      let previous = text.index(before: numberStart)
      guard text[previous].isASCII, text[previous].isNumber || text[previous] == "." else {
        break
      }
      numberStart = previous
    }
    guard let percent = Double(text[numberStart ..< percentIndex]) else {
      return nil
    }
    let fraction = min(max(percent / 100, 0), 1)
    let rest = text[text.index(after: percentIndex)...]
    var bytes: (completed: Int64, total: Int64)?
    if !provisional || rest.hasSuffix(")") {
      bytes = Self.byteCounts(rest)
    }
    return RuntimeInstallProgress(
      phase: .downloading,
      fractionCompleted: fraction,
      completedBytes: bytes?.completed,
      totalBytes: bytes?.total
    )
  }

  /// ` (558.6 MB of 3.76 GB)` 의 두 크기. 단위는 1000 진법 (`kB` 소문자는 `ByteCountFormatter` 의 10진 표기와 같다).
  static func byteCounts(_ text: Substring) -> (completed: Int64, total: Int64)? {
    guard
      let open = text.firstIndex(of: "("),
      let close = text[open...].firstIndex(of: ")")
    else {
      return nil
    }
    let inner = text[text.index(after: open) ..< close]
    guard let separator = inner.range(of: " of ") else {
      return nil
    }
    guard
      let completed = Self.byteCount(inner[..<separator.lowerBound]),
      let total = Self.byteCount(inner[separator.upperBound...])
    else {
      return nil
    }
    return (completed, total)
  }

  /// `558.6 MB` → 558_600_000. 단위를 모르면 nil.
  static func byteCount(_ text: Substring) -> Int64? {
    let parts = text.split(separator: " ")
    guard parts.count == 2, let value = Double(parts[0]), value >= 0 else {
      return nil
    }
    let multiplier: Double
    switch parts[1] {
    case "B": multiplier = 1
    case "kB", "KB": multiplier = 1e3
    case "MB": multiplier = 1e6
    case "GB": multiplier = 1e9
    case "TB": multiplier = 1e12
    default: return nil
    }
    let bytes: Double = (value * multiplier).rounded()
    guard bytes < Double(Int64.max) else {
      return nil
    }
    return Int64(bytes)
  }

  // MARK: - 알림 판정

  /// phase 는 뒤로 가지 않는다. 직전 알림과 phase 가 다르거나, 퍼센트가 0.1%p 이상 바뀌었거나(줄어도),
  /// 바이트가 nil 에서 값으로 바뀌었을 때만 알린다 (실측: 같은 값 줄이 1초마다 반복된다).
  private mutating func update(_ candidate: RuntimeInstallProgress) -> RuntimeInstallProgress? {
    guard Self.rank(candidate.phase) >= Self.rank(self.current.phase) else {
      return nil
    }
    self.current = candidate
    guard Self.isNotable(candidate, since: self.lastEmitted) else {
      return nil
    }
    self.lastEmitted = candidate
    return candidate
  }

  static func isNotable(_ next: RuntimeInstallProgress, since last: RuntimeInstallProgress) -> Bool {
    if next.phase != last.phase {
      return true
    }
    if last.completedBytes == nil, next.completedBytes != nil {
      return true
    }
    switch (last.fractionCompleted, next.fractionCompleted) {
    case let (last?, next?):
      // 퍼센트는 소수 한 자리라 0.149 - 0.148 이 0.001 보다 조금 작게 나온다.
      return abs(next - last) >= 0.001 - 1e-9
    case (nil, .some):
      return true
    default:
      return false
    }
  }

  private static func rank(_ phase: RuntimeInstallProgress.Phase) -> Int {
    switch phase {
    case .preparing: 0
    case .downloading: 1
    case .installing: 2
    }
  }
}
