import Testing
@testable import Core

struct RuntimeInstallProgressTests {
  @Test("preparing 상수는 phase 만 있고 퍼센트·바이트가 없다")
  func preparing() {
    let progress = RuntimeInstallProgress.preparing
    #expect(progress.phase == .preparing)
    #expect(progress.fractionCompleted == nil)
    #expect(progress.completedBytes == nil)
    #expect(progress.totalBytes == nil)
    #expect(progress == RuntimeInstallProgress(
      phase: .preparing,
      fractionCompleted: nil,
      completedBytes: nil,
      totalBytes: nil
    ))
  }
}
