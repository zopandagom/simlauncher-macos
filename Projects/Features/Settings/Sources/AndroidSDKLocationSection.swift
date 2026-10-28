import Core
import SwiftUI
import UniformTypeIdentifiers

/// "Android SDK 위치" 절: 지금 위치(기본이면 표시), 다른 폴더 고르기·기본 위치로 되돌리기, 관리자 잠금 안내, 마지막 고르기 결과 줄.
/// 폴더 고르기 패널(`fileImporter`, "새 폴더" 로 빈 폴더를 만들 수 있다)의 표시 여부만 View 일시 상태로 두고, 고른 폴더는 Model 에 넘긴다.
struct AndroidSDKLocationSection: View {
  let model: SettingsModel
  @State private var isImporterPresented = false

  var body: some View {
    Section(SettingsText.androidSDKSectionTitle) {
      if self.model.androidSDKPath.isLocked {
        Label(SettingsText.androidSDKLockedNote, systemImage: "lock.fill")
          .fixedSize(horizontal: false, vertical: true)
      }
      self.locationLine
      if !self.model.androidSDKPath.isLocked {
        self.buttons
        VStack(alignment: .leading, spacing: 4) {
          Text(SettingsText.androidSDKGuide)
          Text(SettingsText.androidSDKInstallNote)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      if let result = self.model.androidSDKCandidate {
        self.resultLine(result)
      }
    }
    .fileImporter(isPresented: self.$isImporterPresented, allowedContentTypes: [.folder]) { result in
      // 취소·실패는 무시한다.
      guard case let .success(url) = result else { return }
      Task { await self.model.sdkFolderChosen(url) }
    }
  }

  @ViewBuilder
  private var locationLine: some View {
    switch self.model.androidSDKRootChoice {
    case let .root(root):
      HStack(alignment: .firstTextBaseline) {
        // 경로는 번역하지 않는다.
        Text(verbatim: Self.displayPath(root.url))
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
          .help(Self.displayPath(root.url))
        if root.isDefault {
          Text(SettingsText.androidSDKDefaultBadge)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    case .invalidSetting:
      Label {
        Text(SettingsText.androidSDKInvalidSetting(isLocked: self.model.androidSDKPath.isLocked))
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
    }
  }

  private var buttons: some View {
    HStack {
      Button(SettingsText.androidSDKChooseButton) {
        self.isImporterPresented = true
      }
      .disabled(!self.model.canChooseSDKFolder)
      Button(SettingsText.androidSDKResetButton) {
        self.model.sdkDefaultButtonTapped()
      }
      .disabled(!self.model.canResetSDKFolder)
      if self.model.isInspectingSDKFolder {
        ProgressView()
          .controlSize(.small)
        Text(SettingsText.androidSDKInspecting)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func resultLine(_ result: SettingsSDKFolderResult) -> some View {
    let isPlainSuccess = result.isSaved && result.writable
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(SettingsText.sdkFolderResult(result))
          .fixedSize(horizontal: false, vertical: true)
        if !result.isSaved {
          // 저장하지 않은 폴더는 위 위치 줄에 보이지 않으므로 무엇을 골랐는지 함께 보인다.
          Text(verbatim: result.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
      }
    } icon: {
      Image(systemName: isPlainSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(isPlainSuccess ? .green : .orange)
    }
  }

  /// 끝 `/` 를 뺀 경로 (루트 `/` 는 그대로).
  private static func displayPath(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    guard path.count > 1, path.hasSuffix("/") else { return path }
    return String(path.dropLast())
  }
}
