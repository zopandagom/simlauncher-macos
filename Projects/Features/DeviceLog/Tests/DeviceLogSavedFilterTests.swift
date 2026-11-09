import AppLogInterface
import AppLogTesting
import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import DeviceLogFeature

/// 저장된 필터: 불러오기, "지금 필터 저장…" 시트와 같은 이름 확인, 삭제, 잠금·50개·바깥 변경.
@MainActor
struct DeviceLogSavedFilterTests {
  typealias Support = DeviceLogTestSupport

  /// 조건 하나: 맞추는 방법·글자·제외.
  struct Spec {
    let kind: LogFilter.Kind
    let text: String
    let isExcluded: Bool

    init(_ kind: LogFilter.Kind, _ text: String, _ isExcluded: Bool = false) {
      self.kind = kind
      self.text = text
      self.isExcluded = isExcluded
    }
  }

  private static let errors = Self.saved("Errors", "error")

  /// 포함 조건 하나로 저장한 필터.
  private static func saved(_ name: String, _ text: String) -> SavedLogFilter {
    SavedLogFilter(
      name: name,
      conditions: [.init(kind: .contains, text: text, isExcluded: false)],
      isCaseSensitive: false
    )!
  }

  /// f0 … f(n-1).
  private static func savedFilters(_ count: Int) -> [SavedLogFilter] {
    (0 ..< count).map { Self.saved("f\($0)", "x") }
  }

  /// 세션 없이 창을 연 Model.
  private func open(_ preferences: PreferencesClientFake) -> DeviceLogModel {
    let (model, _) = Support.fixture([], preferences: preferences)
    model.windowAppeared(Support.target)
    return model
  }

  /// 창 필터를 이 조건들로 채운다 (Model 의 이벤트 메서드로).
  private func setConditions(
    _ specs: [Spec],
    caseSensitive: Bool = false,
    in model: DeviceLogModel,
    target: AppLogTarget = Support.target
  ) throws {
    for (offset, spec) in specs.enumerated() {
      if offset > 0 {
        model.conditionAdded(in: target)
      }
      let id = try #require(model.window(for: target).filter.conditions.last).id
      model.conditionKindChanged(id, spec.kind, in: target)
      model.conditionTextChanged(id, spec.text, in: target)
      model.conditionExclusionChanged(id, spec.isExcluded, in: target)
    }
    model.caseSensitivityChanged(caseSensitive, in: target)
  }

  /// 저장 시트를 열고 이름을 넣어 "저장" 을 누른다.
  private func save(_ name: String, in model: DeviceLogModel, target: AppLogTarget = Support.target) {
    model.saveFilterTapped(in: target)
    model.saveNameChanged(name, in: target)
    model.saveConfirmed(in: target)
  }

  /// 목록 읽기를 뺀 호출 (저장·삭제).
  private func writes(_ preferences: PreferencesClientFake) -> [PreferencesClientFake.Call] {
    preferences.calls.filter { $0 != .savedLogFilters }
  }

  private func draft(_ model: DeviceLogModel, target: AppLogTarget = Support.target) -> LogFilterSaveDraft? {
    model.window(for: target).saveDraft
  }

  // MARK: - 읽기·불러오기

  @Test("창을 열면 저장된 필터 목록을 읽는다")
  func readsOnOpen() {
    let preferences = PreferencesClientFake(logFilters: [.sampleErrors, nil, .sampleHTTP])
    let (model, _) = Support.fixture([], preferences: preferences)
    #expect(model.savedFilters == .empty)
    model.windowAppeared(Support.target)
    #expect(model.savedFilters == SavedLogFilterSetting(filters: [.sampleErrors, .sampleHTTP], isLocked: false))
    #expect(preferences.calls.contains(.savedLogFilters))
  }

  @Test("저장된 필터를 고르면 그 창 필터가 통째로 바뀌고 다시 거른다 (다른 창 필터는 그대로)")
  func selectReplacesFilter() async throws {
    let session = Support.summary()
    let other = Support.summary(target: Support.otherTarget)
    let preferences = PreferencesClientFake(logFilters: [.sampleErrors])
    let (model, fake) = Support.fixture([session, other], preferences: preferences)
    fake.append(["error a", "ok", "ERROR b"], to: session.id)
    fake.append(["error x", "y"], to: other.id)
    await Support.openAndWait(model, expecting: session.id, visible: 3)
    await Support.openAndWait(model, expecting: other.id, visible: 2, target: Support.otherTarget)
    try self.setConditions([Spec(.contains, "ok"), Spec(.contains, "b", true)], in: model)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }

    model.savedFilterSelected(.sampleErrors, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    let window = model.window(for: Support.target)
    #expect(Support.texts(window.visibleLines) == ["error a", "ERROR b"])
    #expect(window.filter.savedConditions() == SavedLogFilter.sampleErrors.conditions)
    #expect(window.filter.isCaseSensitive == SavedLogFilter.sampleErrors.isCaseSensitive)
    #expect(window.filterProblem == nil)
    let otherWindow = model.window(for: Support.otherTarget)
    #expect(otherWindow.filter.savedConditions().isEmpty)
    #expect(otherWindow.visibleCount == 2)
  }

  @Test("읽을 수 없는 정규식을 불러오면 그 조건에 문제를 세우고 보이는 줄은 앞 결과 그대로")
  func selectInvalidRegex() async throws {
    let session = Support.summary()
    let preferences = PreferencesClientFake(logFilters: [.sampleErrors, .sampleInvalidRegex])
    let (model, fake) = Support.fixture([session], preferences: preferences)
    fake.append(["error a", "ok"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 2)
    model.savedFilterSelected(.sampleErrors, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }

    model.savedFilterSelected(.sampleInvalidRegex, in: Support.target)
    let window = model.window(for: Support.target)
    let condition = try #require(window.filter.conditions.first)
    #expect(window.filter.savedConditions() == SavedLogFilter.sampleInvalidRegex.conditions)
    #expect(window.filterProblem == .invalidRegex(conditionID: condition.id))
    #expect(model.saveBlock(for: Support.target) == .invalidRegex)
    await Support.settle()
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["error a"])
  }

  // MARK: - 저장 시트

  @Test("저장할 수 있으면 지금 필터 저장이 빈 이름 시트를 연다")
  func saveOpensSheet() throws {
    let preferences = PreferencesClientFake(logFilters: [])
    let model = self.open(preferences)
    try self.setConditions([Spec(.contains, "error")], in: model)
    #expect(model.saveBlock(for: Support.target) == nil)
    model.saveFilterTapped(in: Support.target)
    let draft = try #require(self.draft(model))
    #expect(draft.name.isEmpty)
    #expect(draft.step == .naming)
    #expect(self.writes(preferences).isEmpty)
  }

  @Test("막힌 필터(빈 필터·정규식 오류·잠김)에서는 시트를 열지 않는다", arguments: [
    LogFilterSaveBlock.emptyFilter, .invalidRegex, .locked,
  ])
  func blockedDoesNotOpen(block: LogFilterSaveBlock) throws {
    let preferences = PreferencesClientFake(logFilters: [Self.errors], logFiltersLocked: block == .locked)
    let model = self.open(preferences)
    switch block {
    case .invalidRegex: try self.setConditions([Spec(.regex, "(")], in: model)
    case .locked: try self.setConditions([Spec(.contains, "error")], in: model)
    default: break
    }
    model.saveFilterTapped(in: Support.target)
    #expect(self.draft(model) == nil)
    #expect(model.saveBlock(for: Support.target) == block)
    #expect(self.writes(preferences).isEmpty)
  }

  @Test("50개여도 시트는 열리고, 새 이름이면 저장을 부르지 않고, 같은 이름이면 바꿀지 묻고 바꾸기로 덮어쓴다")
  func fullListOnlyReplaces() throws {
    let preferences = PreferencesClientFake(logFilters: Self.savedFilters(SavedLogFilter.maxCount))
    let model = self.open(preferences)
    try self.setConditions([Spec(.contains, "error")], in: model)
    model.saveFilterTapped(in: Support.target)
    #expect(self.draft(model) != nil)

    model.saveNameChanged("new", in: Support.target)
    #expect(model.isSaveOverLimit(for: Support.target))
    model.saveConfirmed(in: Support.target)
    #expect(self.writes(preferences).isEmpty)
    #expect(self.draft(model)?.step == .naming)

    model.saveNameChanged("F3", in: Support.target)
    #expect(!model.isSaveOverLimit(for: Support.target))
    model.saveConfirmed(in: Support.target)
    #expect(self.draft(model)?.step == .confirmingReplace(existingName: "f3"))
    model.replaceConfirmed(in: Support.target)
    #expect(self.draft(model) == nil)
    #expect(self.writes(preferences) == [
      .saveLogFilter("F3", replacingSameName: false), .saveLogFilter("F3", replacingSameName: true),
    ])
    let filters = model.savedFilters.filters
    #expect(filters.count == SavedLogFilter.maxCount)
    #expect(filters[3] == Self.saved("F3", "error"))
    #expect(preferences.storedLogFilters.compactMap(\.self) == filters)
  }

  @Test("이름을 넣고 저장하면 빈 조건을 뺀 필터를 잘라 낸 이름으로 저장하고 시트를 닫는다")
  func saveTrimsNameAndDropsEmptyConditions() throws {
    let preferences = PreferencesClientFake(logFilters: [Self.errors])
    let model = self.open(preferences)
    try self.setConditions(
      [Spec(.contains, "error"), Spec(.contains, ""), Spec(.prefix, "app", true)], caseSensitive: true, in: model
    )
    self.save("  내 필터 \n", in: model)
    let expected = try #require(SavedLogFilter(
      name: "내 필터",
      conditions: [
        .init(kind: .contains, text: "error", isExcluded: false), .init(kind: .prefix, text: "app", isExcluded: true),
      ],
      isCaseSensitive: true
    ))
    #expect(self.draft(model) == nil)
    #expect(self.writes(preferences) == [.saveLogFilter("내 필터", replacingSameName: false)])
    #expect(preferences.storedLogFilters == [Self.errors, expected])
    #expect(model.savedFilters.filters == [Self.errors, expected])
    // 저장한 창 필터는 그대로다 (빈 조건도 입력란으로 남는다).
    #expect(model.window(for: Support.target).filter.conditions.count == 3)
  }

  @Test("빈 이름·41자 이름은 저장을 부르지 않는다")
  func invalidNamesDoNotSave() throws {
    let preferences = PreferencesClientFake(logFilters: [])
    let model = self.open(preferences)
    try self.setConditions([Spec(.contains, "error")], in: model)
    model.saveFilterTapped(in: Support.target)
    let tooLong = String(repeating: "가", count: SavedLogFilter.maxNameLength + 1)
    for name in ["", "   ", tooLong] {
      model.saveNameChanged(name, in: Support.target)
      model.saveConfirmed(in: Support.target)
      #expect(self.draft(model)?.step == .naming, "\(name)")
    }
    #expect(self.draft(model)?.nameProblem == .nameTooLong)
    model.saveNameChanged("   ", in: Support.target)
    #expect(self.draft(model)?.nameProblem == .emptyName)
    #expect(self.writes(preferences).isEmpty)
  }
}

extension DeviceLogSavedFilterTests {
  // MARK: - 같은 이름

  /// "Errors" 와 HTTP 가 저장된 창에서 "fatal" 필터를 "errors" 로 저장해 바꿀지 묻는 데까지.
  private func confirmingReplace() throws -> (DeviceLogModel, PreferencesClientFake) {
    let preferences = PreferencesClientFake(logFilters: [Self.errors, .sampleHTTP])
    let model = self.open(preferences)
    try self.setConditions([Spec(.contains, "fatal")], in: model)
    self.save("errors", in: model)
    return (model, preferences)
  }

  @Test("같은 이름이면 저장된 표기로 바꿀지 묻고, 바꾸기를 누르면 같은 자리를 새 입력 이름 표기·지금 필터로 덮어쓴다")
  func sameNameAsksAndReplaces() throws {
    let (model, preferences) = try self.confirmingReplace()
    #expect(self.draft(model)?.step == .confirmingReplace(existingName: "Errors"))
    #expect(self.draft(model)?.name == "errors")
    #expect(preferences.storedLogFilters == [Self.errors, .sampleHTTP])

    model.replaceConfirmed(in: Support.target)
    #expect(self.draft(model) == nil)
    #expect(self.writes(preferences) == [
      .saveLogFilter("errors", replacingSameName: false), .saveLogFilter("errors", replacingSameName: true),
    ])
    #expect(preferences.storedLogFilters == [Self.saved("errors", "fatal"), .sampleHTTP])
    #expect(model.savedFilters.filters == [Self.saved("errors", "fatal"), .sampleHTTP])
  }

  @Test("바꾸기를 취소하면 이름을 둔 채 이름 입력으로 돌아가고 저장하지 않는다")
  func replaceCancelKeepsName() throws {
    let (model, preferences) = try self.confirmingReplace()
    model.replaceCancelled(in: Support.target)
    #expect(self.draft(model)?.step == .naming)
    #expect(self.draft(model)?.name == "errors")
    #expect(self.writes(preferences) == [.saveLogFilter("errors", replacingSameName: false)])
    #expect(preferences.storedLogFilters == [Self.errors, .sampleHTTP])
    // 이름 입력 중에는 "바꾸기" 가 아무것도 하지 않는다 (확인 창이 닫힐 때 다시 불려도 무해).
    model.replaceConfirmed(in: Support.target)
    model.replaceCancelled(in: Support.target)
    #expect(self.writes(preferences).count == 1)
    #expect(self.draft(model)?.step == .naming)
  }

  @Test("확인 중 바깥에서 그 이름이 지워졌으면 바꾸기가 끝에 붙인다")
  func replaceAfterExternalRemovalAppends() throws {
    let (model, preferences) = try self.confirmingReplace()
    preferences.setStoredLogFilters([.sampleHTTP], isLocked: false)
    model.replaceConfirmed(in: Support.target)
    #expect(self.draft(model) == nil)
    #expect(preferences.storedLogFilters == [.sampleHTTP, Self.saved("errors", "fatal")])
    #expect(model.savedFilters.filters == [.sampleHTTP, Self.saved("errors", "fatal")])
  }

  @Test("확인 중 바깥에서 잠기면 이름 입력으로 돌아가 잠금으로 막힌다")
  func replaceAfterExternalLock() throws {
    let (model, preferences) = try self.confirmingReplace()
    preferences.setStoredLogFilters(preferences.storedLogFilters, isLocked: true)
    model.replaceConfirmed(in: Support.target)
    #expect(self.draft(model)?.step == .naming)
    #expect(model.savedFilters.isLocked)
    #expect(model.saveBlock(for: Support.target) == .locked)
    #expect(preferences.storedLogFilters == [Self.errors, .sampleHTTP])
  }

  @Test("시트를 연 뒤 바깥에서 50개가 되면 저장이 limitReached 로 막히고 시트가 남는다")
  func externalFullListBlocksSave() throws {
    // 이름 입력 중: "저장" 이 목록을 다시 읽어 50개를 보고 부르지 않는다.
    let preferences = PreferencesClientFake(logFilters: [])
    let model = self.open(preferences)
    try self.setConditions([Spec(.contains, "error")], in: model)
    model.saveFilterTapped(in: Support.target)
    model.saveNameChanged("new", in: Support.target)
    preferences.setStoredLogFilters(Self.savedFilters(SavedLogFilter.maxCount), isLocked: false)
    model.saveConfirmed(in: Support.target)
    #expect(self.draft(model)?.step == .naming)
    #expect(model.isSaveOverLimit(for: Support.target))
    #expect(self.writes(preferences).isEmpty)

    // 같은 이름 확인 중: 그 이름이 빠지고 50개가 되면 Client 가 limitReached 로 거절한다.
    let (replacing, replacingPreferences) = try self.confirmingReplace()
    replacingPreferences.setStoredLogFilters(Self.savedFilters(SavedLogFilter.maxCount), isLocked: false)
    replacing.replaceConfirmed(in: Support.target)
    #expect(self.draft(replacing)?.step == .naming)
    #expect(replacing.isSaveOverLimit(for: Support.target))
    #expect(replacing.savedFilters.filters.count == SavedLogFilter.maxCount)
    #expect(replacingPreferences.storedLogFilters.count == SavedLogFilter.maxCount)
  }

  @Test("시트를 취소하거나 창을 닫으면 저장하지 않고 시트 상태를 버린다")
  func cancelAndCloseDiscardDraft() throws {
    let preferences = PreferencesClientFake(logFilters: [])
    let model = self.open(preferences)
    try self.setConditions([Spec(.contains, "error")], in: model)
    model.saveFilterTapped(in: Support.target)
    model.saveNameChanged("a", in: Support.target)
    model.saveCancelled(in: Support.target)
    #expect(self.draft(model) == nil)

    model.saveFilterTapped(in: Support.target)
    model.saveNameChanged("b", in: Support.target)
    model.windowDisappeared(Support.target)
    #expect(self.draft(model) == nil)
    model.windowAppeared(Support.target)
    #expect(self.draft(model) == nil)
    #expect(self.writes(preferences).isEmpty)
  }

  // MARK: - 삭제·공용 목록

  @Test("삭제하면 목록에서 빠지고, 잠겼으면 삭제를 부르지 않으며, 바깥에서 잠긴 뒤 삭제는 다시 읽어 잠금으로 보인다")
  func delete() {
    let preferences = PreferencesClientFake(logFilters: [Self.errors, .sampleHTTP])
    let model = self.open(preferences)
    model.savedFilterDeleteTapped("ERRORS")
    #expect(model.savedFilters.filters == [.sampleHTTP])
    #expect(preferences.storedLogFilters == [.sampleHTTP])
    #expect(self.writes(preferences) == [.removeLogFilter("ERRORS")])

    preferences.setStoredLogFilters([.sampleHTTP], isLocked: true)
    #expect(!model.savedFilters.isLocked)
    model.savedFilterDeleteTapped(SavedLogFilter.sampleHTTP.name)
    #expect(model.savedFilters == SavedLogFilterSetting(filters: [.sampleHTTP], isLocked: true))
    #expect(preferences.storedLogFilters == [.sampleHTTP])
    let count = self.writes(preferences).count
    model.savedFilterDeleteTapped(SavedLogFilter.sampleHTTP.name)
    #expect(self.writes(preferences).count == count)

    let lockedPreferences = PreferencesClientFake(logFilters: [Self.errors], logFiltersLocked: true)
    let lockedModel = self.open(lockedPreferences)
    lockedModel.savedFilterDeleteTapped(Self.errors.name)
    #expect(self.writes(lockedPreferences).isEmpty)
    #expect(lockedPreferences.storedLogFilters == [Self.errors])
  }

  @Test("한 창에서 저장하면 모든 창이 같은 목록을 본다")
  func listIsShared() throws {
    let preferences = PreferencesClientFake(logFilters: [])
    let model = self.open(preferences)
    model.windowAppeared(Support.otherTarget)
    try self.setConditions([Spec(.contains, "error")], in: model)
    self.save("Errors", in: model)
    #expect(model.savedFilters.filters == [Self.saved("Errors", "error")])
    // 다른 창은 저장된 필터를 불러올 수 있고 자기 필터는 그대로다.
    #expect(model.window(for: Support.otherTarget).filter.savedConditions().isEmpty)
    let shared = try #require(model.savedFilters.filters.first)
    model.savedFilterSelected(shared, in: Support.otherTarget)
    #expect(model.window(for: Support.otherTarget).filter.savedConditions() == shared.conditions)
  }
}
