import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import SetupFeature
import SimulatorTesting
import SwiftUI

/// App 없이 Setup 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 Xcode·시뮬레이터 대신 Testing 모듈의 `DevEnvironmentClientFake`(Xcode 준비됨, 확인·진행 알림마다 1초 지연)와
/// `SimulatorClientFake`(런타임 이미지 없음 → 기본 iOS 설치 안 됨)를 주입한다. 명령을 실행하지 않으므로 Xcode·App Store 는
/// 열리지 않고 아무것도 내려받지 않는다. "iOS 시뮬레이터 설치"를 누르면 준비 → 내려받기 → 설치 진행을 1초 간격으로 보이고,
/// 끝나면 iOS 27.1 이 설치된 목록으로 바꿔 다시 확인한다. 무진행 안내 시계는 60초 대신 5초다.
/// 첫 판정이 준비됨이라 곧바로 App 의 기기 목록 자리를 대신하는 화면이 보이고, 그 화면의 버튼으로 Setup 을 다시 연다
/// (Launcher 의 툴바 "개발 환경"·빈 화면 "iOS 설치"·"다른 iOS 버전 설치"·실패 화면 "개발 환경 열기"가 모두 이 흐름).
@main
struct SetupFeatureExampleApp: App {
  @State private var model = Self.makeModel()

  var body: some Scene {
    WindowGroup {
      if self.model.isFinished {
        VStack(spacing: 12) {
          Text(verbatim: "기기 목록 화면 자리")
          Button {
            self.model.reopened()
          } label: {
            Text(verbatim: "개발 환경 다시 열기")
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        SetupView(model: self.model)
      }
    }
  }

  private static func makeModel() -> SetupModel {
    let fake = DevEnvironmentClientFake(status: .ready(.sample))
    fake.setDelay(.seconds(1))
    fake.setInstallScript(progress: demoProgress, result: .success(.installed))
    let simulator = SimulatorClientFake()
    simulator.setRuntimeImages([])
    return SetupModel(
      devEnvironment: InstallingDemoClient(fake: fake, simulator: simulator),
      simulator: simulator,
      sleep: demoStallSleep
    )
  }
}

/// 준비 → 내려받기(바이트 포함) → 설치 진행.
private let demoProgress: [RuntimeInstallProgress] = [
  .preparing,
  .downloading(fraction: 0.149, completed: 558_600_000, total: 3_760_000_000),
  .downloading(fraction: 0.5, completed: 1_880_000_000, total: 3_760_000_000),
  .downloading(fraction: 0.991, completed: 3_726_160_000, total: 3_760_000_000),
  .installing,
]

/// 무진행 안내를 빨리 보려고 60초 대신 5초 기다린다.
private let demoStallSleep: @Sendable (Duration) async throws -> Void = { _ in
  try await Task.sleep(for: .seconds(5))
}

/// 설치가 성공하면 Simulator Fake 의 런타임 이미지를 기본 iOS(27.1)가 Ready 인 목록으로 바꾸는 데모용 Client.
/// 나머지는 `DevEnvironmentClientFake` 에 그대로 넘긴다.
private struct InstallingDemoClient: DevEnvironmentClient {
  let fake: DevEnvironmentClientFake
  let simulator: SimulatorClientFake

  func selectedXcode() async -> XcodeInstallation? {
    await self.fake.selectedXcode()
  }

  func checkEnvironment() async throws(DevEnvironmentError) -> DevEnvironmentStatus {
    try await self.fake.checkEnvironment()
  }

  func openXcode() async throws(DevEnvironmentError) {
    try await self.fake.openXcode()
  }

  func openXcodeInAppStore() async throws(DevEnvironmentError) {
    try await self.fake.openXcodeInAppStore()
  }

  func defaultIOSRuntime() async -> DefaultIOSRuntime? {
    await self.fake.defaultIOSRuntime()
  }

  func installDefaultIOSRuntime(
    progress: @escaping @Sendable (RuntimeInstallProgress) async -> Void
  ) async throws(RuntimeInstallError) -> RuntimeInstallOutcome {
    let outcome = try await self.fake.installDefaultIOSRuntime(progress: progress)
    self.simulator.setRuntimeImages(RuntimeImage.samples)
    return outcome
  }
}

/// Fake 를 만들어 설정한 뒤 화면을 만든다. 런타임 이미지 기본값은 기본 iOS(27.1)가 Ready 인 목록이다.
@MainActor
private func previewSetup(
  _ status: DevEnvironmentStatus,
  images: [RuntimeImage] = RuntimeImage.samples,
  configure: (DevEnvironmentClientFake, SimulatorClientFake) -> Void = { _, _ in }
) -> SetupView {
  let fake = DevEnvironmentClientFake(status: status)
  let simulator = SimulatorClientFake()
  simulator.setRuntimeImages(images)
  configure(fake, simulator)
  return SetupView(model: SetupModel(devEnvironment: fake, simulator: simulator, sleep: demoStallSleep))
}

/// 기본 iOS 27.1 이미지를 상태만 바꿔 만든다.
private func defaultImage(_ state: RuntimeImage.State) -> RuntimeImage {
  let image = SampleRuntimeImage.iOS27Point1
  return RuntimeImage(
    id: image.id,
    runtimeID: image.runtimeID,
    platform: image.platform,
    version: image.version,
    build: image.build,
    state: state,
    sizeBytes: image.sizeBytes
  )
}

#Preview("확인 중") {
  previewSetup(.ready(.sample)) { fake, _ in fake.suspendChecks() }
}

#Preview("Xcode 없음") {
  previewSetup(.xcodeNotInstalled)
}

#Preview("Command Line Tools 만") {
  previewSetup(.commandLineToolsOnly)
}

#Preview("라이선스 미동의") {
  previewSetup(.licenseNotAccepted(.sample))
}

#Preview("첫 실행 준비 필요") {
  previewSetup(.firstLaunchRequired(.sample))
}

/// App 에서는 첫 판정이 준비됨이면 곧바로 기기 목록으로 넘어가지만, Preview 는 화면을 바꾸지 않아 완료 화면이 보인다
/// (Setup 안에서 준비가 끝났거나 툴바로 다시 연 경우의 화면).
#Preview("준비됨") {
  previewSetup(.ready(.sample))
}

/// 설치 버튼·기기 목록 열기·다른 iOS 버전 안내. 설치를 누르면 Fake 의 기본 진행(.preparing) 뒤 끝나고,
/// 목록은 그대로라 "설치가 끝났지만 … 보이지 않습니다" 결과 줄이 보인다.
#Preview("iOS 없음") {
  previewSetup(.ready(.sample), images: [])
}

/// 설치를 누르면 준비 → 내려받기 → 설치를 1초 간격으로 보인다 (취소는 설치 단계 전까지).
#Preview("설치 데모 (1초 간격)") {
  previewSetup(.ready(.sample), images: []) { fake, _ in
    fake.setDelay(.seconds(1))
    fake.setInstallScript(progress: demoProgress, result: .success(.installed))
  }
}

/// 설치를 누르면 내려받기 14.9% 에서 멈추고, 5초 뒤 연결 확인 안내가 보인다. 취소할 수 있다.
#Preview("설치 중 무진행 (5초)") {
  previewSetup(.ready(.sample), images: []) { fake, _ in
    fake.setInstallScript(progress: Array(demoProgress.prefix(2)), result: .success(.installed))
    fake.suspendInstalls()
  }
}

/// 설치를 누르면 설치 단계(취소 불가)에서 멈춘다.
#Preview("설치 단계 (취소 불가)") {
  previewSetup(.ready(.sample), images: []) { fake, _ in
    fake.setInstallScript(progress: [.preparing, .installing], result: .success(.installed))
    fake.suspendInstalls()
  }
}

#Preview("설치 실패") {
  previewSetup(.ready(.sample), images: []) { fake, _ in
    fake.setInstallScript(progress: [.preparing], result: .failure(.failed))
  }
}

#Preview("설치 도구 시작 실패") {
  previewSetup(.ready(.sample), images: []) { fake, _ in
    fake.setInstallScript(progress: [.preparing], result: .failure(.launchFailed))
  }
}

/// 설치를 누른 뒤 취소를 누르면 "설치를 취소했습니다." 결과 줄이 보인다.
#Preview("취소함") {
  previewSetup(.ready(.sample), images: []) { fake, _ in
    fake.setInstallScript(progress: Array(demoProgress.prefix(2)), result: .success(.installed))
    fake.suspendInstalls()
  }
}

#Preview("iOS 준비 중") {
  previewSetup(.ready(.sample), images: [defaultImage(.preparing)])
}

#Preview("iOS 쓸 수 없음") {
  previewSetup(.ready(.sample), images: [defaultImage(.unusable)])
}

#Preview("iOS 버전 읽기 실패") {
  previewSetup(.ready(.sample)) { fake, _ in fake.setDefaultIOSRuntime(nil) }
}

#Preview("런타임 목록 실패") {
  previewSetup(.ready(.sample)) { _, simulator in simulator.setRuntimeImagesError(.commandFailed) }
}

#Preview("확인 실패") {
  previewSetup(.ready(.sample)) { fake, _ in fake.setCheckError(.checkFailed) }
}

#Preview("열기 실패 (App Store 열기)") {
  previewSetup(.xcodeNotInstalled) { fake, _ in fake.setOpenAppStoreError(.openFailed) }
}

#Preview("열기 실패 (Xcode 열기)") {
  previewSetup(.licenseNotAccepted(.sample)) { fake, _ in fake.setOpenXcodeError(.openFailed) }
}

#Preview("다시 확인 중 (다시 확인, 1초)") {
  previewSetup(.xcodeNotInstalled) { fake, _ in fake.setDelay(.seconds(1)) }
}
