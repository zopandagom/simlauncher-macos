import Core
import SimulatorTesting
import Testing
@testable import LauncherFeature

struct ScreenshotActivityTests {
  private static let states: [VirtualDevice.State] = [.shutdown, .booted, .booting, .shuttingDown, .unknown]

  @Test("작업이 없으면 쓸 수 있는 켜진 기기만 찍을 수 있다", arguments: Self.states)
  func canStartFollowsDeviceRule(state: VirtualDevice.State) {
    let activity = ScreenshotActivity()

    for isAvailable in [true, false] {
      let device = Self.device(state: state, isAvailable: isAvailable)
      let expected = isAvailable && state == .booted
      #expect(activity.canStart(on: device, during: nil) == expected, "쓸 수 있음: \(isAvailable)")
    }
  }

  @Test("같은 기기의 앱 설치·링크 열기 중에는 찍을 수 있고, 켜기·끄기·삭제·초기화 중에는 찍을 수 없다")
  func canStartDuringDeviceTask() {
    let activity = ScreenshotActivity()
    let device = Self.device(state: .booted)

    #expect(activity.canStart(on: device, during: .installApp))
    #expect(activity.canStart(on: device, during: .openURL))
    // 켜기는 켠 뒤 다시 읽기가 끝날 때까지 작업이 남아 목록 값이 켜짐일 수 있다. 그래도 막는다.
    #expect(!activity.canStart(on: device, during: .boot))
    #expect(!activity.canStart(on: device, during: .shutdown))
    #expect(!activity.canStart(on: device, during: .delete))
    #expect(!activity.canStart(on: device, during: .erase))
  }

  @Test("begin 은 허용되면 기록하고, 같은 기기를 찍는 중이면 다시 시작하지 않는다")
  func beginRecordsAndBlocksSameDevice() {
    var activity = ScreenshotActivity()
    let device = Self.device(state: .booted)

    let began = activity.begin(on: device, during: nil)
    #expect(began)
    #expect(activity.isTaking(on: device.id))
    #expect(activity.deviceIDs == [device.id])
    #expect(!activity.canStart(on: device, during: nil))
    let beganAgain = activity.begin(on: device, during: nil)
    #expect(!beganAgain)
    #expect(activity.deviceIDs == [device.id])
  }

  @Test("다른 기기는 함께 찍을 수 있다")
  func otherDevicesAreIndependent() {
    var activity = ScreenshotActivity()
    let phone = Self.device(state: .booted)
    let pad = Self.device(id: SampleID.iPadOff, state: .booted)

    let phoneBegan = activity.begin(on: phone, during: nil)
    #expect(phoneBegan)
    let padBegan = activity.begin(on: pad, during: .installApp)
    #expect(padBegan)
    #expect(activity.deviceIDs == [phone.id, pad.id])
  }

  @Test("begin 이 거절되면 아무것도 바꾸지 않는다")
  func rejectedBeginChangesNothing() {
    var activity = ScreenshotActivity()

    let shutdownBegan = activity.begin(on: Self.device(state: .shutdown), during: nil)
    #expect(!shutdownBegan)
    let unavailableBegan = activity.begin(on: Self.device(state: .booted, isAvailable: false), during: nil)
    #expect(!unavailableBegan)
    let duringShutdownBegan = activity.begin(on: Self.device(state: .booted), during: .shutdown)
    #expect(!duringShutdownBegan)
    #expect(activity == ScreenshotActivity())
  }

  @Test("end 는 그 기기만 지우고, 두 번 불러도 무해하다")
  func endIsIdempotent() {
    var activity = ScreenshotActivity()
    let phone = Self.device(state: .booted)
    let pad = Self.device(id: SampleID.iPadOff, state: .booted)
    _ = activity.begin(on: phone, during: nil)
    _ = activity.begin(on: pad, during: nil)

    activity.end(on: phone.id)
    activity.end(on: phone.id)

    #expect(!activity.isTaking(on: phone.id))
    #expect(activity.deviceIDs == [pad.id])
    #expect(activity.canStart(on: phone, during: nil))
  }

  private static func device(
    id: VirtualDevice.ID = SampleID.iPhoneOn,
    state: VirtualDevice.State,
    isAvailable: Bool = true
  ) -> VirtualDevice {
    VirtualDevice(
      id: id,
      name: "iPhone 17 Pro",
      family: .phone,
      state: state,
      availability: isAvailable ? .available : .unavailable(.runtimeNotInstalled),
      runtime: SampleRuntime.iOS27
    )
  }
}
