import Core
import SwiftUI

/// 새 Android 기기 만들기 시트: 이름(표시 이름, 한글 가능), 시스템 이미지, 화면 모양. 입력은 모두 Model 의 이벤트 메서드로 넘긴다.
struct AndroidDeviceCreationSheet: View {
  let model: AndroidDevicesModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `creationDraft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: AndroidDeviceCreationDraft?

  var body: some View {
    Group {
      if let draft = self.model.creationDraft ?? self.shownDraft {
        self.form(draft)
      }
    }
    .onChange(of: self.model.creationDraft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func form(_ draft: AndroidDeviceCreationDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(AndroidDevicesText.createSheetTitle)
        .font(.headline)
      Form {
        TextField(
          AndroidDevicesText.nameField,
          text: Binding(get: { draft.name }, set: { self.model.creationNameChanged($0) })
        )
        if draft.isNameEdited, let problem = draft.nameProblem {
          Text(AndroidDevicesText.nameProblem(problem))
            .font(.caption)
            .foregroundStyle(.red)
        }
        Picker(
          AndroidDevicesText.imagePicker,
          selection: Binding(get: { draft.image }, set: { self.model.creationImageChanged($0) })
        ) {
          ForEach(draft.options.images, id: \.self) { image in
            Text(AndroidDevicesText.imageOption(image)).tag(image)
          }
        }
        Picker(
          AndroidDevicesText.profilePicker,
          selection: Binding(get: { draft.profile }, set: { self.model.creationProfileChanged($0) })
        ) {
          ForEach(draft.options.profiles) { profile in
            Text(AndroidDevicesText.profileOption(profile)).tag(profile.id)
          }
        }
      }
      HStack {
        Spacer()
        Button(AndroidDevicesText.cancelButton) {
          self.model.creationCancelTapped()
        }
        .keyboardShortcut(.cancelAction)
        Button(AndroidDevicesText.createConfirmButton) {
          Task { await self.model.creationConfirmTapped() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!draft.canSubmit)
      }
    }
    .padding(20)
    .frame(minWidth: 380)
  }
}
