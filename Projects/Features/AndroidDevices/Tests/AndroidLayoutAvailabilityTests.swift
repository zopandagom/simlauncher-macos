import AndroidEmulatorTesting
import Core
import Testing
@testable import AndroidDevicesFeature

/// 행 "레이아웃 보기" 를 누를 수 있는지 (`AndroidLayoutAvailability.canOpen`).
struct AndroidLayoutAvailabilityTests {
  private let tablet = AndroidVirtualDevice.bootedTabletSample

  /// 기기 작업이 없거나 앱 작업이면 열 수 있다 (스크린샷과 같은 작업 규칙).
  private static func allowsLayout(_ task: AndroidDeviceTask?) -> Bool {
    switch task {
    case .none, .installApp, .launchApp, .openURL: true
    case .boot, .shutdown, .delete, .erase: false
    }
  }

  @Test("쓸 수 있는 켜진 기기만, 작업이 없거나 앱 작업 중일 때만 열 수 있다", arguments: AndroidCaptureActivityTests.allTasks)
  func rules(_ task: AndroidDeviceTask?) {
    #expect(AndroidLayoutAvailability.canOpen(device: self.tablet, during: task) == Self.allowsLayout(task))
    #expect(!AndroidLayoutAvailability.canOpen(device: .phoneSample, during: task))
    #expect(!AndroidLayoutAvailability.canOpen(device: self.tablet.with(state: .booting), during: task))
    #expect(!AndroidLayoutAvailability.canOpen(device: .unsupportedNameSample, during: task))
  }

  @Test("스크린샷을 찍는 중·녹화 중이어도 열 수 있다 (판정이 캡처 기록을 보지 않는다)")
  func capturesDoNotBlock() {
    var screenshots = AndroidScreenshotActivity()
    var recordings = AndroidRecordingActivity()
    let beganScreenshot = screenshots.begin(on: self.tablet, during: nil)
    let beganRecording = recordings.begin(on: self.tablet, during: nil)
    #expect(beganScreenshot)
    #expect(beganRecording)
    #expect(!screenshots.canStart(on: self.tablet, during: nil))
    #expect(AndroidLayoutAvailability.canOpen(device: self.tablet, during: nil))
  }

  @Test("막힌 이유 툴팁은 꺼짐·쓸 수 없음이 서로 다르고 레이아웃을 말한다")
  func blockReasons() {
    let notBooted = AndroidDevicesText.layoutBlockReason(.notBooted)
    let unavailable = AndroidDevicesText.layoutBlockReason(.unavailable)
    #expect(notBooted != unavailable)
    #expect(notBooted.contains("레이아웃"))
    #expect(unavailable.contains("레이아웃"))
    #expect(AndroidDevicesText.layoutButton == "레이아웃 보기")
  }
}
