import CommandInterface
import Core
import DevEnvironmentInterface
import Foundation
import Testing
@testable import DevEnvironmentImpl

/// 픽스처는 Xcode 27.1 실측 원문(파이프, stdout)의 형식 그대로다: 진행 줄은 `\r` 로 시작하고 `\n` 이 없으며,
/// 줄 끝 공백이 붙고, 한 조각에 `\r` 줄 둘이 붙어 오기도 한다. 내려받기 줄의 이름·build 는 iOS 값으로 바꿔 썼다.
struct RuntimeInstallOutputParserTests {
  private static let prefix = "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): "

  private static func downloading(_ fraction: Double, _ completed: Int64?, _ total: Int64?) -> RuntimeInstallProgress {
    RuntimeInstallProgress(
      phase: .downloading,
      fractionCompleted: fraction,
      completedBytes: completed,
      totalBytes: total
    )
  }

  private static let installing = RuntimeInstallProgress(
    phase: .installing,
    fractionCompleted: nil,
    completedBytes: nil,
    totalBytes: nil
  )

  /// stdout 조각을 순서대로 넣고 알린 진행을 모은다.
  private static func feed(
    _ chunks: [String],
    into parser: inout RuntimeInstallOutputParser
  ) -> [RuntimeInstallProgress] {
    var emitted: [RuntimeInstallProgress] = []
    for chunk in chunks {
      emitted.append(contentsOf: parser.feed(.stdout(Data(chunk.utf8))))
    }
    return emitted
  }

  // MARK: - 실측 흐름

  @Test("실측 내려받기 흐름: 첫 퍼센트부터 알리고, 같은 값 반복은 한 번만, Installing·Done 은 installing 하나")
  func measuredDownload() {
    let chunks: [String] = [
      "Finding content...\n",
      "Automatically resolved architecture variant for platform iOS as 'arm64'.\n",
      """
      \rDownloading iOS 27.1 Simulator (24A94232) (arm64): \
      \rDownloading iOS 27.1 Simulator (24A94232) (arm64): Preparing to download...
      """,
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 0.0% (73 kB of 3.76 GB) ",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 0.0% (73 kB of 3.76 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 0.0% (73 kB of 3.76 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 14.9% (558.6 MB of 3.76 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 14.9% (558.6 MB of 3.76 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 28.1% (1.05 GB of 3.76 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Installing...             ",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Done.        ",
      "\niOS 27.1 (24A94232) - 0E1F2A3B-4C5D-6E7F-8091-A2B3C4D5E6F7\n",
    ]
    var parser = RuntimeInstallOutputParser()

    let emitted = Self.feed(chunks, into: &parser)

    #expect(emitted == [
      Self.downloading(0, 73000, 3_760_000_000),
      Self.downloading(14.9 / 100, 558_600_000, 3_760_000_000),
      Self.downloading(28.1 / 100, 1_050_000_000, 3_760_000_000),
      Self.installing,
    ])
    #expect(parser.finish(exitCode: 0) == .success(.installed))
  }

  @Test("실측 이미 설치됨 4줄 + exit 0 → alreadyInstalled, 진행 알림 없음")
  func measuredAlreadyInstalled() {
    let output = """
    Finding content...
    Automatically resolved architecture variant for platform iOS as 'arm64'.
    iOS 27.1 (24A94425) - 1A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9
    iOS 27.0 (24A434) - 9F8E7D6C-5B4A-4392-8170-6F5E4D3C2B1A

    """
    var parser = RuntimeInstallOutputParser()

    #expect(Self.feed([output], into: &parser).isEmpty)
    #expect(!parser.sawDownloadLine)
    #expect(parser.finish(exitCode: 0) == .success(.alreadyInstalled))
  }

  @Test("실측 취소 출력: 우리가 취소하지 않았는데 Download was cancelled. 면 exit 70·0 모두 failed", arguments: [Int32(70), 0])
  func cancelledByTool(exitCode: Int32) {
    let chunks: [String] = [
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 14.9% (558.6 MB of 3.76 GB)",
      "\nDownload was cancelled.\n",
    ]
    var parser = RuntimeInstallOutputParser()

    _ = Self.feed(chunks, into: &parser)

    #expect(parser.cancelledByTool)
    #expect(parser.finish(exitCode: exitCode) == .failure(.failed))
  }

  @Test("0 이 아닌 종료는 내려받기 줄이 있어도 없어도 failed", arguments: [true, false])
  func nonZeroExit(downloaded: Bool) {
    var parser = RuntimeInstallOutputParser()
    if downloaded {
      _ = parser.feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 3.0% (1 GB of 3 GB)".utf8)))
    }
    #expect(parser.finish(exitCode: 1) == .failure(.failed))
  }

  // MARK: - 줄 나누기

  @Test("\\n 줄과 \\r 줄 모두에서 퍼센트를 읽는다")
  func bothSeparators() {
    var parser = RuntimeInstallOutputParser()
    let newline = parser
      .feed(.stdout(Data("Downloading iOS 27.1 Simulator (24A94232) (arm64): 10.0% (1 GB of 10 GB)\n".utf8)))
    let carriage = parser
      .feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 20.0% (2 GB of 10 GB)\r".utf8)))

    #expect(newline == [Self.downloading(0.1, 1_000_000_000, 10_000_000_000)])
    #expect(carriage == [Self.downloading(0.2, 2_000_000_000, 10_000_000_000)])
  }

  @Test("한 줄이 두 조각에 나뉘어 와도 읽는다 (잘린 임시 줄은 바이트를 쓰지 않고, 이어진 줄에서 바이트가 생기면 알린다)")
  func splitLine() {
    var parser = RuntimeInstallOutputParser()

    let first = parser
      .feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 14.9% (558.6 MB of 3.".utf8)))
    let second = parser.feed(.stdout(Data("76 GB)".utf8)))

    #expect(first == [Self.downloading(14.9 / 100, nil, nil)])
    #expect(second == [Self.downloading(14.9 / 100, 558_600_000, 3_760_000_000)])
  }

  @Test("끝나지 않은 \\r 줄도 다음 조각을 기다리지 않고 판정하고, 줄이 끝날 때 다시 알리지 않는다")
  func provisionalLineIsJudgedImmediately() {
    var parser = RuntimeInstallOutputParser()

    let open = parser
      .feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 5.0% (1 GB of 20 GB)".utf8)))
    let closed = parser.feed(.stdout(Data("\r".utf8)))

    #expect(open == [Self.downloading(0.05, 1_000_000_000, 20_000_000_000)])
    #expect(closed.isEmpty)
  }

  @Test("stdout·stderr 는 각자의 줄 버퍼로 본다 (서로의 조각이 섞이지 않는다)")
  func separateBuffers() {
    var parser = RuntimeInstallOutputParser()

    let stdout = parser.feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 1".utf8)))
    let stderr = parser.feed(.stderr(Data("warning: something\n".utf8)))
    let rest = parser.feed(.stdout(Data("2.0% (1 GB of 10 GB)".utf8)))

    #expect(stdout.isEmpty)
    #expect(stderr.isEmpty)
    #expect(rest == [Self.downloading(0.12, 1_000_000_000, 10_000_000_000)])
  }

  @Test("한 조각의 \\r 줄 둘을 각각 판정한다")
  func twoLinesInOneChunk() {
    var parser = RuntimeInstallOutputParser()
    let chunk = """
    \rDownloading iOS 27.1 Simulator (24A94232) (arm64): 1.0% (1 GB of 100 GB)\
    \rDownloading iOS 27.1 Simulator (24A94232) (arm64): 2.0% (2 GB of 100 GB)
    """

    let emitted = parser.feed(.stdout(Data(chunk.utf8)))

    #expect(emitted == [
      Self.downloading(0.01, 1_000_000_000, 100_000_000_000),
      Self.downloading(0.02, 2_000_000_000, 100_000_000_000),
    ])
  }

  @Test("멀티바이트 글자가 두 조각에 걸쳐도 깨지지 않는다")
  func multibyteAcrossChunks() {
    var parser = RuntimeInstallOutputParser()
    let bytes = Data("\rDownloading 한글 (arm64): 7.0% (1 GB of 10 GB)".utf8)
    let split = bytes.firstIndex(of: 0xED).map { $0 + 1 } ?? 1

    let first = parser.feed(.stdout(Data(bytes[..<split])))
    let second = parser.feed(.stdout(Data(bytes[split...])))

    #expect(first.isEmpty)
    #expect(second == [Self.downloading(0.07, 1_000_000_000, 10_000_000_000)])
  }

  @Test("잘못된 UTF-8 과 구분자 없는 64KB 넘는 출력에도 멈추거나 넘치지 않는다")
  func garbageInput() {
    var parser = RuntimeInstallOutputParser()

    let invalid = parser.feed(.stdout(Data([0xFF, 0xFE, 0x0A, 0xC3])))
    let huge = parser.feed(.stdout(Data(repeating: 0x41, count: 200_000)))
    let after = parser
      .feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 9.0% (1 GB of 10 GB)".utf8)))

    #expect(invalid.isEmpty)
    #expect(huge.isEmpty)
    #expect(after == [Self.downloading(0.09, 1_000_000_000, 10_000_000_000)])
    #expect(parser.finish(exitCode: 0) == .success(.installed))
  }

  // MARK: - 줄 판정

  @Test("Finding content·빈 상태·Preparing to download 는 preparing 이라 알리지 않는다 (Impl 이 먼저 알렸다)")
  func preparingIsNotRepeated() {
    var parser = RuntimeInstallOutputParser()
    let chunks: [String] = [
      "Finding content...\n",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): ",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Preparing to download...",
    ]

    #expect(Self.feed(chunks, into: &parser).isEmpty)
    #expect(parser.sawDownloadLine)
  }

  @Test("downloading 뒤 preparing 문구는 무시하고, installing 뒤 downloading 줄도 무시한다")
  func phaseDoesNotGoBack() {
    var parser = RuntimeInstallOutputParser()
    let chunks: [String] = [
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 50.0% (5 GB of 10 GB)",
      "\nFinding content...\n",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Preparing to download...",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Installing...",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 99.0% (9.9 GB of 10 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Done.        ",
    ]

    #expect(Self.feed(chunks, into: &parser) == [
      Self.downloading(0.5, 5_000_000_000, 10_000_000_000),
      Self.installing,
    ])
  }

  @Test("0.1%p 미만 변화는 알리지 않고, 쌓여서 0.1%p 가 되면 알린다. 줄어도 알린다")
  func fractionThreshold() {
    var parser = RuntimeInstallOutputParser()
    let chunks: [String] = [
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 10.00% (1 GB of 10 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 10.05% (1 GB of 10 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 10.10% (1 GB of 10 GB)",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 9.0% (0.9 GB of 10 GB)",
    ]

    let fractions: [Double?] = Self.feed(chunks, into: &parser).map(\.fractionCompleted)

    let expected: [Double?] = [10.0 / 100, 10.10 / 100, 9.0 / 100]
    #expect(fractions == expected)
  }

  @Test(
    "바이트 단위: B·kB·KB·MB·GB·TB 는 1000 진법, 모르는 단위나 괄호 없음은 바이트 nil (퍼센트는 유지)",
    arguments: [
      ("1.0% (512 B of 1000 B)", (512, 1000)),
      ("1.0% (73 kB of 3.76 GB)", (73000, 3_760_000_000)),
      ("1.0% (1.5 KB of 2 MB)", (1500, 2_000_000)),
      ("1.0% (0.01 TB of 1 TB)", (10_000_000_000, 1_000_000_000_000)),
      ("1.0% (1 XB of 2 GB)", nil),
      ("1.0%", nil),
      ("1.0% (garbage)", nil),
    ] as [(String, (Int64, Int64)?)]
  )
  func byteUnits(status: String, expected: (Int64, Int64)?) {
    var parser = RuntimeInstallOutputParser()
    let line = "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): \(status)\n"
    let emitted = parser.feed(.stdout(Data(line.utf8)))
    #expect(emitted == [Self.downloading(0.01, expected?.0, expected?.1)])
  }

  @Test("100 을 넘는 퍼센트는 1.0 으로 자른다")
  func clampsFraction() {
    var parser = RuntimeInstallOutputParser()
    let emitted = parser
      .feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 100.4% (3 GB of 3 GB)\n".utf8)))
    #expect(emitted.first?.fractionCompleted == 1.0)
  }

  @Test(
    "이름 부분이 추정과 달라도, ): 가 없어도 퍼센트를 읽는다",
    arguments: [
      "Downloading iOS 27.1 (24A94232): 3.0% (1 GB of 10 GB)",
      "Downloading... (3.0% (1 GB of 10 GB)",
      "Downloading iOS 27.1 Simulator 3.0% (1 GB of 10 GB)",
    ]
  )
  func unexpectedName(line: String) {
    var parser = RuntimeInstallOutputParser()
    let emitted = parser.feed(.stdout(Data("\(line)\n".utf8)))
    #expect(emitted.first?.fractionCompleted == 0.03)
    #expect(emitted.first?.phase == .downloading)
  }

  @Test("퍼센트를 읽지 못한 내려받기 줄은 진행을 바꾸지 않지만 내려받기로 본다")
  func unreadableDownloadLine() {
    var parser = RuntimeInstallOutputParser()
    let emitted = parser.feed(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Verifying...\n".utf8)))
    #expect(emitted.isEmpty)
    #expect(parser.finish(exitCode: 0) == .success(.installed))
  }
}
