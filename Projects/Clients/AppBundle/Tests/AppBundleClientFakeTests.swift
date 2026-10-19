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
}
