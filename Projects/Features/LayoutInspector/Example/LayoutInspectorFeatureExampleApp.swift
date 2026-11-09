import AppKit
import Core
import LayoutInspectorFeature
import ScreenLayoutInterface
import ScreenLayoutTesting
import SwiftUI

/// App 없이 레이아웃 창만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// `ScreenLayoutClientFake` 에 "다음 결과"(스냅샷 종류나 실패)를 넣고 "창 열기"·창의 "새로 고침" 으로 읽게 한다.
/// 스크린샷은 Fixtures 없이 샘플 노드 사각형을 CoreGraphics(AppKit)로 그려 만든 PNG 다.
/// 상태 확인: "읽기를 붙잡기" 를 켜고 열면 처음 읽는 중, 스냅샷이 있을 때 새로 고치면 새로 고치는 중이고 "놓기" 로 끝낸다.
/// "준비 단계부터" 를 켜면 iOS 첫 준비(.preparing) 문구를 보인다. 실패를 고르고 처음 열면 처음 실패, 스냅샷 뒤 새로 고치면
/// 새로 고침 실패 배너다. 노드 0개·시스템 화면·밀도 없음(px 만)은 "다음 결과" 의 스냅샷 종류로 고른다.
@main
struct LayoutInspectorFeatureExampleApp: App {
  @State private var demo = ExampleDemo()

  var body: some Scene {
    WindowGroup {
      ExampleControls(demo: self.demo)
    }
    WindowGroup(id: LayoutTarget.windowID, for: LayoutTarget.self) { $target in
      if let target {
        LayoutInspectorView(model: self.demo.model, target: target)
      }
    }
    .defaultSize(width: 1100, height: 760)
    .restorationBehavior(.disabled)
  }
}

/// 다음 읽기가 돌려줄 결과.
enum ExampleResult: String, CaseIterable, Identifiable {
  case snapshot = "스냅샷"
  case systemScreen = "시스템 화면"
  case noNodes = "노드 0개"
  case noDensity = "밀도 없음 (px 만)"
  case screenNotIdle = "실패: 화면이 계속 바뀜"
  case displayOff = "실패: 화면 꺼짐"
  case automationBusy = "실패: 다른 자동화 도구"
  case deviceNotBooted = "실패: 기기 꺼짐"
  case timedOut = "실패: 시간 초과"
  case unreadable = "실패: 해석 실패"

  var id: Self {
    self
  }

  @MainActor
  func result(png: Data) -> Result<LayoutSnapshot, ScreenLayoutError> {
    let date = Date()
    return switch self {
    case .snapshot: .success(.sample(capturedAt: date, screenshotPNG: png))
    case .systemScreen:
      .success(.sample(
        capturedAt: date,
        screenshotPNG: png,
        appIdentifier: "com.android.systemui",
        isSystemScreen: true
      ))
    case .noNodes: .success(.sample(capturedAt: date, screenshotPNG: png, nodes: []))
    case .noDensity: .success(.sample(capturedAt: date, screenshotPNG: png, pixelsPerUnit: nil))
    case .screenNotIdle: .failure(.screenNotIdle)
    case .displayOff: .failure(.displayOff)
    case .automationBusy: .failure(.automationBusy)
    case .deviceNotBooted: .failure(.deviceNotBooted)
    case .timedOut: .failure(.timedOut)
    case .unreadable: .failure(.unreadable)
    }
  }
}

/// Fake 와 Model.
@MainActor
@Observable
final class ExampleDemo {
  static let target = LayoutTarget.android(AndroidVirtualDevice.ID("Pixel_9"))

  let fake: ScreenLayoutClientFake
  let model: LayoutInspectorModel
  let png = ExampleScreenshot.png(for: LayoutSnapshot.sampleNodes, size: LayoutSize(width: 1080, height: 2400))
  private(set) var next = ExampleResult.snapshot
  private(set) var isHolding = false
  private(set) var startsWithPreparing = false

  init() {
    let fake = ScreenLayoutClientFake()
    self.fake = fake
    self.model = LayoutInspectorModel(screenLayout: fake)
    fake.setDefaultResult(ExampleResult.snapshot.result(png: self.png))
  }

  func setNext(_ next: ExampleResult) {
    self.next = next
    self.fake.setDefaultResult(next.result(png: self.png))
  }

  func setHolding(_ isHolding: Bool) {
    self.isHolding = isHolding
    self.fake.setHolding(isHolding)
  }

  func setStartsWithPreparing(_ startsWithPreparing: Bool) {
    self.startsWithPreparing = startsWithPreparing
    self.fake.setAutomaticPhases(startsWithPreparing ? [.preparing] : [.reading])
  }

  /// 붙잡힌 읽기를 놓기 전에 결과 시각을 지금으로 바꾼다 (같은 결과를 다시 골라도 "마지막 갱신" 이 바뀐다).
  func release() {
    self.fake.setDefaultResult(self.next.result(png: self.png))
    let fake = self.fake
    let sendsReading = self.startsWithPreparing
    Task {
      // 준비 단계부터였으면 .reading 을 보낸 뒤 놓는다 (iOS 의 준비 → 읽기 흐름).
      if sendsReading {
        await fake.sendPhase(.reading, to: Self.target)
      }
      fake.release(Self.target)
    }
  }
}

struct ExampleControls: View {
  @Environment(\.openWindow) private var openWindow
  let demo: ExampleDemo

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        self.openWindow(id: LayoutTarget.windowID, value: ExampleDemo.target)
      } label: {
        Text(verbatim: "레이아웃 창 열기")
      }
      Picker(
        selection: Binding(get: { self.demo.next }, set: { self.demo.setNext($0) })
      ) {
        ForEach(ExampleResult.allCases) { result in
          Text(verbatim: result.rawValue).tag(result)
        }
      } label: {
        Text(verbatim: "다음 결과")
      }
      .fixedSize()
      Toggle(isOn: Binding(get: { self.demo.isHolding }, set: { self.demo.setHolding($0) })) {
        Text(verbatim: "읽기를 붙잡기 (읽는 중 상태 보기)")
      }
      Toggle(isOn: Binding(get: { self.demo.startsWithPreparing }, set: { self.demo.setStartsWithPreparing($0) })) {
        Text(verbatim: "준비 단계부터 (iOS 첫 준비 문구)")
      }
      Button {
        self.demo.release()
      } label: {
        Text(verbatim: "붙잡은 읽기 놓기")
      }
    }
    .padding()
    .frame(minWidth: 360)
  }
}

/// 샘플 노드 사각형을 그린 화면 PNG.
enum ExampleScreenshot {
  static func png(for nodes: [LayoutNode], size: LayoutSize) -> Data {
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size.width, pixelsHigh: size.height, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return LayoutSnapshot.placeholderPNG }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let height = CGFloat(size.height)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()
    let colors: [NSColor] = [.systemGray, .systemBlue, .systemTeal, .systemGreen, .systemYellow]
    for node in nodes where node.frame.width > 0 && node.frame.height > 0 {
      // PNG 는 위가 원점, AppKit 은 아래가 원점이라 뒤집는다.
      let rect = NSRect(
        x: node.frame.x, y: height - node.frame.y - node.frame.height,
        width: node.frame.width, height: node.frame.height
      )
      colors[node.depth % colors.count].withAlphaComponent(0.25).setFill()
      rect.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:]) ?? LayoutSnapshot.placeholderPNG
  }
}

#Preview("레이아웃 창") {
  let demo = ExampleDemo()
  return LayoutInspectorView(model: demo.model, target: ExampleDemo.target)
}
