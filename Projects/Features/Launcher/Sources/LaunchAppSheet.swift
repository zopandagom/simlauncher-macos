import Core
import SwiftUI

/// 앱 실행 시트: 그 기기의 사용자 설치 앱 목록에서 하나를 골라 로그를 받으며 실행한다. 기기를 켜는 중·목록을 불러오는 중·빈 목록·
/// 실패(켜기·목록 읽기를 가르는 제목, 이유와 "다시 시도")를 보인다. 선택과 버튼은 모두 Model 의 이벤트 메서드로 넘긴다.
/// 앱이 정한 이름·버전·번들 ID 는 번역하지 않는 값이라 `Text(verbatim:)` 로 보인다.
struct LaunchAppSheet: View {
  let model: LauncherAppSheetsModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `launchAppDraft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: LaunchAppDraft?

  var body: some View {
    Group {
      if let draft = self.model.launchAppDraft ?? self.shownDraft {
        self.form(draft)
      }
    }
    .onChange(of: self.model.launchAppDraft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func form(_ draft: LaunchAppDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(LauncherText.launchAppSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      self.content(draft)
        .frame(minHeight: 60, alignment: .topLeading)
      if case .loaded = draft.apps {
        Text(LauncherText.launchAppSheetNote)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        if case .failed = draft.apps {
          Button(LauncherText.closeButton) {
            self.model.launchAppCancelTapped()
          }
          .keyboardShortcut(.cancelAction)
          Button(LauncherText.retryButton) {
            Task { await self.model.launchAppRetryTapped() }
          }
          .keyboardShortcut(.defaultAction)
        } else {
          Button(LauncherText.cancelButton) {
            self.model.launchAppCancelTapped()
          }
          .keyboardShortcut(.cancelAction)
          Button(LauncherText.launchAppConfirmButton) {
            Task { await self.model.launchAppConfirmTapped() }
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!draft.canSubmit)
        }
      }
    }
    .padding(20)
    .frame(minWidth: 420)
  }

  @ViewBuilder
  private func content(_ draft: LaunchAppDraft) -> some View {
    switch draft.apps {
    case .booting:
      ProgressView {
        Text(LauncherText.bootingForAppList)
      }
      .frame(maxWidth: .infinity)
    case .loading:
      ProgressView {
        Text(LauncherText.loadingInstalledApps)
      }
      .frame(maxWidth: .infinity)
    case let .failed(failure, stage):
      Label {
        VStack(alignment: .leading, spacing: 4) {
          Text(LauncherText.launchAppFailureHeading(for: stage))
            .fontWeight(.semibold)
          Text(LauncherText.launchAppListMessage(for: failure))
            .fixedSize(horizontal: false, vertical: true)
        }
      } icon: {
        Image(systemName: "exclamationmark.triangle")
      }
    case let .loaded(apps) where apps.isEmpty:
      Text(LauncherText.noInstalledApps)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    case let .loaded(apps):
      // 앱이 많을 수 있어 스크롤되는 목록으로 보인다. 선택은 `Binding(get:set:)` 으로 Model 의 이벤트에 잇는다.
      List(apps, selection: Binding(
        get: { draft.selection },
        set: { self.model.launchAppSelectionChanged($0) }
      )) { app in
        self.appRow(app)
      }
      .frame(minHeight: 160)
      .accessibilityLabel(LauncherText.installedAppPicker)
    }
  }

  /// 표시 이름이 같은 앱이 있을 수 있어 번들 ID 를 함께 보인다 (있으면 버전도).
  private func appRow(_ app: InstalledApp) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: app.displayName)
        .lineLimit(1)
        .truncationMode(.middle)
      HStack(spacing: 8) {
        Text(verbatim: app.bundleID.rawValue)
          .lineLimit(1)
          .truncationMode(.middle)
        if let version = LauncherText.appVersionLabel(version: app.version, build: app.build) {
          Text(verbatim: version)
            .lineLimit(1)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}
