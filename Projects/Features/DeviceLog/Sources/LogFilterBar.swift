import AppLogInterface
import Core
import SwiftUI

/// 필터 줄: 조건마다 맞추는 방법·글자·제외·지우기, "조건 더하기", "대소문자 구분", 도움말. 입력은 모두 Model 의 이벤트 메서드로 넘긴다.
struct LogFilterBar: View {
  let model: DeviceLogModel
  let target: AppLogTarget

  var body: some View {
    let window = self.model.window(for: self.target)
    VStack(alignment: .leading, spacing: 6) {
      ForEach(window.filter.conditions) { condition in
        self.conditionRow(condition, problem: window.filterProblem)
      }
      HStack {
        Button {
          self.model.conditionAdded(in: self.target)
        } label: {
          Label(DeviceLogText.addCondition, systemImage: "plus")
        }
        Toggle(
          DeviceLogText.caseSensitiveToggle,
          isOn: Binding(
            get: { self.model.window(for: self.target).filter.isCaseSensitive },
            set: { self.model.caseSensitivityChanged($0, in: self.target) }
          )
        )
        .toggleStyle(.checkbox)
        Spacer()
      }
      Text(DeviceLogText.filterHelp(platform: self.target.platform))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func conditionRow(_ condition: LogFilter.Condition, problem: LogFilterProblem?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Picker(
          DeviceLogText.kindLabel,
          selection: Binding(
            get: { condition.kind },
            set: { self.model.conditionKindChanged(condition.id, $0, in: self.target) }
          )
        ) {
          ForEach(LogFilter.Kind.allCases, id: \.self) { kind in
            Text(DeviceLogText.kind(kind)).tag(kind)
          }
        }
        .labelsHidden()
        .fixedSize()
        TextField(
          DeviceLogText.conditionPrompt,
          text: Binding(
            get: { condition.text },
            set: { self.model.conditionTextChanged(condition.id, $0, in: self.target) }
          )
        )
        .textFieldStyle(.roundedBorder)
        .font(.body.monospaced())
        Toggle(
          DeviceLogText.excludeToggle,
          isOn: Binding(
            get: { condition.isExcluded },
            set: { self.model.conditionExclusionChanged(condition.id, $0, in: self.target) }
          )
        )
        .toggleStyle(.checkbox)
        .help(DeviceLogText.excludeHelp)
        Button {
          self.model.conditionRemoved(condition.id, in: self.target)
        } label: {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help(DeviceLogText.removeCondition)
        .accessibilityLabel(DeviceLogText.removeCondition)
      }
      if problem == .invalidRegex(conditionID: condition.id) {
        Text(DeviceLogText.invalidRegex)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }
}
