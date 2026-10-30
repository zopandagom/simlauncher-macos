import Core
import SwiftUI

/// 카탈로그에서 설치 시트: 왼쪽은 카탈로그별(저장 순서) Android 앱 목록과 읽는 중·실패 이유·Android 앱이 없는 이유, 오른쪽은
/// 고른 앱의 버전 목록(최신순), 아래는 새로 고침·취소·받아서 설치. 등록한 카탈로그가 없으면 두 열 대신 안내를 보인다.
/// iOS `CatalogInstallSheet` 와 같은 배치이고, 대상이 한 대면 제목에 기기를, 여러 대면 제목 아래 대상 줄에 이름을 보인다. 입력은 모두 Model 의 이벤트 메서드로
/// 넘기고, 받기는 Model 이벤트(`catalogMenuTapped`·`catalogRefreshTapped`)가 시작한다 (이 View 의 `.task`·`onAppear` 로 받지 않는다).
/// 카탈로그 값(주소·앱·버전 이름·브랜치·태그·빌드 번호)은 번역 키로 쓰지 않고 `Text(verbatim:)` 으로만 보인다.
struct AndroidCatalogInstallSheet: View {
  let model: AndroidDownloadInstallModel
  /// 마지막으로 그린 상태. 닫히는 동안 Model 의 `catalogDraft` 는 이미 nil 이라, 내용이 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: AndroidCatalogInstallDraft?
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Group {
      if let draft = self.model.catalogDraft ?? self.shownDraft {
        self.content(draft)
      }
    }
    .onChange(of: self.model.catalogDraft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  /// 시트 크기는 내용의 min 프레임으로 정해지고 크기 조절이 안 된다. 빈 목록도 같은 프레임이라 크기가 바뀌지 않는다.
  private func content(_ draft: AndroidCatalogInstallDraft) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      AndroidSheetTitle(
        title: AndroidDevicesText.catalogSheetTitle(for: draft.targets),
        targetsLine: AndroidDevicesText.batchTargetsLine(draft.targets)
      )
      if draft.isEmpty {
        self.emptyView(draft)
      } else {
        self.columns(draft)
      }
      self.buttons(draft)
    }
    .padding(20)
    .frame(minWidth: 720, minHeight: 460)
  }

  private func emptyView(_ draft: AndroidCatalogInstallDraft) -> some View {
    ContentUnavailableView {
      Label(AndroidDevicesText.emptyCatalogTitle, systemImage: "tray")
    } description: {
      Text(AndroidDevicesText.emptyCatalogMessage(isLocked: draft.isLocked))
    } actions: {
      if draft.showsOpenSettings {
        Button(AndroidDevicesText.openSettingsButton) {
          self.openSettings()
        }
      }
      Button(AndroidDevicesText.refreshButton) {
        Task { await self.model.catalogRefreshTapped() }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func columns(_ draft: AndroidCatalogInstallDraft) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(AndroidDevicesText.catalogAppsHeader)
          .font(.subheadline.weight(.semibold))
        self.appList(draft)
      }
      .frame(width: 260)
      VStack(alignment: .leading, spacing: 6) {
        Text(AndroidDevicesText.catalogVersionsHeader)
          .font(.subheadline.weight(.semibold))
        self.versionPane(draft)
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxHeight: .infinity)
  }

  private func appList(_ draft: AndroidCatalogInstallDraft) -> some View {
    List(selection: Binding(get: { draft.selectedApp }, set: { self.model.catalogAppSelected($0) })) {
      ForEach(draft.sources) { (source: AndroidCatalogSource) in
        AndroidCatalogSourceSection(
          source: source,
          apps: draft.apps(in: source),
          emptyReason: draft.emptyReason(for: source),
          note: draft.note(for: source)
        )
      }
    }
  }

  @ViewBuilder
  private func versionPane(_ draft: AndroidCatalogInstallDraft) -> some View {
    switch draft.versionPane {
    case .noSelection:
      self.placeholder(AndroidDevicesText.catalogNoSelection)
    case .loading:
      VStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(AndroidDevicesText.catalogLoading)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .noVersions:
      self.placeholder(AndroidDevicesText.catalogNoVersions)
    case let .versions(versions):
      List(selection: Binding(get: { draft.selectedVersionID }, set: { self.model.catalogVersionSelected($0) })) {
        ForEach(versions) { (version: BuildCatalog.Version) in
          AndroidCatalogVersionRow(version: version)
            .tag(version.id)
        }
      }
    }
  }

  private func placeholder(_ text: String) -> some View {
    Text(text)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func buttons(_ draft: AndroidCatalogInstallDraft) -> some View {
    HStack {
      // 빈 목록이면 안내 안에 새로 고침이 있다.
      if !draft.isEmpty {
        Button(AndroidDevicesText.refreshButton) {
          Task { await self.model.catalogRefreshTapped() }
        }
        if draft.isLoading {
          ProgressView()
            .controlSize(.small)
        }
      }
      Spacer()
      Button(AndroidDevicesText.cancelButton) {
        self.model.catalogCancelTapped()
      }
      .keyboardShortcut(.cancelAction)
      Button(AndroidDevicesText.installURLConfirmButton) {
        Task { await self.model.catalogInstallTapped() }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(!draft.canInstall)
    }
  }
}

/// 카탈로그 구역 하나: 머리글(저장된 주소 그대로, 한 줄·가운데 생략)과 Android 앱 줄, 또는 읽는 중·실패 이유·쓸 수 없는 주소 이유·
/// Android 앱이 없는 이유 줄. 상태 줄은 고를 수 없다.
private struct AndroidCatalogSourceSection: View {
  let source: AndroidCatalogSource
  /// 이 구역의 Android 앱 (파일 순서). 읽는 중·실패면 비어 있다.
  let apps: [BuildCatalog.App]
  /// 읽혔지만 Android 앱이 없는 이유. 앱이 있거나 읽는 중·실패면 nil.
  let emptyReason: AndroidCatalogEmptyReason?
  /// 상태 줄(실패 이유·쓸 수 없는 주소)과 그 잠김. 읽는 중·읽힌 구역이면 nil.
  let note: AndroidCatalogSourceNote?

  var body: some View {
    Section {
      self.rows
    } header: {
      Text(verbatim: self.source.raw)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(Text(verbatim: self.source.raw))
    }
  }

  @ViewBuilder
  private var rows: some View {
    switch self.source.state {
    case .loading:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text(AndroidDevicesText.catalogLoading)
          .foregroundStyle(.secondary)
      }
      .selectionDisabled()
    case .loaded:
      if let reason = self.emptyReason {
        self.statusText(AndroidDevicesText.catalogEmptyReason(reason))
      } else {
        ForEach(self.apps) { (app: BuildCatalog.App) in
          Text(verbatim: app.name)
            .tag(AndroidCatalogAppKey(sourceID: self.source.id, appID: app.id))
        }
      }
    case .failed, .invalid:
      if let note = self.note {
        self.statusText(AndroidDevicesText.catalogSourceNote(note))
      }
    }
  }

  /// 문구 (안의 위치·id 는 이미 문자열에 들어 있어 번역 키로 다시 찾지 않는다).
  private func statusText(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .selectionDisabled()
  }
}

/// 버전 한 줄: 이름과 캡션(태그 · 브랜치 · 빌드 번호 · 생성 시각).
private struct AndroidCatalogVersionRow: View {
  let version: BuildCatalog.Version

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: self.version.name)
      Text(verbatim: AndroidDevicesText.versionDetail(self.version))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
