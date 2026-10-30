import Core
import SwiftUI

/// URL 에서 설치 시트: 주소 입력란과 그 아래 안내. 입력은 모두 Model 의 이벤트 메서드로 넘긴다.
/// iOS `InstallURLSheet` 와 같은 배치이고, 대상은 행 한 대라 제목에만 기기를 보인다.
struct AndroidInstallURLSheet: View {
  let model: AndroidDownloadInstallModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `urlDraft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: AndroidInstallURLDraft?
  /// 열릴 때 입력란에 바로 칠 수 있게 포커스를 둔다 (View 일시 상태).
  @FocusState private var isURLFocused: Bool

  var body: some View {
    Group {
      if let draft = self.model.urlDraft ?? self.shownDraft {
        self.form(draft)
      }
    }
    .onChange(of: self.model.urlDraft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func form(_ draft: AndroidInstallURLDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      // 기기 이름이 든 문구라 번역 키로 다시 찾지 않는다.
      Text(verbatim: AndroidDevicesText.installURLSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Form {
        TextField(
          AndroidDevicesText.downloadURLField,
          text: Binding(get: { draft.text }, set: { self.model.urlTextChanged($0) }),
          prompt: Text(AndroidDevicesText.downloadURLPrompt)
        )
        .focused(self.$isURLFocused)
        Text(AndroidDevicesText.downloadURLGuide)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        // 입력 중에는 덜 친 주소도 문제로 잡히므로 오류색이 아닌 안내로 보인다. 이유는 글자로 보인다.
        if let problem = draft.problem, let text = AndroidDevicesText.downloadURLProblem(problem) {
          Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack {
        Spacer()
        Button(AndroidDevicesText.cancelButton) {
          self.model.urlCancelTapped()
        }
        .keyboardShortcut(.cancelAction)
        Button(AndroidDevicesText.installURLConfirmButton) {
          Task { await self.model.urlInstallTapped() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!draft.canSubmit)
      }
    }
    .padding(20)
    .frame(minWidth: 420)
    .onAppear { self.isURLFocused = true }
  }
}
