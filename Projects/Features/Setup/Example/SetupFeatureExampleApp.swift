import Core
import DevEnvironmentTesting
import SetupFeature
import SwiftUI

/// App 없이 Setup 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 Xcode 대신 Testing 모듈의 `DevEnvironmentClientFake`(라이선스 미동의 상태, 확인·열기마다 1초 지연)를 주입한다.
/// 명령을 실행하지 않으므로 Xcode·App Store 는 열리지 않는다. "기기 목록 열기"를 누르면 App 의 기기 목록 자리를
/// 대신하는 화면을 보이고, 그 화면의 버튼으로 Setup 을 다시 연다 (App 의 툴바 "개발 환경" 흐름).
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
    let fake = DevEnvironmentClientFake(status: .licenseNotAccepted(.sample))
    fake.setDelay(.seconds(1))
    return SetupModel(devEnvironment: fake)
  }
}

/// Fake 를 만들어 설정한 뒤 화면을 만든다.
@MainActor
private func previewSetup(
  _ status: DevEnvironmentStatus,
  configure: (DevEnvironmentClientFake) -> Void = { _ in }
) -> SetupView {
  let fake = DevEnvironmentClientFake(status: status)
  configure(fake)
  return SetupView(model: SetupModel(devEnvironment: fake))
}

#Preview("확인 중") {
  previewSetup(.ready(.sample)) { $0.suspendChecks() }
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

#Preview("확인 실패") {
  previewSetup(.ready(.sample)) { $0.setCheckError(.checkFailed) }
}

#Preview("열기 실패 (App Store 열기)") {
  previewSetup(.xcodeNotInstalled) { $0.setOpenAppStoreError(.openFailed) }
}

#Preview("열기 실패 (Xcode 열기)") {
  previewSetup(.licenseNotAccepted(.sample)) { $0.setOpenXcodeError(.openFailed) }
}

#Preview("다시 확인 중 (다시 확인, 1초)") {
  previewSetup(.xcodeNotInstalled) { $0.setDelay(.seconds(1)) }
}
