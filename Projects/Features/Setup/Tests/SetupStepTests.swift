import Core
import DevEnvironmentTesting
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import SetupFeature

struct SetupStepTests {
  struct Expected: Sendable, CustomTestStringConvertible {
    let status: DevEnvironmentStatus
    let runtime: SetupRuntimeState
    let progress: [SetupStep.Progress]

    init(_ status: DevEnvironmentStatus, _ runtime: SetupRuntimeState, _ progress: [SetupStep.Progress]) {
      self.status = status
      self.runtime = runtime
      self.progress = progress
    }

    var testDescription: String {
      "\(self.status) / \(self.runtime)"
    }
  }

  static let installed = SetupRuntimeState.checked(.sample, .installed(SampleRuntimeImage.iOS27Point1))
  static let notInstalled = SetupRuntimeState.checked(.sample, .notInstalled)
  static let preparing = SetupRuntimeState.checked(.sample, .preparing(SampleRuntimeImage.iOS27Point1))
  static let unusable = SetupRuntimeState.checked(.sample, .unusable(SampleRuntimeImage.iOS27Point1))

  /// 설계 §3.6 표의 progress 열. 설치 중·설치 결과 확인 중은 런타임이 설치 안 됨인 상태라 그 행과 같다.
  static let cases: [Expected] = [
    Expected(.xcodeNotInstalled, .notChecked, [.current, .pending, .pending, .pending]),
    Expected(.commandLineToolsOnly, .notChecked, [.current, .pending, .pending, .pending]),
    Expected(.licenseNotAccepted(.sample), .notChecked, [.done, .current, .pending, .pending]),
    Expected(.firstLaunchRequired(.sample), .notChecked, [.done, .done, .current, .pending]),
    // 준비되지 않았으면 런타임 상태는 보지 않는다 (타입상 가능한 조합).
    Expected(.licenseNotAccepted(.sample), installed, [.done, .current, .pending, .pending]),
    Expected(.ready(.sample), installed, [.done, .done, .done, .done]),
    Expected(.ready(.sample), notInstalled, [.done, .done, .done, .current]),
    Expected(.ready(.sample), preparing, [.done, .done, .done, .current]),
    Expected(.ready(.sample), unusable, [.done, .done, .done, .current]),
    Expected(.ready(.sample), .defaultRuntimeUnknown, [.done, .done, .done, .current]),
    Expected(.ready(.sample), .failed(.commandFailed), [.done, .done, .done, .current]),
    Expected(.ready(.sample), .notChecked, [.done, .done, .done, .current]),
  ]

  @Test("상태마다 네 단계가 같은 순서이고, 지금 할 단계 앞은 끝남·뒤는 남음이다", arguments: cases)
  func stepsForStatus(expected: Expected) {
    let steps = SetupStep.steps(for: expected.status, runtime: expected.runtime)

    #expect(steps.map(\.kind) == [.installXcode, .acceptLicense, .firstLaunch, .installRuntime])
    #expect(steps.map(\.progress) == expected.progress)
    #expect(steps.map(\.id) == steps.map(\.kind))
  }
}
