import Foundation
import Testing
@testable import Core

struct AppBundleInfoTests {
  // MARK: - AppBundleID

  @Test(
    "번들 ID 는 ASCII 영숫자·점·하이픈·밑줄 1~255자를 받는다",
    arguments: ["com.example.app", "com.example.my-app", "com.example.my_app", "a", String(repeating: "a", count: 255)]
  )
  func acceptsBundleID(raw: String) {
    #expect(AppBundleID(raw)?.rawValue == raw)
  }

  @Test(
    "번들 ID 형식이 아니면 만들지 않는다",
    arguments: [
      "", "-x", "--stdout=/tmp/x", "a b", "a/b", "com.예시.app", String(repeating: "a", count: 256), "a\nb", "a\u{0}b",
      "a:b", "é",
    ]
  )
  func rejectsBundleID(raw: String) {
    #expect(AppBundleID(raw) == nil)
  }

  // MARK: - AppBundlePlatform

  @Test(
    "지원 플랫폼 이름을 대소문자를 구분해 바꾼다",
    arguments: [
      ("iPhoneSimulator", AppBundlePlatform.iOSSimulator),
      ("iPhoneOS", .iOS),
      ("MacOSX", .other),
      ("iphonesimulator", .other),
      ("", .other),
    ]
  )
  func mapsPlatform(raw: String, expected: AppBundlePlatform) {
    #expect(AppBundlePlatform(bundlePlatform: raw) == expected)
  }

  // MARK: - installProblem

  @Test("시뮬레이터용·arm64·최소 17.0 앱은 iOS 27.0·arm64 기기에 설치할 수 있다")
  func noProblem() {
    #expect(Self.info().installProblem(on: Self.iOS27, hostArchitecture: .arm64) == nil)
  }

  @Test(
    "지원 플랫폼에 시뮬레이터가 없으면 시뮬레이터용 빌드가 아니다",
    arguments: [Set<AppBundlePlatform>([.iOS]), [.iOS, .other], [], [.other]]
  )
  func notSimulatorBuild(platforms: Set<AppBundlePlatform>) {
    let info = Self.info(platforms: platforms)
    #expect(info.installProblem(on: Self.iOS27, hostArchitecture: .arm64) == .notSimulatorBuild)
  }

  @Test("지원 플랫폼 키가 없으면 플랫폼은 보지 않고, 시뮬레이터가 들어 있으면 다른 플랫폼이 함께 있어도 통과한다")
  func platformsAbsentOrMixed() {
    #expect(Self.info(platforms: nil).installProblem(on: Self.iOS27, hostArchitecture: .arm64) == nil)
    #expect(Self.info(platforms: [.iOS, .iOSSimulator]).installProblem(on: Self.iOS27, hostArchitecture: .arm64) == nil)
  }

  @Test("이 Mac 아키텍처가 실행 파일에 없으면 그 아키텍처가 없다고 알린다")
  func missingArchitecture() {
    #expect(
      Self.info(architectures: [.x86_64]).installProblem(on: Self.iOS27, hostArchitecture: .arm64)
        == .missingArchitecture(.arm64)
    )
    #expect(
      Self.info(architectures: [.arm64]).installProblem(on: Self.iOS27, hostArchitecture: .x86_64)
        == .missingArchitecture(.x86_64)
    )
    #expect(Self.info(architectures: [])
      .installProblem(on: Self.iOS27, hostArchitecture: .arm64) == .missingArchitecture(.arm64))
    #expect(Self.info(architectures: [.arm64, .x86_64])
      .installProblem(on: Self.iOS27, hostArchitecture: .x86_64) == nil)
  }

  @Test("기기 iOS 가 최소 버전보다 낮으면 필요한 버전을 알리고, 같거나 최소 버전이 없으면 통과한다")
  func minimumOSVersion() {
    let required = OSVersion(major: 27, minor: 1)
    #expect(
      Self.info(minimum: required)
        .installProblem(on: Self.iOS27, hostArchitecture: .arm64) == .requiresNewerOS(required)
    )
    #expect(Self.info(minimum: OSVersion(major: 27)).installProblem(on: Self.iOS27, hostArchitecture: .arm64) == nil)
    #expect(Self.info(minimum: nil).installProblem(on: Self.iOS27, hostArchitecture: .arm64) == nil)
  }

  @Test("문제가 여럿이면 플랫폼 → 아키텍처 → OS 버전 순서로 첫 문제 하나만 알린다")
  func problemOrder() {
    let all = Self.info(platforms: [.iOS], architectures: [.x86_64], minimum: OSVersion(major: 99))
    #expect(all.installProblem(on: Self.iOS27, hostArchitecture: .arm64) == .notSimulatorBuild)
    let archAndOS = Self.info(architectures: [.x86_64], minimum: OSVersion(major: 99))
    #expect(archAndOS.installProblem(on: Self.iOS27, hostArchitecture: .arm64) == .missingArchitecture(.arm64))
  }

  private static let iOS27 = DeviceRuntime(
    id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
    platform: .iOS,
    version: OSVersion(major: 27),
    name: "iOS 27.0",
    isAvailable: true,
    supportedDeviceTypeIDs: []
  )

  private static func info(
    platforms: Set<AppBundlePlatform>? = [.iOSSimulator],
    architectures: Set<CPUArchitecture> = [.arm64],
    minimum: OSVersion? = OSVersion(major: 17)
  ) -> AppBundleInfo {
    AppBundleInfo(
      bundleID: AppBundleID("com.example.app")!,
      displayName: "앱",
      version: "1.0",
      build: "1",
      platforms: platforms,
      architectures: architectures,
      minimumOSVersion: minimum,
      location: URL(filePath: "/tmp/App.app", directoryHint: .isDirectory)
    )
  }
}
