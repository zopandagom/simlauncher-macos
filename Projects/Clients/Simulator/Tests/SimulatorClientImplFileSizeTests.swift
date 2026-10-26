import Foundation
import Testing
@testable import SimulatorImpl

/// 녹화 결과 파일 크기를 읽는 기본 구현.
struct SimulatorClientImplFileSizeTests {
  @Test("기본 파일 크기: 있는 파일은 바이트 수, 없는 파일은 nil")
  func regularFileSize() throws {
    let folder = URL.temporaryDirectory.appending(path: "SimulatorRecordingTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "a.mov")
    try Data([1, 2, 3]).write(to: file)

    #expect(SimulatorClientImpl.regularFileSize(file) == 3)
    #expect(SimulatorClientImpl.regularFileSize(folder.appending(path: "none.mov")) == nil)
  }
}
