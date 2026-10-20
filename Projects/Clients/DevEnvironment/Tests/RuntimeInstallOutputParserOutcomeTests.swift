import CommandInterface
import Core
import DevEnvironmentInterface
import Foundation
import Testing
@testable import DevEnvironmentImpl

/// `RuntimeInstallOutputParser.outcome`: 끝난 명령의 전체 출력으로 결과를 정한다 (늦게 온 취소로 넘기지 못한 조각이 있어도).
/// 픽스처 형식은 `RuntimeInstallOutputParserTests` 와 같다 (실측 원문, 이름·build 만 iOS 값).
struct RuntimeInstallOutputParserOutcomeTests {
  @Test(
    "outcome 은 같은 출력을 조각으로 넘긴 뒤 finish 한 결과와 같다 (내려받기·이미 설치됨·exit 70·도구 취소 + exit 0)",
    arguments: [
      (
        [
          "Finding content...\n",
          "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 0.0% (73 kB of 3.76 GB) ",
          "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Done.        ",
          "\niOS 27.1 (24A94232) - 0E1F2A3B-4C5D-6E7F-8091-A2B3C4D5E6F7\n",
        ],
        Int32(0)
      ),
      (
        [
          "Finding content...\n",
          "Automatically resolved architecture variant for platform iOS as 'arm64'.\n",
          "iOS 27.1 (24A94425) - 1A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9\n",
        ],
        0
      ),
      (["\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 14.9% (558.6 MB of 3.76 GB)"], 70),
      (
        ["\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 1.0% (1 GB of 100 GB)", "\nDownload was cancelled.\n"],
        0
      ),
    ] as [([String], Int32)]
  )
  func outcomeMatchesChunkedFeed(chunks: [String], exitCode: Int32) {
    var parser = RuntimeInstallOutputParser()
    for chunk in chunks {
      _ = parser.feed(.stdout(Data(chunk.utf8)))
    }
    let chunked = parser.finish(exitCode: exitCode)

    let whole = RuntimeInstallOutputParser.outcome(
      stdout: Data(chunks.joined().utf8),
      stderr: Data(),
      exitCode: exitCode
    )

    #expect(whole == chunked)
  }

  @Test("outcome 은 stderr 에만 있는 줄도 본다")
  func outcomeReadsStderr() {
    let downloading = Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 3.0% (1 GB of 10 GB)\n".utf8)
    let cancelled = Data("Download was cancelled.\n".utf8)

    let installed = RuntimeInstallOutputParser.outcome(stdout: Data(), stderr: downloading, exitCode: 0)
    let failed = RuntimeInstallOutputParser.outcome(stdout: Data(), stderr: cancelled, exitCode: 0)

    #expect(installed == .success(.installed))
    #expect(failed == .failure(.failed))
  }
}
