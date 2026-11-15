import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import SwiftUI
import Synchronization
import UpdateCheckInterface
import UpdateCheckTesting
import UpdateFeature

/// App 없이 업데이트 배너·업데이트 확인 창을 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 위의 고르기로 `UpdateCheckClientFake` 의 결과(새 버전·최신·비교 불가·실패 케이스 전부)를 바꾸고, "건너뛴 버전으로 저장" 은
/// `PreferencesClientFake` 에 건너뛴 버전을 넣는다 (고른 값은 Fake 설정만 바꾼다. 결과는 다음 확인 때 보인다).
/// "느리게(멈춤)" 를 켜면 이후 확인이 "재개" 까지 멈춘다: 창을 닫고 다시 열어도 요청 수가 그대로인지(진행 중 요청에 합류) 본다.
/// "시계 25시간 앞으로" 는 Model 의 `now` 가 읽는 오프셋을 밀어 숨김·기록 만료를 본다. "지금 버전 모름" 은 Model 을 지금 버전 없이
/// 다시 만든다. "저장소 없는 빌드의 창" 은 배포 저장소가 없는 Fake 로 만든 Model 의 창(방어 안내)을 연다.
@main
struct UpdateFeatureExampleApp: App {
  @State private var demo = ExampleDemo()

  var body: some Scene {
    WindowGroup {
      ExampleControls(demo: self.demo)
        .safeAreaInset(edge: .top, spacing: 0) {
          UpdateBanner(model: self.demo.model)
        }
    }
    .commands {
      UpdateCommands(model: self.demo.model)
    }
    Window(UpdateCheckView.windowTitle, id: UpdateCheckView.windowID) {
      UpdateCheckView(model: self.demo.model)
    }
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
    .defaultLaunchBehavior(.suppressed)
    .commandsRemoved()
    Window(Text(verbatim: "저장소 없는 빌드"), id: ExampleDemo.unavailableWindowID) {
      UpdateCheckView(model: self.demo.unavailableModel)
    }
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
    .defaultLaunchBehavior(.suppressed)
  }
}

/// Fake 결과 고르기.
enum ExampleResult: String, CaseIterable, Identifiable {
  case newer
  case upToDate
  case latestUnrecognized
  case offline
  case timedOut
  case connectionFailed
  case refused
  case notFound
  case httpStatus
  case unexpectedResponse
  case failed
  case cancelled

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .newer: "새 버전 1.3.0"
    case .upToDate: "최신 (1.2.0)"
    case .latestUnrecognized: "비교 불가: 버전 값이 숫자 버전 아님"
    case .offline: "실패: 오프라인"
    case .timedOut: "실패: 시간 초과"
    case .connectionFailed: "실패: 연결 실패"
    case .refused: "실패: 거절 (403·429)"
    case .notFound: "실패: 없음 (404)"
    case .httpStatus: "실패: 그 밖 HTTP (502)"
    case .unexpectedResponse: "실패: 응답 이상"
    case .failed: "실패: 그 밖"
    case .cancelled: "실패: 취소"
    }
  }

  var result: Result<AppVersion?, UpdateCheckError> {
    switch self {
    case .newer: .success(AppVersion("1.3.0"))
    case .upToDate: .success(AppVersion("1.2.0"))
    case .latestUnrecognized: .success(nil)
    case .offline: .failure(.offline)
    case .timedOut: .failure(.timedOut)
    case .connectionFailed: .failure(.connectionFailed)
    case .refused: .failure(.refused)
    case .notFound: .failure(.notFound)
    case .httpStatus: .failure(.httpStatus(502))
    case .unexpectedResponse: .failure(.unexpectedResponse)
    case .failed: .failure(.failed)
    case .cancelled: .failure(.cancelled)
    }
  }
}

/// Model 의 `now` 가 읽는 시계. 버튼으로 앞으로 민다.
final class ExampleClock: Sendable {
  private let offset = Mutex<TimeInterval>(0)

  func now() -> Date {
    Date().addingTimeInterval(self.offset.withLock { $0 })
  }

  func advance(by interval: TimeInterval) {
    self.offset.withLock { $0 += interval }
  }

  var offsetHours: Int {
    Int(self.offset.withLock { $0 } / 3600)
  }
}

/// Fake 와 Model.
@MainActor
@Observable
final class ExampleDemo {
  static let unavailableWindowID = "update-check-unavailable"

  let updateCheck = UpdateCheckClientFake(result: ExampleResult.newer.result)
  let preferences = PreferencesClientFake()
  let clock = ExampleClock()
  private(set) var model: UpdateModel
  let unavailableModel: UpdateModel
  private(set) var selected = ExampleResult.newer
  private(set) var isSlow = false
  private(set) var isCurrentKnown = true

  init() {
    let clock = self.clock
    self.model = Self.makeModel(updateCheck: self.updateCheck, preferences: self.preferences, clock: clock, known: true)
    self.unavailableModel = UpdateModel(
      updateCheck: UpdateCheckClientFake(releasePageURL: nil),
      preferences: PreferencesClientFake(),
      currentVersion: AppVersion("1.2.0"),
      now: { clock.now() }
    )
  }

  private static func makeModel(
    updateCheck: UpdateCheckClientFake,
    preferences: PreferencesClientFake,
    clock: ExampleClock,
    known: Bool
  ) -> UpdateModel {
    UpdateModel(
      updateCheck: updateCheck,
      preferences: preferences,
      currentVersion: known ? AppVersion("1.2.0") : nil,
      now: { clock.now() }
    )
  }

  func select(_ result: ExampleResult) {
    self.selected = result
    self.updateCheck.setResult(result.result)
  }

  func setSlow(_ isSlow: Bool) {
    self.isSlow = isSlow
    if isSlow {
      self.updateCheck.suspend()
    } else {
      self.updateCheck.resume()
    }
  }

  func setCurrentKnown(_ known: Bool) {
    self.isCurrentKnown = known
    self.model = Self.makeModel(
      updateCheck: self.updateCheck,
      preferences: self.preferences,
      clock: self.clock,
      known: known
    )
  }

  func storeSkipped() {
    self.preferences.setStoredSkippedUpdateVersion("1.3.0", isLocked: false)
  }

  func setAutomaticEnabled(_ isEnabled: Bool) {
    self.preferences.setStoredAutomaticUpdateCheck(isEnabled, isLocked: false)
  }

  /// 저장된 기록·숨김·건너뛰기를 지운다 (다시 자동 확인할 수 있게).
  func clearStored() {
    self.preferences.setStoredLastUpdateCheck(nil, isLocked: false)
    self.preferences.setStoredUpdateBannerDismissal(nil, isLocked: false)
    self.preferences.setStoredSkippedUpdateVersion(nil, isLocked: false)
  }
}

/// 고르기·버튼과 Fake·저장 값 표시.
struct ExampleControls: View {
  let demo: ExampleDemo
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Form {
      Section {
        Picker(
          selection: Binding(get: { self.demo.selected }, set: { self.demo.select($0) })
        ) {
          ForEach(ExampleResult.allCases) { result in
            Text(verbatim: result.title).tag(result)
          }
        } label: {
          Text(verbatim: "다음 확인 결과")
        }
        Toggle(isOn: Binding(get: { self.demo.isSlow }, set: { self.demo.setSlow($0) })) {
          Text(verbatim: "느리게(멈춤)")
        }
        Toggle(isOn: Binding(get: { self.demo.isCurrentKnown }, set: { self.demo.setCurrentKnown($0) })) {
          Text(verbatim: "지금 버전 1.2.0 읽음 (끄면 지금 버전 모름, Model 을 다시 만든다)")
        }
        Toggle(
          isOn: Binding(
            get: { self.demo.preferences.storedAutomaticUpdateCheck.isEnabled },
            set: { self.demo.setAutomaticEnabled($0) }
          )
        ) {
          Text(verbatim: "자동 확인 켬 (저장 값)")
        }
      }
      Section {
        HStack {
          Button {
            self.openWindow(id: UpdateCheckView.windowID)
            Task { await self.demo.model.checkForUpdatesRequested() }
          } label: {
            Text(verbatim: "업데이트 확인…")
          }
          Button {
            self.demo.setSlow(false)
          } label: {
            Text(verbatim: "재개")
          }
          Button {
            Task { await self.demo.model.appLaunched() }
          } label: {
            Text(verbatim: "실행 시 자동 확인")
          }
          Button {
            Task { await self.demo.model.appBecameActive() }
          } label: {
            Text(verbatim: "활성화 시 자동 확인")
          }
        }
        HStack {
          Button {
            self.demo.clock.advance(by: 25 * 3600)
          } label: {
            Text(verbatim: "시계 25시간 앞으로")
          }
          Button {
            self.demo.storeSkipped()
          } label: {
            Text(verbatim: "1.3.0 을 건너뛴 버전으로 저장")
          }
          Button {
            self.demo.clearStored()
          } label: {
            Text(verbatim: "기록·숨김·건너뛰기 지우기")
          }
          Button {
            self.openWindow(id: ExampleDemo.unavailableWindowID)
          } label: {
            Text(verbatim: "저장소 없는 빌드의 창")
          }
        }
      }
      Section {
        // Fake·시계는 관찰되지 않아 주기적으로 다시 그린다.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
          self.status
        }
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 640, minHeight: 480)
  }

  private var status: some View {
    let preferences = self.demo.preferences
    let dismissal = preferences.storedUpdateBannerDismissal.map { "\($0.version.description) @ \($0.dismissedAt)" }
    let lines = [
      "요청 수: \(self.demo.updateCheck.callCount) (멈춰 기다림 \(self.demo.updateCheck.suspendedCallCount))",
      "시계 오프셋: +\(self.demo.clock.offsetHours)시간",
      "마지막 확인 기록: \(preferences.storedLastUpdateCheck.map { "\($0)" } ?? "없음")",
      "배너 숨김: \(dismissal ?? "없음")",
      "건너뛴 버전: \(preferences.storedSkippedUpdateVersion ?? "없음")",
    ]
    return VStack(alignment: .leading, spacing: 4) {
      ForEach(lines, id: \.self) { line in
        Text(verbatim: line)
          .font(.callout.monospaced())
      }
    }
  }
}

#Preview("배너와 확인 창 (새 버전)") {
  let demo = ExampleDemo()
  VStack(spacing: 0) {
    UpdateBanner(model: demo.model)
    UpdateCheckView(model: demo.model)
  }
  .task {
    await demo.model.appLaunched()
  }
}

#Preview("저장소 없는 빌드의 창") {
  UpdateCheckView(model: ExampleDemo().unavailableModel)
}
