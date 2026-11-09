import AppLogInterface
import Core
import SwiftUI

/// "지금 필터 저장…" 시트: 이름 입력, 막힘 이유·50개 안내, 같은 이름이면 바꿀지 묻는 확인.
/// 입력은 모두 Model 의 이벤트 메서드로 넘기고, Binding 의 get 은 body 에서 잡은 값이 아니라 Model 을 다시 읽는다.
/// 모든 이벤트 메서드에 가드가 있어, SwiftUI 가 닫힌 뒤 set(false) 를 다시 불러도 두 번 처리하지 않는다.
struct LogFilterSaveSheet: View {
  let model: DeviceLogModel
  let target: AppLogTarget

  var body: some View {
    let draft = self.model.window(for: self.target).saveDraft
    let block = self.model.saveBlock(for: self.target)
    let isOverLimit = self.model.isSaveOverLimit(for: self.target)
    let isSaveDisabled = draft?.nameProblem != nil || block != nil || isOverLimit
    VStack(alignment: .leading, spacing: 10) {
      Text(DeviceLogText.saveSheetTitle)
        .font(.headline)
      TextField(
        DeviceLogText.saveNameLabel,
        text: Binding(
          get: { self.model.window(for: self.target).saveDraft?.name ?? "" },
          set: { self.model.saveNameChanged($0, in: self.target) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 320)
      if draft?.nameProblem == .nameTooLong {
        self.notice(DeviceLogText.nameTooLong)
      }
      if let block {
        self.notice(DeviceLogText.saveBlocked(block))
      }
      if isOverLimit {
        self.notice(DeviceLogText.savedFilterLimit)
      }
      HStack {
        Spacer()
        Button(DeviceLogText.cancelButton) {
          self.model.saveCancelled(in: self.target)
        }
        .keyboardShortcut(.cancelAction)
        Button(DeviceLogText.saveButton) {
          self.model.saveConfirmed(in: self.target)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSaveDisabled)
      }
    }
    .padding()
    .alert(
      DeviceLogText.replaceTitle(existingName: Self.existingName(draft) ?? ""),
      isPresented: Binding(
        get: { Self.existingName(self.model.window(for: self.target).saveDraft) != nil },
        set: { isPresented in
          if !isPresented {
            self.model.replaceCancelled(in: self.target)
          }
        }
      )
    ) {
      Button(DeviceLogText.replaceButton) {
        self.model.replaceConfirmed(in: self.target)
      }
      Button(DeviceLogText.cancelButton, role: .cancel) {
        self.model.replaceCancelled(in: self.target)
      }
    } message: {
      Text(DeviceLogText.replaceMessage)
    }
  }

  private func notice(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.red)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// 같은 이름 확인 중이면 저장된 표기.
  private static func existingName(_ draft: LogFilterSaveDraft?) -> String? {
    guard case let .confirmingReplace(existingName) = draft?.step else { return nil }
    return existingName
  }
}
