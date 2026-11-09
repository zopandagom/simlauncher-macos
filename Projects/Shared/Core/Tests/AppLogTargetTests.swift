import Foundation
import Testing
@testable import Core

struct AppLogTargetTests {
  @Test("Codable 로 왕복해도 같은 값 (창 값으로 저장된다)")
  func codableRoundTrip() throws {
    let targets = [
      AppLogTarget.iOS(VirtualDevice.ID("00000000-0000-0000-0000-000000000001")),
      AppLogTarget.android(AndroidVirtualDevice.ID("Pixel_9")),
    ]

    let decoded = try JSONDecoder().decode([AppLogTarget].self, from: JSONEncoder().encode(targets))

    #expect(decoded == targets)
  }

  @Test("iOS(_:) 는 플랫폼 iOS 와 UDID, 창 ID 는 고정 값")
  func iOSTarget() {
    let target = AppLogTarget.iOS(VirtualDevice.ID("ABC"))

    #expect(target == AppLogTarget(platform: .iOS, deviceID: "ABC"))
    #expect(AppLogTarget.windowID == "device-log")
    #expect(AppLogTarget.Platform.iOS.rawValue == "ios")
  }

  @Test("android(_:) 는 플랫폼 android 와 AVD 이름")
  func androidTarget() {
    let target = AppLogTarget.android(AndroidVirtualDevice.ID("Pixel_9"))

    #expect(target.platform == .android)
    #expect(target.deviceID == "Pixel_9")
    #expect(target != AppLogTarget.iOS(VirtualDevice.ID("Pixel_9")))
  }
}
