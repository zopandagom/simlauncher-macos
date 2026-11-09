import Foundation
import Testing
@testable import Core

struct LayoutTargetTests {
  @Test("Codable 로 왕복해도 같은 값 (창 값으로 저장된다)")
  func codableRoundTrip() throws {
    let targets = [
      LayoutTarget.iOS(VirtualDevice.ID("00000000-0000-0000-0000-000000000001")),
      LayoutTarget.android(AndroidVirtualDevice.ID("Pixel_9")),
    ]

    let decoded = try JSONDecoder().decode([LayoutTarget].self, from: JSONEncoder().encode(targets))

    #expect(decoded == targets)
  }

  @Test("android(_:)·iOS(_:) 는 플랫폼과 기기 ID 를 담는다")
  func factories() {
    let android = LayoutTarget.android(AndroidVirtualDevice.ID("Pixel_9"))
    let iOS = LayoutTarget.iOS(VirtualDevice.ID("ABC"))

    #expect(android == LayoutTarget(platform: .android, deviceID: "Pixel_9"))
    #expect(iOS == LayoutTarget(platform: .iOS, deviceID: "ABC"))
    #expect(android != LayoutTarget.iOS(VirtualDevice.ID("Pixel_9")))
  }

  @Test("창 ID 는 로그 창과 다른 고정 값")
  func windowID() {
    #expect(LayoutTarget.windowID == "device-layout")
    #expect(LayoutTarget.windowID != AppLogTarget.windowID)
  }
}
