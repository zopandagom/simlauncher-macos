import Core
import SimulatorInterface
import SwiftUI

/// 테스트 조건 시트: 제목 → 머리 안내 → `Form` { 화면(외관·글씨 크기·고대비) · 위치(마지막으로 보낸 위치, 한 점, 경로, 시나리오,
/// 지우기) } → 마지막 적용의 실패 줄 → 닫기. 입력과 선택은 `Binding(get:set:)` 으로 Model 의 이벤트 메서드에 잇는다.
/// 그 기기에 적용 중인 명령이 있으면 모든 적용 컨트롤을 끈다. TC-B·C 는 `Form` 끝에 앱 단위 구역을 더한다.
struct TestConditionsSheet: View {
  let model: TestConditionsModel
  /// 마지막으로 그린 초안. 닫히는 동안 Model 의 `draft` 는 이미 nil 이라, 글자가 비지 않도록 View 가 들고 있는다.
  @State private var shownDraft: TestConditionsDraft?

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

  private func content(_ draft: TestConditionsDraft) -> some View {
    let isApplying = self.model.applying[draft.deviceID] != nil
    return VStack(alignment: .leading, spacing: 12) {
      Text(LauncherText.testConditionsSheetTitle(for: draft.device))
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(LauncherText.testConditionsSheetNote)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Form {
        Section(LauncherText.displaySection) {
          self.display(draft, isApplying: isApplying)
        }
        Section(LauncherText.locationSection) {
          self.location(draft, isApplying: isApplying)
        }
      }
      .formStyle(.grouped)
      .frame(minHeight: 360, maxHeight: .infinity)
      HStack(spacing: 8) {
        if isApplying {
          ProgressView()
            .controlSize(.small)
          Text(LauncherText.applyingCondition)
            .foregroundStyle(.secondary)
        } else if let message = draft.message {
          Label {
            Text(LauncherText.testConditionsMessage(message))
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "exclamationmark.triangle")
          }
        }
        Spacer()
        Button(LauncherText.closeButton) {
          self.model.closeTapped()
        }
        .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(minWidth: 520, idealWidth: 540, minHeight: 520, idealHeight: 640)
  }

  // MARK: - 화면

  @ViewBuilder
  private func display(_ draft: TestConditionsDraft, isApplying: Bool) -> some View {
    switch draft.display {
    case .loading:
      ProgressView {
        Text(LauncherText.readingConditions)
      }
      .frame(maxWidth: .infinity)
    case let .failed(error):
      VStack(alignment: .leading, spacing: 6) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(LauncherText.conditionsReadFailed)
              .fontWeight(.semibold)
            Text(LauncherText.testConditionsFailure(error))
              .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        Button(LauncherText.rereadButton) {
          Task { await self.model.displayRetryTapped() }
        }
      }
    case let .loaded(settings):
      self.appearancePicker(settings.appearance, isApplying: isApplying)
      self.contentSizePicker(settings.contentSize, isApplying: isApplying)
      self.contrastToggle(settings.increaseContrast, isApplying: isApplying)
    }
  }

  private func appearancePicker(_ reading: IOSSettingReading<DeviceAppearance>, isApplying: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Picker(LauncherText.appearanceLabel, selection: Binding<DeviceAppearance?>(
        get: { reading.value },
        set: { new in
          guard let new else { return }
          Task { await self.model.appearanceSelected(new) }
        }
      )) {
        ForEach(DeviceAppearance.allCases, id: \.self) { appearance in
          Text(LauncherText.appearanceName(appearance)).tag(Optional(appearance))
        }
      }
      .pickerStyle(.segmented)
      .disabled(isApplying || reading.value == nil)
      self.readingNote(reading)
    }
  }

  private func contentSizePicker(_ reading: IOSSettingReading<IOSContentSize>, isApplying: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Picker(LauncherText.contentSizeLabel, selection: Binding<IOSContentSize?>(
        get: { reading.value },
        set: { new in
          guard let new else { return }
          Task { await self.model.contentSizeSelected(new) }
        }
      )) {
        if reading.value == nil {
          Text(verbatim: "—").tag(IOSContentSize?.none)
        }
        ForEach(IOSContentSize.allCases, id: \.self) { size in
          Text(LauncherText.contentSizeName(size)).tag(Optional(size))
        }
      }
      .pickerStyle(.menu)
      .disabled(isApplying || reading.value == nil)
      self.readingNote(reading)
    }
  }

  private func contrastToggle(_ reading: IOSSettingReading<Bool>, isApplying: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle(LauncherText.increaseContrastLabel, isOn: Binding(
        get: { reading.value ?? false },
        set: { new in Task { await self.model.increaseContrastChanged(new) } }
      ))
      .disabled(isApplying || reading.value == nil)
      self.readingNote(reading)
    }
  }

  /// 지원 안 함·알 수 없음이면 컨트롤 아래 이유를 보인다.
  @ViewBuilder
  private func readingNote(_ reading: IOSSettingReading<some Hashable & Sendable>) -> some View {
    switch reading {
    case .value:
      EmptyView()
    case .unsupported:
      self.caption(LauncherText.settingUnsupported)
    case .unknown:
      self.caption(LauncherText.settingUnknown)
    }
  }
}

// MARK: - 위치

extension TestConditionsSheet {
  @ViewBuilder
  private func location(_ draft: TestConditionsDraft, isApplying: Bool) -> some View {
    if let sent = self.model.sentLocations[draft.deviceID] {
      VStack(alignment: .leading, spacing: 2) {
        Text(LauncherText.sentLocationLine(sent))
          .fixedSize(horizontal: false, vertical: true)
        self.caption(LauncherText.sentLocationNote)
        self.caption(LauncherText.sentLocationKeptNote)
      }
    }
    self.point(draft, isApplying: isApplying)
    self.route(draft, isApplying: isApplying)
    self.scenario(draft, isApplying: isApplying)
    VStack(alignment: .leading, spacing: 4) {
      Button(LauncherText.clearLocationButton) {
        Task { await self.model.clearLocationTapped() }
      }
      .disabled(isApplying)
      self.caption(LauncherText.clearLocationHelp)
      self.caption(LauncherText.locationPlaybackNote)
    }
  }

  private func point(_ draft: TestConditionsDraft, isApplying: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        TextField(
          LauncherText.coordinateField,
          text: Binding(get: { draft.pointText }, set: { self.model.pointTextChanged($0) }),
          prompt: Text(LauncherText.coordinatePlaceholder)
        )
        Menu(LauncherText.locationPresetsMenu) {
          ForEach(LocationPreset.allCases, id: \.self) { preset in
            Button(LauncherText.presetName(preset)) {
              self.model.locationPresetSelected(preset)
            }
          }
        }
        .fixedSize()
        Button(LauncherText.setPointButton) {
          Task { await self.model.setPointTapped() }
        }
        .disabled(isApplying || draft.pointCoordinate == nil)
      }
      if let problem = draft.pointProblem {
        self.caption(LauncherText.coordinateProblem(problem))
      }
    }
  }

  private func route(_ draft: TestConditionsDraft, isApplying: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(LauncherText.routeLabel)
      TextEditor(text: Binding(get: { draft.routeText }, set: { self.model.routeTextChanged($0) }))
        .font(.body.monospaced())
        .frame(minHeight: 64, maxHeight: 120)
        .accessibilityLabel(LauncherText.routeLabel)
      self.caption(LauncherText.routeGuide)
      if let problem = draft.routeProblem {
        self.caption(LauncherText.routeProblem(problem))
      }
      HStack {
        Picker(LauncherText.routeSpeedLabel, selection: Binding(
          get: { draft.routeSpeed },
          set: { self.model.routeSpeedChanged($0) }
        )) {
          ForEach(LocationRouteSpeed.allCases, id: \.self) { speed in
            Text(LauncherText.routeSpeedName(speed)).tag(speed)
          }
        }
        .pickerStyle(.menu)
        .fixedSize()
        Spacer()
        Button(LauncherText.startRouteButton) {
          Task { await self.model.startRouteTapped() }
        }
        .disabled(isApplying || draft.routeWaypoints == nil)
      }
    }
  }

  private func scenario(_ draft: TestConditionsDraft, isApplying: Bool) -> some View {
    HStack {
      Picker(LauncherText.scenarioLabel, selection: Binding(
        get: { draft.scenario },
        set: { self.model.scenarioChanged($0) }
      )) {
        ForEach(IOSLocationScenario.allCases, id: \.self) { scenario in
          Text(LauncherText.scenarioName(scenario)).tag(scenario)
        }
      }
      .pickerStyle(.menu)
      .fixedSize()
      Spacer()
      Button(LauncherText.runScenarioButton) {
        Task { await self.model.runScenarioTapped() }
      }
      .disabled(isApplying)
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

private extension IOSSettingReading {
  /// 읽은 값. 지원 안 함·알 수 없음이면 nil.
  var value: Value? {
    guard case let .value(value) = self else { return nil }
    return value
  }
}
