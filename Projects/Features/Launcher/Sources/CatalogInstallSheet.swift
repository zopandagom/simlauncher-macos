import Core
import SwiftUI

/// 카탈로그에서 설치 시트: 왼쪽은 카탈로그별(저장 순서) 앱 목록과 읽는 중·실패 이유, 오른쪽은 고른 앱의 버전 목록(최신순),
/// 아래는 새로 고침·취소·받아서 설치. 등록한 카탈로그가 없으면 두 열 대신 안내를 보인다. 입력은 모두 Model 의 이벤트 메서드로
/// 넘기고, 받기는 Model 이벤트(`menuTapped`·`refreshButtonTapped`)가 시작한다 (이 View 의 `.task`·`onAppear` 로 받지 않는다).
/// 카탈로그 값(주소·앱·버전 이름·브랜치·태그·빌드 번호)은 번역 키로 쓰지 않고 `Text(verbatim:)` 으로만 보인다.
/// 대상이 여러 대(툴바 "선택한 기기에 앱 설치")면 제목에 대수를, 그 아래 줄에 대상 이름을 보인다.
struct CatalogInstallSheet: View {
  let model: CatalogInstallModel
  /// 마지막으로 그린 상태. 닫히는 동안 Model 의 `draft` 는 이미 nil 이라, 내용이 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: CatalogInstallDraft?
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Group {
      if let draft = self.model.draft ?? self.shownDraft {
        self.content(draft)
      }
    }
    .onChange(of: self.model.draft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  /// 시트 크기는 내용의 min 프레임으로 정해지고 크기 조절이 안 된다. 빈 목록도 같은 프레임이라 크기가 바뀌지 않는다.
  private func content(_ draft: CatalogInstallDraft) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(LauncherText.catalogSheetTitle(for: draft.targets))
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
        if let line = LauncherText.batchTargetsLine(draft.targets) {
          BatchTargetsLine(text: line)
        }
      }
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

  private func emptyView(_ draft: CatalogInstallDraft) -> some View {
    ContentUnavailableView {
      Label(LauncherText.emptyCatalogTitle, systemImage: "tray")
    } description: {
      Text(LauncherText.emptyCatalogMessage(isLocked: draft.isLocked))
    } actions: {
      if draft.showsOpenSettings {
        Button(LauncherText.openSettingsButton) {
          self.openSettings()
        }
      }
      Button(LauncherText.refreshButton) {
        Task { await self.model.refreshButtonTapped() }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func columns(_ draft: CatalogInstallDraft) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(LauncherText.catalogAppsHeader)
          .font(.subheadline.weight(.semibold))
        self.appList(draft)
      }
      .frame(width: 260)
      VStack(alignment: .leading, spacing: 6) {
        Text(LauncherText.catalogVersionsHeader)
          .font(.subheadline.weight(.semibold))
        self.versionPane(draft)
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxHeight: .infinity)
  }

  private func appList(_ draft: CatalogInstallDraft) -> some View {
    List(selection: Binding(get: { draft.selectedApp }, set: { self.model.appSelected($0) })) {
      ForEach(draft.sources) { (source: CatalogSource) in
        CatalogSourceSection(source: source, note: draft.note(for: source))
      }
    }
  }

  @ViewBuilder
  private func versionPane(_ draft: CatalogInstallDraft) -> some View {
    switch draft.versionPane {
    case .noSelection:
      self.placeholder(LauncherText.catalogNoSelection)
    case .loading:
      VStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(LauncherText.catalogLoading)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .noVersions:
      self.placeholder(LauncherText.catalogNoVersions)
    case let .versions(versions):
      List(selection: Binding(get: { draft.selectedVersionID }, set: { self.model.versionSelected($0) })) {
        ForEach(versions) { (version: BuildCatalog.Version) in
          CatalogVersionRow(version: version)
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

  private func buttons(_ draft: CatalogInstallDraft) -> some View {
    HStack {
      // 빈 목록이면 안내 안에 새로 고침이 있다.
      if !draft.isEmpty {
        Button(LauncherText.refreshButton) {
          Task { await self.model.refreshButtonTapped() }
        }
        if draft.isLoading {
          ProgressView()
            .controlSize(.small)
        }
      }
      Spacer()
      Button(LauncherText.cancelButton) {
        self.model.cancelTapped()
      }
      .keyboardShortcut(.cancelAction)
      Button(LauncherText.installURLConfirmButton) {
        Task { await self.model.installButtonTapped() }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(!draft.canInstall)
    }
  }
}

/// 카탈로그 구역 하나: 머리글(저장된 주소 그대로, 한 줄·가운데 생략)과 앱 줄, 또는 읽는 중·실패 이유·쓸 수 없는 주소 이유 줄.
/// 상태 줄은 고를 수 없다.
private struct CatalogSourceSection: View {
  let source: CatalogSource
  /// 상태 줄(실패 이유·쓸 수 없는 주소)과 그 잠김. 읽는 중·읽힌 구역이면 nil.
  let note: CatalogSourceNote?

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
        Text(LauncherText.catalogLoading)
          .foregroundStyle(.secondary)
      }
      .selectionDisabled()
    case let .loaded(catalog):
      if catalog.apps.isEmpty {
        self.statusText(LauncherText.catalogNoApps)
      } else {
        ForEach(catalog.apps) { (app: BuildCatalog.App) in
          Text(verbatim: app.name)
            .tag(CatalogAppKey(sourceID: self.source.id, appID: app.id))
        }
      }
    case .failed, .invalid:
      if let note = self.note {
        self.statusText(LauncherText.catalogSourceNote(note))
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
private struct CatalogVersionRow: View {
  let version: BuildCatalog.Version

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: self.version.name)
      Text(verbatim: LauncherText.versionDetail(self.version))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
