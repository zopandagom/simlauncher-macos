import AppLogInterface
import AppLogTesting
import Core
import DeviceLogFeature
import Foundation
import SwiftUI

/// App 없이 로그 창만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// `AppLogClientFake` 에 기기 하나·세션 둘(받는 중인 LogProbe, 앱이 끝난 Other)을 넣는다. "로그 창 열기" 는 App 과 같이
/// `openWindow` 로 기기당 창 하나를 연다 (다시 누르면 같은 창이 앞으로 온다).
/// 부하 확인: "5만 줄 넣기" 는 받는 중 세션에 한 번에 5만 줄을, "초당 1000줄" 은 100ms 마다 100줄을 넣는다. 넣은 줄이 5만 줄을
/// 넘으면 Client 처럼 앞을 버린 것으로 알린다 (`setDropped`). 이 상태로 필터 입력·스크롤·일시정지가 멈추지 않는지 본다.
/// "다시 실행" 은 Fake 기본 동작(같은 기기·앱의 받는 중 세션을 새로 더함)이다.
@main
struct DeviceLogFeatureExampleApp: App {
  @State private var demo = ExampleDemo()

  var body: some Scene {
    WindowGroup {
      ExampleControls(demo: self.demo)
    }
    WindowGroup(id: AppLogTarget.windowID, for: AppLogTarget.self) { $target in
      if let target {
        DeviceLogView(model: self.demo.model, target: target)
      }
    }
    .defaultSize(width: 900, height: 600)
    .restorationBehavior(.disabled)
  }
}

/// Fake 와 Model, 부하 타이머.
@MainActor
@Observable
final class ExampleDemo {
  static let device = VirtualDevice.ID("5C0F3A2E-0000-4000-8000-000000000001")
  static let target = AppLogTarget.iOS(device)
  static let maxLines = 50000

  let fake: AppLogClientFake
  let model: DeviceLogModel
  let receivingSession = AppLogSessionID(UUID())
  private(set) var isStreaming = false
  @ObservationIgnored private var streamTask: Task<Void, Never>?
  @ObservationIgnored private var appended = 0

  init() {
    let started = Date()
    let ended = AppLogSessionSummary(
      id: AppLogSessionID(UUID()), target: Self.target, deviceName: "iPhone 17 Pro", appID: "com.example.other",
      appName: "Other", startedAt: started.addingTimeInterval(-600), state: .ended(.appExited)
    )
    let receiving = AppLogSessionSummary(
      id: self.receivingSession, target: Self.target, deviceName: "iPhone 17 Pro",
      appID: "dev.simlauncher.logprobe", appName: "LogProbe", startedAt: started, state: .receiving
    )
    self.fake = AppLogClientFake(sessions: [ended, receiving])
    self.model = DeviceLogModel(appLog: self.fake)
    self.fake.append(ExampleLines.endedSession, to: ended.id)
    self.append(ExampleLines.start)
  }

  func appendFiftyThousand() {
    let start = self.appended
    self.append((0 ..< Self.maxLines).map { ExampleLines.load(start + $0) })
  }

  func setStreaming(_ isStreaming: Bool) {
    self.isStreaming = isStreaming
    self.streamTask?.cancel()
    self.streamTask = nil
    guard isStreaming else { return }
    self.streamTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        guard let self, !Task.isCancelled else { return }
        let start = self.appended
        self.append((0 ..< 100).map { ExampleLines.load(start + $0) })
      }
    }
  }

  private func append(_ texts: [String]) {
    self.fake.append(texts, to: self.receivingSession)
    self.appended += texts.count
    if self.appended > Self.maxLines {
      self.fake.setDropped(self.appended - Self.maxLines, for: self.receivingSession)
    }
  }
}

struct ExampleControls: View {
  @Environment(\.openWindow) private var openWindow
  let demo: ExampleDemo

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        self.openWindow(id: AppLogTarget.windowID, value: ExampleDemo.target)
      } label: {
        Text(verbatim: "로그 창 열기")
      }
      Button {
        self.demo.appendFiftyThousand()
      } label: {
        Text(verbatim: "5만 줄 넣기")
      }
      Toggle(isOn: Binding(get: { self.demo.isStreaming }, set: { self.demo.setStreaming($0) })) {
        Text(verbatim: "초당 1000줄")
      }
    }
    .padding()
    .frame(minWidth: 280)
  }
}

/// 넣을 줄. 머리말 형식은 실측(OS_ACTIVITY_DT_MODE 의 Logger·NSLog, DT_MODE 없는 NSLog)을 따른다.
enum ExampleLines {
  static let start = [
    "probe start",
    "multi line 1",
    "multi line 2",
    "2026-11-03 15:58:29.655736+0900 LogProbe[82561:42341349] [probe] logger default hello",
    "2026-11-03 15:58:29.700112+0900 LogProbe[82561:42341349] nslog hello 1",
    "2026-11-03 15:58:29.812345+0900 LogProbe[82561:42341350] [General] "
      + "Failed to send CA Event for app launch measurements",
    "tick 1",
    "tick 2",
    "tick 3",
    "tick 4",
    "tick 5",
  ]

  static let endedSession = [
    "other start",
    "2026-11-03 15:48:08.123 Other App[80001:42300001] nslog without DT_MODE",
    "Other/main.swift:23: Fatal error: probe crash",
  ]

  /// 부하 줄. 7줄마다 줄바꿈되는 긴 줄을 섞는다.
  static func load(_ number: Int) -> String {
    let base = "2026-11-03 16:19:43.695726+0900 LogProbe[90410:42391228] [probe] line \(number) status=200 payload"
    return number % 7 == 0 ? base + String(repeating: " long text", count: 30) : base
  }
}

#Preview("받는 중 세션 (앱 고르기 둘)") {
  let demo = ExampleDemo()
  return DeviceLogView(model: demo.model, target: ExampleDemo.target)
    .frame(width: 900, height: 600)
}

#Preview("세션 없음") {
  DeviceLogView(
    model: DeviceLogModel(appLog: AppLogClientFake()),
    target: .iOS(VirtualDevice.ID("5C0F3A2E-0000-4000-8000-000000000009"))
  )
}
