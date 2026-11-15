import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Testing

/// Fake 의 런타임 권한: 설정한 목록·값 바꾸기·적용 안 됨·앱 없음·에러·호출 기록·멈춤.
struct AndroidEmulatorClientFakePermissionTests {
  private static let pixel = AndroidVirtualDevice.ID("Pixel")
  private static let package = AndroidPackageName("com.example.app")!
  private static let camera = AndroidRuntimePermission("android.permission.CAMERA")!
  private static let audio = AndroidRuntimePermission("android.permission.RECORD_AUDIO")!
  private static let grants = [
    AndroidPermissionGrant(permission: camera, isGranted: false),
    AndroidPermissionGrant(permission: audio, isGranted: true),
  ]

  @Test("설정하지 않은 앱은 appNotInstalled, 설정한 목록을 돌려주고 성공한 쓰기가 그 권한 값만 바꾼다")
  func readWrite() async throws {
    let fake = AndroidEmulatorClientFake()
    #expect(try await fake.runtimePermissions(of: Self.package, on: Self.pixel) == .appNotInstalled)
    #expect(
      try await fake.setRuntimePermission(Self.camera, granted: true, of: Self.package, on: Self.pixel)
        == .appNotInstalled
    )

    fake.setRuntimePermissions(Self.grants, of: Self.package, on: Self.pixel)
    #expect(try await fake.runtimePermissions(of: Self.package, on: Self.pixel) == .runtime(Self.grants))

    let granted = [
      AndroidPermissionGrant(permission: Self.camera, isGranted: true),
      AndroidPermissionGrant(permission: Self.audio, isGranted: true),
    ]
    #expect(
      try await fake.setRuntimePermission(Self.camera, granted: true, of: Self.package, on: Self.pixel)
        == .applied(granted)
    )
    #expect(fake.storedRuntimePermissions(of: Self.package, on: Self.pixel) == granted)
    #expect(fake.storedRuntimePermissions(of: Self.package, on: AndroidVirtualDevice.ID("Other")) == nil)
    #expect(fake.calls == [
      .testCondition(.runtimePermissions(Self.package, Self.pixel)),
      .testCondition(.setRuntimePermission(Self.camera, true, Self.package, Self.pixel)),
      .testCondition(.runtimePermissions(Self.package, Self.pixel)),
      .testCondition(.setRuntimePermission(Self.camera, true, Self.package, Self.pixel)),
    ])
  }

  @Test("빈 목록은 권한을 요청하지 않는 앱이고, 목록에 없는 권한·적용 안 됨 설정은 값을 바꾸지 않고 notApplied(지금 목록)")
  func notApplied() async throws {
    let fake = AndroidEmulatorClientFake()
    fake.setRuntimePermissions([], of: Self.package, on: Self.pixel)
    #expect(try await fake.runtimePermissions(of: Self.package, on: Self.pixel) == .runtime([]))
    #expect(
      try await fake.setRuntimePermission(Self.camera, granted: true, of: Self.package, on: Self.pixel)
        == .notApplied([])
    )

    fake.setRuntimePermissions(Self.grants, of: Self.package, on: Self.pixel)
    fake.setRuntimePermissionNotApplied(true)
    #expect(
      try await fake.setRuntimePermission(Self.audio, granted: false, of: Self.package, on: Self.pixel)
        == .notApplied(Self.grants)
    )
    #expect(fake.storedRuntimePermissions(of: Self.package, on: Self.pixel) == Self.grants)

    fake.setRuntimePermissionNotApplied(false)
    fake.removeRuntimePermissions(of: Self.package, on: Self.pixel)
    #expect(try await fake.runtimePermissions(of: Self.package, on: Self.pixel) == .appNotInstalled)
    #expect(
      try await fake.setRuntimePermission(Self.audio, granted: false, of: Self.package, on: Self.pixel)
        == .appNotInstalled
    )
  }

  @Test("설정한 에러: 읽기 에러는 읽기만, 쓰기 에러는 쓰기만 던지고 값은 바꾸지 않는다")
  func errors() async throws {
    let fake = AndroidEmulatorClientFake()
    fake.setRuntimePermissions(Self.grants, of: Self.package, on: Self.pixel)

    fake.setRuntimePermissionsError(.deviceNotBooted)
    await #expect(throws: AndroidEmulatorError.deviceNotBooted) {
      try await fake.runtimePermissions(of: Self.package, on: Self.pixel)
    }
    #expect(
      try await fake.setRuntimePermission(Self.camera, granted: true, of: Self.package, on: Self.pixel)
        == .applied([
          AndroidPermissionGrant(permission: Self.camera, isGranted: true),
          AndroidPermissionGrant(permission: Self.audio, isGranted: true),
        ])
    )

    fake.setRuntimePermissionsError(nil)
    fake.setRuntimePermissionError(.appCommandFailed)
    await #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try await fake.setRuntimePermission(Self.audio, granted: false, of: Self.package, on: Self.pixel)
    }
    #expect(fake.storedRuntimePermissions(of: Self.package, on: Self.pixel)?.last?.isGranted == true)
  }

  @Test("suspendConditions 는 읽기·쓰기 둘 다, suspendConditionReads 는 읽기만 멈춘다")
  func suspend() async throws {
    let fake = AndroidEmulatorClientFake()
    fake.setRuntimePermissions(Self.grants, of: Self.package, on: Self.pixel)
    fake.suspendConditions()
    let write = Task {
      try await fake.setRuntimePermission(Self.camera, granted: true, of: Self.package, on: Self.pixel)
    }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(fake.storedRuntimePermissions(of: Self.package, on: Self.pixel) == Self.grants)
    fake.resumeConditions()
    _ = try await write.value

    fake.suspendConditionReads()
    let read = Task { try await fake.runtimePermissions(of: Self.package, on: Self.pixel) }
    while fake.calls.count < 2 {
      await Task.yield()
    }
    // 읽기가 멈춘 동안 쓰기는 돌아온다.
    #expect(
      try await fake.setRuntimePermission(Self.camera, granted: false, of: Self.package, on: Self.pixel)
        == .applied(Self.grants)
    )
    fake.resumeConditionReads()
    #expect(try await read.value == .runtime(Self.grants))
  }
}
