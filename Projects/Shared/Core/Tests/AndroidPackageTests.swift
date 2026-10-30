import Foundation
import Testing
@testable import Core

struct AndroidPackageNameTests {
  @Test("구성 요소 2개 이상, 영문자로 시작하고 영숫자·_ 만이면 만든다", arguments: ["com.a", "a.b_c.D1", "A.B", "x1.y_"])
  func valid(raw: String) {
    #expect(AndroidPackageName(raw)?.rawValue == raw)
  }

  @Test(
    "빈 값·구성 요소 하나·숫자나 _ 로 시작·빈 구성 요소·허용하지 않는 문자는 거절한다",
    arguments: [
      "",
      "com",
      "1com.a",
      "com.1a",
      "_a.b",
      "com._a",
      "com..a",
      "com.a.",
      ".com.a",
      "com.a b",
      "com.a-b",
      "com.a$b",
      "com.한글"
    ]
  )
  func invalid(raw: String) {
    #expect(AndroidPackageName(raw) == nil)
  }

  @Test("255자까지 받고 256자는 거절한다")
  func length() {
    let maxLength = "a." + String(repeating: "b", count: 253)
    #expect(maxLength.count == 255)
    #expect(AndroidPackageName(maxLength) != nil)
    #expect(AndroidPackageName(maxLength + "c") == nil)
  }

  @Test("이름순으로 정렬한다")
  func comparable() throws {
    let names = try ["org.b", "com.z", "com.a"].map { try #require(AndroidPackageName($0)) }
    #expect(names.sorted().map(\.rawValue) == ["com.a", "com.z", "org.b"])
  }
}

struct AndroidInstallProblemTests {
  private static let arm64 = AndroidDeviceTraits(apiLevel: 37, abis: ["arm64-v8a"])

  @Test("네이티브 코드가 없으면 ABI 는 보지 않고 API 만 본다")
  func noNativeCode() {
    #expect(Self.info(abis: [], minSDK: .level(24)).installProblem(on: Self.arm64) == nil)
    #expect(
      Self.info(abis: [], minSDK: .level(99)).installProblem(on: Self.arm64) == .requiresNewerAPI(
        required: 99,
        device: 37
      )
    )
  }

  @Test("기기 ABI 와 하나라도 겹치면 통과한다")
  func overlap() {
    let traits = AndroidDeviceTraits(apiLevel: 37, abis: ["x86_64", "arm64-v8a"])
    #expect(Self.info(abis: ["arm64-v8a", "armeabi-v7a"]).installProblem(on: traits) == nil)
  }

  @Test("겹치지 않으면 apk abi 는 정렬, 기기 abi 는 abilist 순서 그대로 담는다")
  func noOverlap() {
    let traits = AndroidDeviceTraits(apiLevel: 37, abis: ["x86_64", "x86"])
    #expect(
      Self.info(abis: ["mips", "armeabi-v7a", "arm64-v8a"]).installProblem(on: traits)
        == .noMatchingABI(app: ["arm64-v8a", "armeabi-v7a", "mips"], device: ["x86_64", "x86"])
    )
  }

  @Test("ABI 와 API 가 둘 다 문제면 ABI 를 먼저 돌려준다")
  func abiFirst() {
    #expect(
      Self.info(abis: ["x86"], minSDK: .level(99)).installProblem(on: Self.arm64)
        == .noMatchingABI(app: ["x86"], device: ["arm64-v8a"])
    )
  }

  @Test("minSdk 가 기기 API 와 같으면 통과하고, 크면 필요한 값과 기기 값을 담는다")
  func apiLevel() {
    #expect(Self.info(minSDK: .level(37)).installProblem(on: Self.arm64) == nil)
    #expect(Self.info(minSDK: .level(38)).installProblem(on: Self.arm64) == .requiresNewerAPI(required: 38, device: 37))
    #expect(Self.info(minSDK: .level(1)).installProblem(on: Self.arm64) == nil)
  }

  @Test("minSdk 를 모르면(.unresolved) API 는 건너뛴다")
  func unresolved() {
    let old = AndroidDeviceTraits(apiLevel: 21, abis: ["arm64-v8a"])
    #expect(Self.info(minSDK: .unresolved).installProblem(on: old) == nil)
  }

  private static func info(abis: Set<String> = [], minSDK: AndroidMinSDK = .level(24)) -> AndroidPackageInfo {
    AndroidPackageInfo(
      location: URL(filePath: "/tmp/a.apk"),
      packageName: AndroidPackageName("com.example.a")!,
      minSDK: minSDK,
      nativeABIs: abis
    )
  }
}

struct AndroidAppActionAvailabilityTests {
  @Test("켜진 기기만 앱 작업을 할 수 있다")
  func booted() {
    #expect(AndroidDeviceListTests.device(state: .booted).appActionAvailability == .allowed)
  }

  @Test("꺼짐·켜는 중은 notBooted 로 막힌다", arguments: [AndroidVirtualDevice.State.shutdown, .booting])
  func notBooted(state: AndroidVirtualDevice.State) {
    #expect(AndroidDeviceListTests.device(state: state).appActionAvailability == .blocked(.notBooted))
  }

  @Test(
    "쓸 수 없는 기기는 켜져 있어도 상태보다 먼저 unavailable 로 막힌다",
    arguments: [AndroidVirtualDevice.State.booted, .booting, .shutdown]
  )
  func unavailable(state: AndroidVirtualDevice.State) {
    let device = AndroidDeviceListTests.device(state: state, availability: .unavailable(.configUnreadable))
    #expect(device.appActionAvailability == .blocked(.unavailable))
  }
}
