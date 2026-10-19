import AppBundleInterface
import AppBundleTesting
import Core
import Foundation
import Testing

struct AppBundleClientFakeTests {
  private static let url = URL(filePath: "/tmp/Picked.app", directoryHint: .isDirectory)

  @Test("기본은 .sample 을 돌려주고 호출을 기록한다")
  func defaultSample() async throws {
    let fake = AppBundleClientFake()

    let info = try await fake.inspect(Self.url)

    #expect(info == .sample)
    #expect(info.bundleID.rawValue == "com.example.sample")
    #expect(fake.calls == [.inspect(Self.url)])
    #expect(fake.hostArchitecture == .arm64)
  }

  @Test("setInfo·setHostArchitecture 뒤에는 바꾼 값을 쓴다")
  func setters() async throws {
    let fake = AppBundleClientFake()
    fake.setInfo(.x86Only)
    fake.setHostArchitecture(.x86_64)

    #expect(try await fake.inspect(Self.url) == .x86Only)
    #expect(fake.hostArchitecture == .x86_64)
  }

  @Test("setInspectError 가 있으면 정보 대신 던지고, nil 로 되돌리면 정보를 돌려준다")
  func inspectError() async throws {
    let fake = AppBundleClientFake()
    fake.setInspectError(.ipaFile)

    await #expect(throws: AppBundleError.ipaFile) { try await fake.inspect(Self.url) }

    fake.setInspectError(nil)
    #expect(try await fake.inspect(Self.url) == .sample)
  }

  @Test("멈춘 검사는 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspendInspections() async throws {
    let fake = AppBundleClientFake()
    fake.suspendInspections()
    let task = Task { try await fake.inspect(Self.url) }
    while fake.calls.isEmpty {
      await Task.yield()
    }

    fake.setInfo(.deviceBuild)
    fake.resumeInspections()

    #expect(try await task.value == .deviceBuild)
    #expect(try await fake.inspect(Self.url) == .deviceBuild)
  }

  @Test("샘플 정보: 기기용 빌드·x86 전용·높은 최소 버전")
  func samples() {
    #expect(AppBundleInfo.deviceBuild.platforms == [.iOS])
    #expect(AppBundleInfo.x86Only.architectures == [.x86_64])
    #expect(AppBundleInfo.requiring(OSVersion(major: 99)).minimumOSVersion == OSVersion(major: 99))
    #expect(AppBundleInfo.requiring(OSVersion(major: 99)).bundleID == AppBundleInfo.sample.bundleID)
  }

  private static let zip = URL(filePath: "/tmp/Build.zip")

  @Test("extract 는 호출을 기록하고 k 번째 호출에 fake(index: k) 를 돌려준다")
  func extractSequence() async throws {
    let fake = AppBundleClientFake()

    let first = try await fake.extractApp(fromZip: Self.zip)
    let second = try await fake.extractApp(fromZip: Self.zip)

    #expect(first == .fake(index: 1))
    #expect(second == .fake(index: 2))
    #expect(fake.calls == [.extractApp(Self.zip), .extractApp(Self.zip)])
  }

  @Test("fake(index:) 는 SimLauncher-Unzip-Fake-<k> 폴더 안 contents/Sample.app")
  func fakeExtractedApp() {
    let extracted = ExtractedApp.fake(index: 3)

    #expect(extracted.folder.path(percentEncoded: false) == "/tmp/SimLauncher-Unzip-Fake-3/")
    #expect(extracted.app.path(percentEncoded: false) == "/tmp/SimLauncher-Unzip-Fake-3/contents/Sample.app/")
  }

  @Test("멈춘 두 extract 를 뒤 호출부터 깨워도 먼저 들어온 호출이 fake(1) 이다")
  func suspendedExtractOrder() async throws {
    let fake = AppBundleClientFake()
    fake.suspendExtractions()
    let firstURL = URL(filePath: "/tmp/First.zip")
    let secondURL = URL(filePath: "/tmp/Second.zip")
    let first = Task { try await fake.extractApp(fromZip: firstURL) }
    while fake.calls.count < 1 {
      await Task.yield()
    }
    let second = Task { try await fake.extractApp(fromZip: secondURL) }
    while fake.calls.count < 2 {
      await Task.yield()
    }

    // 멈춤 중에는 검사가 멈추지 않는다 (멈춤이 따로다).
    #expect(try await fake.inspect(Self.url) == .sample)
    fake.resumeExtractions()

    #expect(try await second.value == .fake(index: 2))
    #expect(try await first.value == .fake(index: 1))
  }

  @Test("멈춘 extract 는 resume 까지 기다리고, 깨어난 뒤의 에러를 던진다. nil 로 되돌리면 성공한다")
  func extractError() async throws {
    let fake = AppBundleClientFake()
    fake.suspendExtractions()
    let task = Task { try await fake.extractApp(fromZip: Self.zip) }
    while fake.calls.isEmpty {
      await Task.yield()
    }

    fake.setExtractError(.zipWithoutApp)
    fake.resumeExtractions()

    await #expect(throws: AppBundleError.zipWithoutApp) { try await task.value }
    fake.setExtractError(nil)
    #expect(try await fake.extractApp(fromZip: Self.zip) == .fake(index: 2))
  }

  @Test("removeExtracted 는 기록하고, removeLeftoverExtractions 는 calls 대신 leftoverCleanupCount 를 센다")
  func cleanupCalls() async {
    let fake = AppBundleClientFake()

    await fake.removeExtracted(.fake(index: 1))
    await fake.removeLeftoverExtractions()
    await fake.removeLeftoverExtractions()

    #expect(fake.calls == [.removeExtracted(.fake(index: 1))])
    #expect(fake.leftoverCleanupCount == 2)
  }

  @Test("setDelay 는 extract 에도 적용된다")
  func extractDelay() async throws {
    let fake = AppBundleClientFake()
    fake.setDelay(.milliseconds(50))
    let clock = ContinuousClock()

    let elapsed = try await clock.measure { _ = try await fake.extractApp(fromZip: Self.zip) }

    #expect(elapsed >= .milliseconds(50))
  }
}
