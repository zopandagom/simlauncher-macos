import Core
import SwiftUI

/// URL 에서 설치 시트: 주소 입력란과 그 아래 안내. 입력은 모두 Model 의 이벤트 메서드로 넘긴다.
struct InstallURLSheet: View {
  let model: LauncherModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `installURLDraft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: InstallURLDraft?
  /// 열릴 때 입력란에 바로 칠 수 있게 포커스를 둔다 (View 일시 상태).
  @FocusState private var isURLFocused: Bool

  var body: some View {
    Group {
      if let draft = self.model.installURLDraft ?? self.shownDraft {
        self.form(draft)
      }
    }
    .onChange(of: self.model.installURLDraft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func form(_ draft: InstallURLDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(LauncherText.installURLSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Form {
        TextField(
          LauncherText.downloadURLField,
          text: Binding(get: { draft.text }, set: { self.model.installURLTextChanged($0) }),
          prompt: Text(LauncherText.downloadURLPrompt)
        )
        .focused(self.$isURLFocused)
        Text(LauncherText.downloadURLGuide)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        // 입력 중에는 덜 친 주소도 문제로 잡히므로 오류색이 아닌 안내로 보인다. 이유는 글자로 보인다.
        if let problem = draft.problem, let text = LauncherText.downloadURLProblem(problem) {
          Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack {
        Spacer()
        Button(LauncherText.cancelButton) {
          self.model.installURLCancelTapped()
        }
        .keyboardShortcut(.cancelAction)
        Button(LauncherText.installURLConfirmButton) {
          Task { await self.model.installURLConfirmTapped() }
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
