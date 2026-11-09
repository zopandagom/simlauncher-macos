import AppLogInterface
import Core
import SwiftUI

/// 필터 줄: 조건마다 맞추는 방법·글자·제외·지우기, "조건 더하기", "저장된 필터" 메뉴, "대소문자 구분", 도움말.
/// 입력은 모두 Model 의 이벤트 메서드로 넘긴다.
/// "저장된 필터" 메뉴: 항목을 고르면 이 창 필터를 통째로 바꿔 불러오고, "지금 필터 저장…" 은 이름 시트(`LogFilterSaveSheet`)를,
/// "삭제" 하위 메뉴는 잠기지 않았을 때만 보인다. 목록은 Model 이 정한 때만 다시 읽어 메뉴를 펼치는 순간에는 읽지 않는다.
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
        self.savedFiltersMenu
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

  private var savedFiltersMenu: some View {
    let saved = self.model.savedFilters
    let block = self.model.saveBlock(for: self.target)
    return Menu(DeviceLogText.savedFiltersMenu) {
      if saved.filters.isEmpty {
        Text(DeviceLogText.noSavedFilters)
      } else {
        // 보이는 목록은 이름이 대소문자 무시로도 겹치지 않는다 (`SavedLogFilterList.visible`).
        ForEach(saved.filters, id: \.name) { filter in
          Button(filter.name) {
            self.model.savedFilterSelected(filter, in: self.target)
          }
        }
      }
      Divider()
      Button(DeviceLogText.saveCurrentFilter) {
        self.model.saveFilterTapped(in: self.target)
      }
      .disabled(block != nil)
      if let block {
        Text(DeviceLogText.saveBlocked(block))
      }
      if !saved.isLocked, !saved.filters.isEmpty {
        Menu(DeviceLogText.deleteMenu) {
          ForEach(saved.filters, id: \.name) { filter in
            Button(filter.name) {
              self.model.savedFilterDeleteTapped(filter.name)
            }
          }
        }
      }
    }
    .fixedSize()
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
