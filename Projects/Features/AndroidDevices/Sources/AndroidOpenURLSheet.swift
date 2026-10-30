import Core
import SwiftUI

/// 링크 열기 시트: 링크 입력란과 그 아래 안내. 입력은 모두 Model 의 이벤트 메서드로 넘긴다 (iOS `OpenURLSheet` 와 같은 모양).
struct AndroidOpenURLSheet: View {
  let model: AndroidAppSheetsModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `openURLDraft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: AndroidOpenURLDraft?
  /// 열릴 때 입력란에 바로 칠 수 있게 포커스를 둔다 (View 일시 상태).
  @FocusState private var isLinkFocused: Bool

  var body: some View {
    Group {
      if let draft = self.model.openURLDraft ?? self.shownDraft {
        self.form(draft)
      }
    }
    .onChange(of: self.model.openURLDraft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func form(_ draft: AndroidOpenURLDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(AndroidDevicesText.openURLSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Form {
        TextField(
          AndroidDevicesText.linkField,
          text: Binding(get: { draft.text }, set: { self.model.openURLTextChanged($0) }),
          prompt: Text(AndroidDevicesText.linkPrompt)
        )
        .focused(self.$isLinkFocused)
        // 입력 중에는 덜 친 링크도 문제로 잡히므로 오류색이 아닌 안내로 보인다. 이유는 글자로 보인다.
        if let problem = draft.problem, let text = AndroidDevicesText.linkProblem(problem) {
          Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack {
        Spacer()
        Button(AndroidDevicesText.cancelButton) {
          self.model.openURLCancelTapped()
        }
        .keyboardShortcut(.cancelAction)
        Button(AndroidDevicesText.openURLConfirmButton) {
          Task { await self.model.openURLConfirmTapped() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!draft.canSubmit)
      }
    }
    .padding(20)
    .frame(minWidth: 420)
    .onAppear { self.isLinkFocused = true }
  }
}
