import Core
import SwiftUI

/// 앱 실행 시트: 그 기기의 사용자 설치 앱(패키지 이름) 목록에서 하나를 골라 실행한다. 목록을 불러오는 중·빈 목록·실패(이유와
/// "다시 시도")를 보인다. 선택과 버튼은 모두 Model 의 이벤트 메서드로 넘긴다.
struct AndroidLaunchAppSheet: View {
  let model: AndroidDevicesModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `launchAppDraft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: AndroidLaunchAppDraft?

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

  private func form(_ draft: AndroidLaunchAppDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(AndroidDevicesText.launchAppSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      self.content(draft)
        .frame(minHeight: 60, alignment: .topLeading)
      HStack {
        Spacer()
        if case .failed = draft.packages {
          Button(AndroidDevicesText.closeButton) {
            self.model.launchAppCancelTapped()
          }
          .keyboardShortcut(.cancelAction)
          Button(AndroidDevicesText.retryButton) {
            Task { await self.model.launchAppRetryTapped() }
          }
          .keyboardShortcut(.defaultAction)
        } else {
          Button(AndroidDevicesText.cancelButton) {
            self.model.launchAppCancelTapped()
          }
          .keyboardShortcut(.cancelAction)
          Button(AndroidDevicesText.launchConfirmButton) {
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
  private func content(_ draft: AndroidLaunchAppDraft) -> some View {
    switch draft.packages {
    case .loading:
      ProgressView {
        Text(AndroidDevicesText.loadingPackages)
      }
      .frame(maxWidth: .infinity)
    case let .failed(error):
      Label {
        Text(AndroidDevicesText.message(for: error) ?? "")
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "exclamationmark.triangle")
      }
    case let .loaded(packages) where packages.isEmpty:
      Text(AndroidDevicesText.noInstalledPackages)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    case let .loaded(packages):
      // 앱이 많을 수 있어 스크롤되는 목록으로 보인다. 선택은 `Binding(get:set:)` 으로 Model 의 이벤트에 잇는다.
      List(packages, id: \.self, selection: Binding(
        get: { draft.selection },
        set: { self.model.launchAppSelectionChanged($0) }
      )) { package in
        // 패키지 이름은 번역하지 않는 값이다.
        Text(verbatim: package.rawValue)
      }
      .frame(minHeight: 160)
      .accessibilityLabel(AndroidDevicesText.packagePicker)
    }
  }
}
