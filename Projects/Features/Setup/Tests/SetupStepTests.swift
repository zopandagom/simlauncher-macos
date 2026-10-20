import Core
import DevEnvironmentTesting
import Testing
@testable import SetupFeature

struct SetupStepTests {
  typealias Expected = (DevEnvironmentStatus, [SetupStep.Progress])

  static let cases: [Expected] = [
    (.xcodeNotInstalled, [.current, .pending, .pending]),
    (.commandLineToolsOnly, [.current, .pending, .pending]),
    (.licenseNotAccepted(.sample), [.done, .current, .pending]),
    (.firstLaunchRequired(.sample), [.done, .done, .current]),
    (.ready(.sample), [.done, .done, .done]),
  ]

  @Test("상태마다 세 단계가 같은 순서이고, 지금 할 단계 앞은 끝남·뒤는 남음이다", arguments: cases)
  func stepsForStatus(status: DevEnvironmentStatus, progress: [SetupStep.Progress]) {
    let steps = SetupStep.steps(for: status)

    #expect(steps.map(\.kind) == [.installXcode, .acceptLicense, .firstLaunch])
    #expect(steps.map(\.progress) == progress)
    #expect(steps.map(\.id) == steps.map(\.kind))
  }
}
