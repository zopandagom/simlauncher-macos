import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Testing

/// Fake 의 설치된 앱 관리: 호출 기록·설정한 에러·멈춤. 목록은 바꾸지 않는다.
struct AndroidEmulatorClientFakeAppsTests {
  private static let pixel = AndroidVirtualDevice.ID("Pixel")
  private static let package = AndroidPackageName("com.example.app")!

  @Test("uninstall: 기본 성공, 호출을 기록하고 installedPackages 결과를 바꾸지 않는다")
  func uninstall() async throws {
    let fake = AndroidEmulatorClientFake()
    fake.setInstalledPackages(.success([Self.package]))

    try await fake.uninstall(Self.package, on: Self.pixel)

    #expect(fake.calls == [.appManagement(.uninstall(Self.package, Self.pixel))])
    #expect(try await fake.installedPackages(on: Self.pixel) == [Self.package])
  }

  @Test("uninstall: 설정한 에러를 던지고, nil 로 되돌리면 다시 성공")
  func uninstallError() async throws {
    let fake = AndroidEmulatorClientFake()

    fake.setUninstallError(.appCommandFailed)
    await #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try await fake.uninstall(Self.package, on: Self.pixel)
    }
    fake.setUninstallError(nil)
    try await fake.uninstall(Self.package, on: Self.pixel)
  }

  @Test("멈춘 uninstall 은 기록만 하고 resumeUninstalls 까지 기다린다 (다른 앱 작업은 기다리지 않는다)")
  func suspend() async throws {
    let fake = AndroidEmulatorClientFake()
    fake.suspendUninstalls()

    let task = Task { try await fake.uninstall(Self.package, on: Self.pixel) }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(try await fake.installedPackages(on: Self.pixel) == [])
    #expect(fake.calls == [.appManagement(.uninstall(Self.package, Self.pixel)), .installedPackages(Self.pixel)])
    fake.resumeUninstalls()
    try await task.value
  }
}
