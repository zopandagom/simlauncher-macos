import AndroidEmulatorInterface
import Core
import SwiftUI

/// Android 설치된 앱 시트 (iOS `InstalledAppsSheet` 와 같은 모양): 제목(기기 이름) → 안내 → 목록(첫 읽기 진행 표시, 실패 줄과
/// "다시 읽기", 빈 목록 안내, 패키지 목록) → 진행 줄·결과 줄 → "앱 목록 다시 읽기"·"삭제…"·"닫기". "삭제…" 는 확인
/// 대화상자(패키지 이름·기기, 기본 버튼은 취소)를 띄운다. 선택과 버튼은 모두 Model 의 이벤트 메서드로 넘긴다.
/// 삭제하는 동안은 닫을 수 없다: "닫기" 버튼과 그 Esc(`.cancelAction`)가 꺼지고, 시스템 닫기도 `.interactiveDismissDisabled` 로
/// 막는다 (Model 의 `closeTapped`·`sheetDismissed` 도 같은 조건으로 무시한다).
/// 패키지 이름은 번역하지 않는 값이라 `Text(verbatim:)` 로 보인다.
struct AndroidInstalledAppsSheet: View {
  let model: AndroidInstalledAppsModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `draft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: AndroidInstalledAppsDraft?
  /// 마지막으로 띄운 확인 대기. "삭제"·"취소" 를 누르면 Model 이 곧바로 `pendingAction` 을 비우므로, 대화상자가 닫히는 동안 제목·
  /// 본문이 비지 않도록 View 가 들고 있는다 (기기 삭제 확인의 `presentedConfirmation` 과 같다).
  @State private var shownAction: AndroidInstalledAppsDraft.Action?

  var body: some View {
    Group {
      if let draft = self.model.draft ?? self.shownDraft {
        self.form(draft)
      }
    }
    .onChange(of: self.model.draft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func form(_ draft: AndroidInstalledAppsDraft) -> some View {
    // 여는 첫 렌더는 Model 값, 닫히는 동안은 들고 있던 값.
    let shownAction = draft.pendingAction ?? self.shownAction
    return VStack(alignment: .leading, spacing: 12) {
      Text(AndroidDevicesText.installedAppsSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(AndroidDevicesText.installedAppsSheetNote)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      self.list(draft)
        .frame(minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
      self.status(draft)
      self.buttons(draft)
    }
    .padding(20)
    .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 480)
    .interactiveDismissDisabled(!draft.canClose)
    .confirmationDialog(
      AndroidDevicesText.removeAppConfirmationTitle(shownAction?.package.rawValue ?? ""),
      isPresented: Binding(
        get: { draft.pendingAction != nil },
        set: { isPresented in
          if !isPresented {
            self.model.actionCancelled()
          }
        }
      ),
      titleVisibility: .visible,
      presenting: shownAction
    ) { action in
      Button(AndroidDevicesText.removeAppConfirmButton, role: .destructive) {
        // 버튼 동작 뒤 SwiftUI 가 곧바로 actionCancelled() 를 부르므로 값을 넘긴다.
        Task { await self.model.actionConfirmed(action) }
      }
      Button(AndroidDevicesText.cancelButton, role: .cancel) {
        self.model.actionCancelled()
      }
    } message: { _ in
      Text(AndroidDevicesText.removeAppConfirmationMessage(on: draft.device))
    }
    .onChange(of: draft.pendingAction, initial: true) { _, new in
      if let new {
        self.shownAction = new
      }
    }
  }

  /// "앱 목록 다시 읽기"(다시 읽는 동안 작은 진행 표시)·"삭제…"·"닫기". 삭제하는 동안 "닫기" 와 그 Esc 를 끈다.
  private func buttons(_ draft: AndroidInstalledAppsDraft) -> some View {
    HStack(spacing: 8) {
      Button(AndroidDevicesText.refreshAppsButton) {
        Task { await self.model.refreshTapped() }
      }
      .disabled(!draft.canRefresh)
      if case .reloading = draft.packages {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(AndroidDevicesText.readingApps)
      }
      Spacer()
      Button(AndroidDevicesText.removeAppButton, role: .destructive) {
        self.model.removeTapped()
      }
      .disabled(!draft.canRequestAction)
      Button(AndroidDevicesText.closeButton) {
        self.model.closeTapped()
      }
      .keyboardShortcut(.cancelAction)
      .disabled(!draft.canClose)
    }
  }

  @ViewBuilder
  private func list(_ draft: AndroidInstalledAppsDraft) -> some View {
    switch draft.packages {
    case .loading:
      ProgressView {
        Text(AndroidDevicesText.readingApps)
      }
      .frame(maxWidth: .infinity)
    case let .failed(error):
      VStack(alignment: .leading, spacing: 8) {
        Label {
          VStack(alignment: .leading, spacing: 4) {
            Text(AndroidDevicesText.appsReadFailed)
              .fontWeight(.semibold)
            Text(AndroidDevicesText.testConditionsFailure(error))
              .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        Button(AndroidDevicesText.rereadButton) {
          Task { await self.model.refreshTapped() }
        }
        .disabled(!draft.canRefresh)
      }
    case let .loaded(packages) where packages.isEmpty, let .reloading(packages) where packages.isEmpty:
      // 빈 목록을 다시 읽는 동안에도(마지막 앱을 지운 뒤의 다시 읽기 등) 안내를 그대로 보인다.
      Text(AndroidDevicesText.noInstalledAppsForConditions)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    case let .loaded(packages), let .reloading(packages):
      // 앱이 많을 수 있어 스크롤되는 목록으로 보인다. 다시 읽는 동안에도 마지막 목록과 선택을 그대로 보인다.
      // 선택은 `Binding(get:set:)` 으로 Model 의 이벤트에 잇고, 삭제하는 동안은 목록을 끈다.
      List(packages, id: \.self, selection: Binding(
        get: { draft.selection },
        set: { self.model.selectionChanged($0) }
      )) { package in
        Text(verbatim: package.rawValue)
      }
      .disabled(draft.isBusy)
      .accessibilityLabel(AndroidDevicesText.packagePicker)
    }
  }

  /// 진행 줄(삭제 중) 또는 마지막 결과 줄.
  @ViewBuilder
  private func status(_ draft: AndroidInstalledAppsDraft) -> some View {
    if let action = draft.runningAction {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(AndroidDevicesText.removingApp(action.package.rawValue))
          .foregroundStyle(.secondary)
      }
    } else if let message = draft.message {
      Label {
        Text(AndroidDevicesText.installedAppsMessage(message))
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        switch message {
        case .removed:
          Image(systemName: "checkmark.circle")
        case .failed:
          Image(systemName: "exclamationmark.triangle")
        }
      }
    }
  }
}
