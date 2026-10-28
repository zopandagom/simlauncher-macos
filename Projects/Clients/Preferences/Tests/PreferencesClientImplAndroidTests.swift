import Core
import PreferencesInterface
import Testing
@testable import PreferencesImpl

/// `AndroidSDKPath`·`AcceptedAndroidLicenses` 읽기·쓰기 (InMemory 저장소).
struct PreferencesClientImplAndroidTests {
  // MARK: - SDK 위치

  @Test("SDK 위치: 키 없음 → absent, 문자열 → path, 문자열 아님 → malformed, 강제 여부를 함께 읽는다")
  func readsSDKPath() {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    #expect(client.androidSDKPath() == .absent)

    store.replaceAndroidSDKPath(.path(" /Volumes/Tools/SDK "), isForced: false)
    #expect(client.androidSDKPath() == AndroidSDKPathSetting(value: .path(" /Volumes/Tools/SDK "), isLocked: false))

    store.replaceAndroidSDKPath(.malformed, isForced: true)
    #expect(client.androidSDKPath() == AndroidSDKPathSetting(value: .malformed, isLocked: true))
  }

  @Test("SDK 위치 쓰기: 문자열은 그대로 저장, nil 은 키를 지운다")
  func writesSDKPath() throws {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)

    try client.setAndroidSDKPath("~/SDK")
    #expect(store.androidSDKPath() == .path("~/SDK"))

    try client.setAndroidSDKPath(nil)
    #expect(store.androidSDKPath() == .absent)
    #expect(store.androidSDKPathSetCount == 2)
  }

  @Test("SDK 위치가 잠겼으면 locked, 쓰지 않는다 (nil 도)")
  func lockedSDKPath() {
    let store = InMemoryPreferenceStore()
    store.replaceAndroidSDKPath(.path("/Volumes/Tools/SDK"), isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(throws: PreferencesError.locked) { try client.setAndroidSDKPath("/other") }
    #expect(throws: PreferencesError.locked) { try client.setAndroidSDKPath(nil) }
    #expect(store.androidSDKPathSetCount == 0)
    #expect(store.androidSDKPath() == .path("/Volumes/Tools/SDK"))
  }

  // MARK: - 라이선스 지문

  @Test("지문: 키 없음 → 빈 집합, 저장된 문자열 항목을 집합으로")
  func readsLicenses() {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    #expect(client.acceptedAndroidLicenses().isEmpty)

    store.replaceLicenses(["a", "b", "a"], isForced: false)
    #expect(client.acceptedAndroidLicenses() == ["a", "b"])
  }

  @Test("지문 더하기: 없는 지문만 정렬해 끝에 붙이고, 더할 것이 없으면 쓰지 않는다")
  func addsLicenses() throws {
    let store = InMemoryPreferenceStore()
    store.replaceLicenses(["m"], isForced: false)
    let client = PreferencesClientImpl(store: store)

    try client.addAcceptedAndroidLicenses(["z", "m", "a"])
    #expect(store.licenses == ["m", "a", "z"])
    #expect(store.licensesSetCount == 1)

    try client.addAcceptedAndroidLicenses(["a", "z"])
    #expect(store.licensesSetCount == 1)
  }

  @Test("지문 더하기는 저장소를 다시 읽어 바깥에서 바뀐 값 위에 더한다")
  func addsOnLatest() throws {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    _ = client.acceptedAndroidLicenses()
    store.replaceLicenses(["outside"], isForced: false)

    try client.addAcceptedAndroidLicenses(["mine"])

    #expect(store.licenses == ["outside", "mine"])
  }

  @Test("지문이 잠겼으면 locked, 쓰지 않고 강제 값은 그대로 읽힌다")
  func lockedLicenses() {
    let store = InMemoryPreferenceStore()
    store.replaceLicenses(["admin"], isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(throws: PreferencesError.locked) { try client.addAcceptedAndroidLicenses(["mine"]) }
    #expect(store.licensesSetCount == 0)
    #expect(client.acceptedAndroidLicenses() == ["admin"])
  }

  @Test("여러 Task 가 동시에 지문을 더해도 쓰기를 잃지 않는다 (8개 × 20번)")
  func concurrentLicenseAdds() async {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)

    await withTaskGroup(of: Void.self) { group in
      for task in 0 ..< 8 {
        group.addTask {
          for index in 0 ..< 20 {
            try? client.addAcceptedAndroidLicenses(["\(task)-\(index)"])
          }
        }
      }
    }

    #expect(Set(store.licenses).count == 160)
    #expect(store.licenses.count == 160)
  }
}
