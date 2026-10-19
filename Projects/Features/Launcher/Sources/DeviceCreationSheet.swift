import Core
import SwiftUI

/// 새 기기 만들기 시트: 이름, iOS 버전, 기기 종류. 입력은 모두 Model 의 이벤트 메서드로 넘긴다.
struct DeviceCreationSheet: View {
  let model: LauncherModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `createDraft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: DeviceCreationDraft?

  var body: some View {
    Group {
      if let draft = self.model.createDraft ?? self.shownDraft {
        self.form(draft)
      }
    }
    .onChange(of: self.model.createDraft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func form(_ draft: DeviceCreationDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(LauncherText.createSheetTitle)
        .font(.headline)
      Form {
        TextField(
          LauncherText.nameField,
          text: Binding(get: { draft.name }, set: { self.model.createNameChanged($0) })
        )
        if let problem = draft.nameProblem {
          Text(LauncherText.nameProblem(problem))
            .font(.caption)
            .foregroundStyle(.red)
        }
        Picker(
          LauncherText.runtimePicker,
          selection: Binding(get: { draft.runtimeID }, set: { self.model.createRuntimeChanged($0) })
        ) {
          ForEach(draft.options.runtimes) { runtime in
            Text(verbatim: runtime.name).tag(runtime.id)
          }
        }
        Picker(
          LauncherText.deviceTypePicker,
          selection: Binding(get: { draft.deviceTypeID }, set: { self.model.createDeviceTypeChanged($0) })
        ) {
          ForEach(draft.deviceTypes) { deviceType in
            Text(verbatim: deviceType.name).tag(deviceType.id)
          }
        }
      }
      HStack {
        Spacer()
        Button(LauncherText.cancelButton) {
          self.model.createCancelTapped()
        }
        .keyboardShortcut(.cancelAction)
        Button(LauncherText.createConfirmButton) {
          Task { await self.model.createConfirmTapped() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!draft.canSubmit)
      }
    }
    .padding(20)
    .frame(minWidth: 360)
  }
}
