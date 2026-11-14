import AndroidEmulatorInterface
import Core
import SwiftUI

/// Android 테스트 조건 시트: 제목 → 머리 안내 → `Form` { 화면(외관) · 위치(위치 서비스 꺼짐 안내, 마지막으로 보낸 위치, 한 점,
/// 경로·시나리오 미지원 안내) } → 마지막 적용의 실패 줄 → 닫기. 입력과 선택은 `Binding(get:set:)` 으로 Model 의 이벤트 메서드에 잇는다.
/// 그 기기에 적용 중인 명령이 있으면 모든 적용 컨트롤을 끈다. TC-B·C 는 `Form` 끝에 앱 단위 구역을 더한다.
struct AndroidTestConditionsSheet: View {
  let model: AndroidTestConditionsModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `draft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: AndroidTestConditionsDraft?

  var body: some View {
    Group {
      if let draft = self.model.draft ?? self.shownDraft {
        self.content(draft)
      }
    }
    .onChange(of: self.model.draft, initial: true) { _, new in
      if let new {
        self.shownDraft = new
      }
    }
  }

  private func content(_ draft: AndroidTestConditionsDraft) -> some View {
    let isApplying = self.model.applying[draft.deviceID] != nil
    return VStack(alignment: .leading, spacing: 12) {
      Text(AndroidDevicesText.testConditionsSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(AndroidDevicesText.testConditionsSheetNote)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Form {
        Section(AndroidDevicesText.displaySection) {
          self.display(draft, isApplying: isApplying)
        }
        Section(AndroidDevicesText.locationSection) {
          self.location(draft, isApplying: isApplying)
        }
      }
      .formStyle(.grouped)
      .frame(minHeight: 260, maxHeight: .infinity)
      HStack(spacing: 8) {
        if isApplying {
          ProgressView()
            .controlSize(.small)
          Text(AndroidDevicesText.applyingCondition)
            .foregroundStyle(.secondary)
        } else if let message = draft.message {
          Label {
            Text(AndroidDevicesText.testConditionsMessage(message))
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "exclamationmark.triangle")
          }
        }
        Spacer()
        Button(AndroidDevicesText.closeButton) {
          self.model.closeTapped()
        }
        .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(minWidth: 520, idealWidth: 540, minHeight: 420, idealHeight: 520)
  }

  // MARK: - 화면

  @ViewBuilder
  private func display(_ draft: AndroidTestConditionsDraft, isApplying: Bool) -> some View {
    switch draft.conditions {
    case .loading:
      ProgressView {
        Text(AndroidDevicesText.readingConditions)
      }
      .frame(maxWidth: .infinity)
    case let .failed(error):
      VStack(alignment: .leading, spacing: 6) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(AndroidDevicesText.conditionsReadFailed)
              .fontWeight(.semibold)
            Text(AndroidDevicesText.testConditionsFailure(error))
              .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        Button(AndroidDevicesText.rereadButton) {
          Task { await self.model.conditionsRetryTapped() }
        }
      }
    case let .loaded(conditions):
      self.appearancePicker(conditions.nightMode, isApplying: isApplying)
    }
  }

  /// 자동·예약 모드·읽지 못함이면 선택 없이 보이고, 그때도 고르면 보낸다 (쓰기 출력으로 확인한다).
  private func appearancePicker(_ reading: AndroidNightModeReading, isApplying: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Picker(AndroidDevicesText.appearanceLabel, selection: Binding<DeviceAppearance?>(
        get: { reading.appearance },
        set: { new in
          guard let new else { return }
          Task { await self.model.appearanceSelected(new) }
        }
      )) {
        ForEach(DeviceAppearance.allCases, id: \.self) { appearance in
          Text(AndroidDevicesText.appearanceName(appearance)).tag(Optional(appearance))
        }
      }
      .pickerStyle(.segmented)
      .disabled(isApplying)
      switch reading {
      case .light, .dark:
        EmptyView()
      case .other:
        self.caption(AndroidDevicesText.nightModeOtherNote)
      case .unknown:
        self.caption(AndroidDevicesText.conditionsReadFailed)
      }
    }
  }

  // MARK: - 위치

  @ViewBuilder
  private func location(_ draft: AndroidTestConditionsDraft, isApplying: Bool) -> some View {
    if draft.isLocationServiceOff {
      Label {
        Text(AndroidDevicesText.locationServiceOffNote)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "location.slash")
      }
    }
    if let sent = self.model.sentLocations[draft.deviceID] {
      VStack(alignment: .leading, spacing: 2) {
        Text(AndroidDevicesText.sentLocationLine(sent))
          .fixedSize(horizontal: false, vertical: true)
        self.caption(AndroidDevicesText.sentLocationNote)
        self.caption(AndroidDevicesText.sentLocationKeptNote)
      }
    }
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        TextField(
          AndroidDevicesText.coordinateField,
          text: Binding(get: { draft.pointText }, set: { self.model.pointTextChanged($0) }),
          prompt: Text(AndroidDevicesText.coordinatePlaceholder)
        )
        Menu(AndroidDevicesText.locationPresetsMenu) {
          ForEach(LocationPreset.allCases, id: \.self) { preset in
            Button(AndroidDevicesText.presetName(preset)) {
              self.model.locationPresetSelected(preset)
            }
          }
        }
        .fixedSize()
        Button(AndroidDevicesText.setPointButton) {
          Task { await self.model.setPointTapped() }
        }
        .disabled(isApplying || draft.pointCoordinate == nil)
      }
      if let problem = draft.pointProblem {
        self.caption(AndroidDevicesText.coordinateProblem(problem))
      }
    }
    self.caption(AndroidDevicesText.routeUnsupportedNote)
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
