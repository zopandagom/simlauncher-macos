import Core
import SimulatorInterface
import SwiftUI

/// 테스트 조건 시트 `Form` 의 앱 단위 구역: 앱(고르기·앱 목록 다시 읽기) → 권한(서비스 11개 × 허용·거부·다시 묻기, SimLauncher 가
/// 바꾼 값, 상시 안내) → 푸시 알림(제목·본문 폼 또는 JSON, 상시 안내). 앱을 고르지 않았으면 권한·푸시 알림 구역은 한 줄 안내만 보인다.
/// Model 은 `let model` 로 받아 이벤트 메서드만 부른다. 그 기기에 적용 중인 명령이 있으면 권한·푸시 컨트롤을 끈다 (앱 고르기는 켜 둔다).
struct TestConditionsAppSections: View {
  let model: TestConditionsModel
  let draft: TestConditionsDraft
  let isApplying: Bool

  private var app: TestConditionsAppDraft {
    self.draft.app
  }

  var body: some View {
    Section(LauncherText.appSection) {
      self.appPicker
    }
    Section(LauncherText.privacySection) {
      if let selected = self.app.selectedApp {
        self.privacy(selected)
      } else {
        self.caption(LauncherText.selectAppFirst)
      }
    }
    Section(LauncherText.pushSection) {
      if self.app.selectedApp != nil {
        self.push
      } else {
        self.caption(LauncherText.selectAppFirst)
      }
    }
  }

  // MARK: - 앱

  @ViewBuilder
  private var appPicker: some View {
    switch self.app.apps {
    case .loading:
      ProgressView {
        Text(LauncherText.readingApps)
      }
      .frame(maxWidth: .infinity)
    case let .failed(error):
      VStack(alignment: .leading, spacing: 6) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(LauncherText.appsReadFailed)
              .fontWeight(.semibold)
            Text(LauncherText.testConditionsFailure(error))
              .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        self.refreshButton
      }
    case let .loaded(apps) where apps.isEmpty:
      VStack(alignment: .leading, spacing: 6) {
        Text(LauncherText.noInstalledAppsForConditions)
          .fixedSize(horizontal: false, vertical: true)
        self.refreshButton
      }
    case let .loaded(apps):
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Picker(LauncherText.appSection, selection: Binding<AppBundleID?>(
            get: { self.app.selectedAppID },
            set: { self.model.appSelected($0) }
          )) {
            Text(LauncherText.noAppSelected).tag(AppBundleID?.none)
            ForEach(apps) { installed in
              Text(LauncherText.appPickerName(installed)).tag(Optional(installed.bundleID))
            }
          }
          .pickerStyle(.menu)
          self.refreshButton
        }
        self.caption(LauncherText.appsRefreshNote)
      }
    }
  }

  private var refreshButton: some View {
    Button(LauncherText.refreshAppsButton) {
      Task { await self.model.appsRefreshTapped() }
    }
  }

  // MARK: - 권한

  @ViewBuilder
  private func privacy(_ selected: InstalledApp) -> some View {
    let history = self.model.privacyHistory[self.draft.deviceID]?[selected.bundleID] ?? [:]
    ForEach(IOSPrivacyService.allCases, id: \.self) { service in
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(LauncherText.privacyServiceName(service))
          if let action = history[service] {
            self.caption(LauncherText.privacyHistoryLine(action))
          }
        }
        Spacer()
        Menu(LauncherText.privacyChangeMenu) {
          ForEach(IOSPrivacyAction.allCases, id: \.self) { action in
            Button(LauncherText.privacyActionName(action)) {
              Task { await self.model.privacyTapped(service, action) }
            }
          }
        }
        .fixedSize()
        .disabled(self.isApplying)
        .accessibilityLabel(LauncherText.privacyMenuAccessibilityLabel(service))
      }
    }
    VStack(alignment: .leading, spacing: 2) {
      self.caption(LauncherText.privacyTerminationNote)
      self.caption(LauncherText.privacyStateNote)
      self.caption(LauncherText.sentLocationKeptNote)
      self.caption(LauncherText.notificationPermissionNote)
    }
  }

  // MARK: - 푸시 알림

  @ViewBuilder
  private var push: some View {
    Picker(LauncherText.pushInputLabel, selection: Binding(
      get: { self.app.pushInput },
      set: { self.model.pushInputChanged($0) }
    )) {
      ForEach(TestConditionsAppDraft.PushInputMode.allCases, id: \.self) { mode in
        Text(LauncherText.pushInputName(mode)).tag(mode)
      }
    }
    .pickerStyle(.segmented)
    switch self.app.pushInput {
    case .form:
      TextField(
        LauncherText.pushTitleField,
        text: Binding(get: { self.app.pushTitle }, set: { self.model.pushTitleChanged($0) })
      )
      TextField(
        LauncherText.pushBodyField,
        text: Binding(get: { self.app.pushBody }, set: { self.model.pushBodyChanged($0) })
      )
    case .json:
      VStack(alignment: .leading, spacing: 4) {
        PlainTextEditor(
          text: self.app.pushJSON,
          accessibilityLabel: LauncherText.pushInputName(.json),
          onChange: { self.model.pushJSONChanged($0) }
        )
        .frame(minHeight: 96, maxHeight: 180)
        self.caption(LauncherText.pushByteCount(self.app.pushByteCount))
      }
    }
    if let problem = self.app.pushProblem {
      self.caption(LauncherText.pushProblem(problem))
    }
    HStack {
      self.caption(LauncherText.pushAuthorizationNote)
      Spacer()
      Button(LauncherText.sendPushButton) {
        Task { await self.model.sendPushTapped() }
      }
      .disabled(self.isApplying || self.app.pushPayload == nil)
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
