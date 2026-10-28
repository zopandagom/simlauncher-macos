import Core
import SwiftUI

/// 설정 창(⌘,)의 내용: 빌드 카탈로그 목록, 주소 입력·등록, 등록 결과 줄, Android SDK 위치. 입력은 모두 Model 의 이벤트 메서드로 넘긴다.
/// Settings 씬의 View 는 앱 시작 때 한 번 만들어지고 창을 닫아도 남으므로, 열고 닫을 때마다 `onAppear`·`onDisappear` 로 알린다.
public struct SettingsView: View {
  let model: SettingsModel

  public init(model: SettingsModel) {
    self.model = model
  }

  public var body: some View {
    Form {
      Section(SettingsText.catalogSectionTitle) {
        if self.model.setting.isLocked {
          Label(SettingsText.lockedNote, systemImage: "lock.fill")
            .fixedSize(horizontal: false, vertical: true)
        }
        self.list
      }
      if self.model.canEdit {
        Section {
          self.addForm
        }
      }
      if let result = self.model.result {
        Section {
          self.resultLine(result)
        }
      }
      AndroidSDKLocationSection(model: self.model)
    }
    .formStyle(.grouped)
    .frame(minWidth: 560, maxWidth: 560, minHeight: 320)
    .onAppear { self.model.onAppear() }
    .onDisappear { self.model.windowClosed() }
  }

  @ViewBuilder
  private var list: some View {
    let entries = self.model.entries
    if entries.isEmpty {
      Text(SettingsText.emptyList)
        .foregroundStyle(.secondary)
    } else {
      // 바깥에서 같은 문자열을 두 번 넣을 수 있어 저장 문자열은 유일하지 않다. 인덱스를 id 로 쓴다.
      ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
        CatalogRow(entry: entry, canRemove: self.model.canEdit) {
          self.model.removeButtonTapped(entry.raw)
        }
      }
    }
  }

  private var addForm: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        TextField(
          SettingsText.urlField,
          text: Binding(get: { self.model.draftText }, set: { self.model.catalogURLTextChanged($0) }),
          prompt: Text(SettingsText.urlPrompt)
        )
        .disabled(self.model.checkingURL != nil)
        .onSubmit {
          Task { await self.model.addButtonTapped() }
        }
        if self.model.checkingURL != nil {
          ProgressView()
            .controlSize(.small)
          Text(SettingsText.checkingLabel)
            .foregroundStyle(.secondary)
          Button(SettingsText.cancelButton) {
            self.model.cancelCheckTapped()
          }
        } else {
          Button(SettingsText.addButton) {
            Task { await self.model.addButtonTapped() }
          }
          .disabled(!self.model.canAdd)
        }
      }
      Text(SettingsText.urlGuide)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      // 입력 중에는 덜 친 주소도 문제로 잡히므로 오류색이 아닌 안내로 보인다.
      if let problem = self.model.draftProblem, let text = SettingsText.draftProblem(problem) {
        Text(text)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func resultLine(_ result: CatalogRegistrationResult) -> some View {
    switch result {
    case let .added(_, appCount):
      Label(SettingsText.added(appCount: appCount), systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case let .failed(failure):
      Label {
        Text(SettingsText.message(for: failure))
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
    }
  }
}
