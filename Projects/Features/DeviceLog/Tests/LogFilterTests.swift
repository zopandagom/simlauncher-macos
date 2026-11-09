import AppLogInterface
import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import DeviceLogFeature

struct LogLineHeaderTests {
  @Test("DT_MODE 의 Logger 줄은 머리말 뒤 카테고리부터가 메시지다")
  func dtModeLogger() {
    let line = "2026-11-03 15:58:29.655736+0900 LogProbe[82561:42341349] [probe] logger default hello"
    #expect(line[LogLineHeader.messageStart(in: line)...] == "[probe] logger default hello")
  }

  @Test("DT_MODE 없는 NSLog 줄(시간대 없음, 밀리초)도 머리말을 뺀다")
  func plainNSLog() {
    let line = "2026-11-03 15:58:08.123 LogProbe[82449:42340721] nslog hello 1"
    #expect(line[LogLineHeader.messageStart(in: line)...] == "nslog hello 1")
  }

  @Test("프로세스 이름에 공백이 들어 있어도 머리말을 찾는다")
  func processNameWithSpaces() {
    let line = "2026-11-03 15:58:08.123 My Probe App[82449:a2f] hello"
    #expect(line[LogLineHeader.messageStart(in: line)...] == "hello")
  }

  @Test("머리말이 없으면(print 줄, 날짜로 시작하지만 형식이 다른 줄) 줄 처음이다")
  func noHeader() {
    for line in ["tick 5", "", "2026-11-03 hello", "2026-11-03 15:58:08.123 LogProbe hello", "1234"] {
      #expect(LogLineHeader.messageStart(in: line) == line.startIndex, "\(line)")
      #expect(LogLineHeader.messageOffset(in: line) == 0, "\(line)")
    }
  }

  @Test("Android logcat threadtime 줄은 레벨 뒤 태그부터가 메시지다 (pid·tid 앞 공백 수가 달라도)")
  func androidThreadtime() {
    let lines = [
      ("11-09 14:13:30.242  4750  4759 I ncher.sampleapp: Compiler allocated", "ncher.sampleapp: Compiler allocated"),
      (
        "11-09 14:14:23.672 15052 15052 E AndroidRuntime: FATAL EXCEPTION: main",
        "AndroidRuntime: FATAL EXCEPTION: main"
      ),
      ("01-02 03:04:05.006   123     7 D MyTag   : hello", "MyTag   : hello"),
    ]
    for (line, message) in lines {
      #expect(line[LogLineHeader.messageStart(in: line)...] == message, "\(line)")
    }
  }

  @Test("threadtime 처럼 보여도 형식이 다르면(버퍼 머리 줄, 레벨 없음, 밀리초가 셋이 아님) 줄 처음이다")
  func androidNotHeader() {
    for line in [
      "--------- beginning of main",
      "11-09 14:13:30.242  4750  4759 ncher.sampleapp: no level",
      "11-09 14:13:30.24  4750  4759 I tag: short millis",
    ] {
      #expect(LogLineHeader.messageOffset(in: line) == 0, "\(line)")
    }
  }

  @Test("한글이 든 줄은 UTF-16 위치로 돌려준다")
  func utf16Offset() {
    let line = "2026-11-03 15:58:08.123 앱[1:2] 안녕"
    let offset = LogLineHeader.messageOffset(in: line)
    #expect((line as NSString).substring(from: offset) == "안녕")
  }
}

struct LogFilterTests {
  /// 조건 하나: 맞추는 방법·글자·제외.
  struct Spec {
    let kind: LogFilter.Kind
    let text: String
    let isExcluded: Bool

    init(_ kind: LogFilter.Kind, _ text: String, _ isExcluded: Bool) {
      self.kind = kind
      self.text = text
      self.isExcluded = isExcluded
    }
  }

  private static let logger = "2026-11-03 15:58:29.655736+0900 LogProbe[82561:42341349] [probe] logger default hello"
  private static let nslog = "2026-11-03 15:58:08.123 LogProbe[82449:42340721] nslog hello 1"

  private func compiled(_ conditions: [Spec], caseSensitive: Bool = false) throws
    -> CompiledLogFilter
  {
    var filter = LogFilter()
    for (offset, condition) in conditions.enumerated() {
      if offset > 0 {
        filter.addCondition()
      }
      let id = try #require(filter.conditions.last).id
      filter.setKind(condition.kind, of: id)
      filter.setText(condition.text, of: id)
      filter.setExcluded(condition.isExcluded, of: id)
    }
    filter.setCaseSensitive(caseSensitive)
    return try filter.compiled().get()
  }

  /// 줄 하나를 거르기(메인 밖 진입점)에 넣은 결과. 숨으면 nil.
  private func visible(_ filter: CompiledLogFilter, _ text: String) async -> VisibleLogLine? {
    await CompiledLogFilter.filtered([AppLogLine(index: 0, text: text)], by: filter).first
  }

  private func shows(_ filter: CompiledLogFilter, _ text: String) async -> Bool {
    await self.visible(filter, text) != nil
  }

  /// 강조한 글자들 (앞에서부터).
  private func highlighted(_ filter: CompiledLogFilter, _ text: String) async -> [String]? {
    await self.visible(filter, text)?.highlights.map { (text as NSString).substring(with: $0.nsRange) }
  }

  @Test("새 필터는 빈 포함 조건 하나이고, 모든 줄을 보인다")
  func emptyFilter() async throws {
    let filter = LogFilter()
    #expect(filter.conditions.count == 1)
    #expect(filter.conditions.first?.text.isEmpty == true)
    let compiled = try filter.compiled().get()
    #expect(compiled.isEmpty)
    #expect(await self.shows(compiled, "anything"))
    #expect(await self.visible(compiled, "anything")?.highlights == [])
  }

  @Test("포함은 기본으로 대소문자를 무시하고, 구분을 켜면 다르다")
  func containsCase() async throws {
    let insensitive = try self.compiled([Spec(.contains, "TICK", false)])
    #expect(await self.shows(insensitive, "tick 5"))
    let sensitive = try self.compiled([Spec(.contains, "TICK", false)], caseSensitive: true)
    #expect(await !self.shows(sensitive, "tick 5"))
    #expect(await self.shows(sensitive, "TICK 5"))
  }

  @Test("포함은 정규식 특수 문자를 글자 그대로 찾는다")
  func containsSpecialCharacters() async throws {
    let filter = try self.compiled([Spec(.contains, "[probe]", false)])
    #expect(await self.shows(filter, Self.logger))
    #expect(await !self.shows(filter, "p"))
    #expect(try await self.shows(self.compiled([Spec(.contains, "a.c", false)]), "xa.cx"))
    #expect(try await !self.shows(self.compiled([Spec(.contains, "a.c", false)]), "abc"))
  }

  @Test("시작은 머리말 뒤 메시지와 비교한다 (DT 형식·DT 없는 NSLog·공백 든 프로세스 이름·머리말 없음)")
  func prefixAfterHeader() async throws {
    let probe = try self.compiled([Spec(.prefix, "[probe]", false)])
    #expect(await self.shows(probe, Self.logger))
    #expect(await !self.shows(probe, Self.nslog))
    #expect(try await self.shows(self.compiled([Spec(.prefix, "nslog", false)]), Self.nslog))
    #expect(try await self.shows(
      self.compiled([Spec(.prefix, "hello", false)]),
      "2026-11-03 15:58:08.123 My App[1:2] hello there"
    ))
    let tick = try self.compiled([Spec(.prefix, "tick", false)])
    #expect(await self.shows(tick, "tick 5"))
    #expect(await !self.shows(tick, "a tick 5"))
    // 머리말의 날짜로 시작하지 않는다.
    #expect(try await !self.shows(self.compiled([Spec(.prefix, "2026", false)]), Self.logger))
  }

  @Test("정규식은 줄 전체에서 맞춘다")
  func regex() async throws {
    let filter = try self.compiled([Spec(.regex, #"tick \d*5$"#, false)])
    #expect(await self.shows(filter, "tick 5"))
    #expect(await self.shows(filter, "tick 15"))
    #expect(await !self.shows(filter, "tick 51"))
    #expect(try await self.shows(self.compiled([Spec(.regex, "^2026.*hello$", false)]), Self.logger))
  }

  @Test("포함 조건은 하나라도 맞으면 보이고(OR), 제외 조건이 맞으면 숨긴다")
  func orAndExclude() async throws {
    let filter = try self.compiled([
      Spec(.contains, "tick", false),
      Spec(.contains, "probe", false),
      Spec(.contains, "5", true),
    ])
    #expect(await self.shows(filter, "tick 1"))
    #expect(await self.shows(filter, "probe start"))
    #expect(await !self.shows(filter, "tick 5"))
    #expect(await !self.shows(filter, "other"))
    let excludeOnly = try self.compiled([Spec(.contains, "General", true)])
    #expect(await self.shows(excludeOnly, "tick 1"))
    #expect(await !self.shows(excludeOnly, "[General] Failed"))
  }

  @Test("빈 조건은 뺀다 (제외도)")
  func emptyConditionsIgnored() async throws {
    let filter = try self.compiled([
      Spec(.contains, "", false),
      Spec(.contains, "", true),
      Spec(.contains, "tick", false),
    ])
    #expect(await self.shows(filter, "tick 1"))
    #expect(await !self.shows(filter, "other"))
  }

  @Test("잘못된 정규식은 그 조건의 문제다")
  func invalidRegex() async throws {
    var filter = LogFilter()
    let id = try #require(filter.conditions.first).id
    filter.setKind(.regex, of: id)
    filter.setText("(", of: id)
    #expect(throws: LogFilterProblem.invalidRegex(conditionID: id)) { try filter.compiled().get() }
    // 포함이면 같은 글자도 문제가 아니다.
    filter.setKind(.contains, of: id)
    #expect(try await self.shows(filter.compiled().get(), "a (b"))
  }

  @Test("강조는 제외가 아닌 모든 조건(포함·시작·정규식)의 맞은 곳이고, 제외 조건은 강조하지 않는다 (맞으면 숨긴다)")
  func highlights() async throws {
    let filter = try self.compiled([
      Spec(.contains, "hello", false), Spec(.prefix, "[probe]", false), Spec(.regex, "log+er", false),
      Spec(.contains, "default", true), Spec(.contains, "probe", true),
    ])
    // 두 번째 제외(`probe`)가 맞아 숨는다.
    #expect(await self.visible(filter, Self.logger) == nil)
    let kept = try self.compiled([
      Spec(.contains, "hello", false), Spec(.prefix, "[probe]", false), Spec(.regex, "log+er", false),
      Spec(.contains, "error", true),
    ])
    #expect(await self.highlighted(kept, Self.logger) == ["[probe]", "logger", "hello"])
    let repeated = try self.compiled([Spec(.contains, "ab", false)])
    #expect(await self.visible(repeated, "ab ab")?.highlights.count == 2)
  }

  @Test("빈 범위로 맞는 정규식은 강조하지 않는다")
  func emptyMatchNotHighlighted() async throws {
    let filter = try self.compiled([Spec(.regex, "x*", false)])
    #expect(await self.shows(filter, "abc"))
    #expect(await self.visible(filter, "abc")?.highlights == [])
  }

  @Test("한 조건에서 붙은 맞은 곳은 한 곳으로 합친다")
  func adjacentMatchesMerged() async throws {
    let filter = try self.compiled([Spec(.regex, ".", false)])
    #expect(await self.visible(filter, "hello")?.highlights == [LogHighlight(location: 0, length: 5)])
  }

  @Test("조건끼리 겹친 강조는 합친다")
  func overlappingConditionsMerged() async throws {
    let filter = try self.compiled([Spec(.contains, "abc", false), Spec(.regex, "bcd", false)])
    #expect(await self.highlighted(filter, "abcde") == ["abcd"])
  }

  @Test("한 줄의 강조는 앞 64곳까지다")
  func highlightLimit() async throws {
    let filter = try self.compiled([Spec(.contains, "a", false)])
    let highlights = try #require(await self.visible(filter, String(repeating: "a ", count: 100))?.highlights)
    #expect(highlights.count == CompiledLogFilter.highlightLimit)
    #expect(highlights.first == LogHighlight(location: 0, length: 1))
    #expect(highlights.last == LogHighlight(location: 126, length: 1))
  }

  @Test("조건 하나의 맞춤은 1024번까지 본다 (줄은 보이고, 강조는 앞 1024글자)")
  func matchLimit() async throws {
    let filter = try self.compiled([Spec(.regex, "a", false)])
    let line = try #require(await self.visible(filter, String(repeating: "a", count: 3000)))
    #expect(line.highlights == [LogHighlight(location: 0, length: Int32(CompiledLogFilter.matchLimit))])
  }

  @Test("강조 위치는 UTF-16 단위다 (한글·이모지 뒤)")
  func utf16Highlight() async throws {
    let filter = try self.compiled([Spec(.contains, "tick", false)])
    let text = "안녕 👋 tick"
    #expect(await self.visible(filter, text)?.highlights == [LogHighlight(location: 6, length: 4)])
    #expect(await self.highlighted(filter, text) == ["tick"])
  }

  @Test("시작 조건의 강조는 머리말 뒤 한 곳이다")
  func prefixHighlight() async throws {
    let filter = try self.compiled([Spec(.prefix, "nslog", false)])
    let line = "2026-11-03 15:58:08.123 LogProbe[82449:42340721] nslog nslog"
    let highlights = try #require(await self.visible(filter, line)?.highlights)
    #expect(highlights == [LogHighlight(location: Int32(LogLineHeader.messageOffset(in: line)), length: 5)])
  }

  @Test("취소하면 느린 줄 안에서도 돌아온다")
  func cancelInsideSlowLine() async throws {
    // `(a+)+$` 는 `a` × 28 + `b` 에서 취소 없이 약 9초 걸린다 (2026-11-04 실측, `-O`). 유한 길이라 취소가 듣지 않아도 끝난다.
    let filter = try self.compiled([Spec(.regex, "(a+)+$", false)])
    let lines = [AppLogLine(index: 0, text: String(repeating: "a", count: 28) + "b")]
    let started = ContinuousClock.now
    let task = Task { await CompiledLogFilter.filtered(lines, by: filter) }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    let result = await task.value
    #expect(result.isEmpty)
    #expect(ContinuousClock.now - started < .seconds(5))
  }

  @Test("거르기는 순서를 지키고, 필터가 없으면 그대로다")
  func filteredKeepsOrder() async throws {
    let lines = (0 ..< 3000).map { AppLogLine(index: $0, text: "tick \($0)") }
    let filter = try self.compiled([Spec(.regex, #"5$"#, false)])
    let result = await CompiledLogFilter.filtered(lines, by: filter)
    #expect(result.count == 300)
    #expect(result.map(\.index) == result.map(\.index).sorted())
    let unfiltered = await CompiledLogFilter.filtered(lines, by: nil)
    #expect(unfiltered.map(\.line) == lines)
    #expect(unfiltered.map(\.highlights) == Array(repeating: [], count: lines.count))
  }

  @Test("마지막 조건을 지우면 빈 조건 하나가 남는다")
  func removeLastCondition() throws {
    var filter = LogFilter()
    let id = try #require(filter.conditions.first).id
    filter.setText("tick", of: id)
    filter.removeCondition(id)
    #expect(filter.conditions.count == 1)
    #expect(filter.conditions.first?.text.isEmpty == true)
    #expect(filter.conditions.first?.id != id)
  }
}

/// Android logcat 줄의 필터 (`LogLineHeader` 의 threadtime 머리말).
extension LogFilterTests {
  @Test("Android logcat 줄의 시작 조건은 태그부터 맞추고, 날짜·pid 로는 맞지 않는다")
  func prefixAndroidTag() async throws {
    let line = "11-09 14:14:23.672  5052  5052 E AndroidRuntime: FATAL EXCEPTION: main"
    let tag = try self.compiled([Spec(.prefix, "AndroidRuntime", false)])
    #expect(await self.shows(tag, line))
    let highlights = try #require(await self.visible(tag, line)?.highlights)
    #expect(highlights == [LogHighlight(location: Int32(LogLineHeader.messageOffset(in: line)), length: 14)])
    #expect(try await !self.shows(self.compiled([Spec(.prefix, "11-09", false)]), line))
    #expect(try await !self.shows(self.compiled([Spec(.prefix, "FATAL", false)]), line))
  }
}

/// 저장된 필터와의 변환·저장 막힘 이유·50개 상한.
extension LogFilterTests {
  private static func make(_ conditions: [Spec], caseSensitive: Bool = false) throws -> LogFilter {
    var filter = LogFilter()
    for (offset, condition) in conditions.enumerated() {
      if offset > 0 {
        filter.addCondition()
      }
      let id = try #require(filter.conditions.last).id
      filter.setKind(condition.kind, of: id)
      filter.setText(condition.text, of: id)
      filter.setExcluded(condition.isExcluded, of: id)
    }
    filter.setCaseSensitive(caseSensitive)
    return filter
  }

  /// 글자 하나짜리 포함 조건으로 저장한 필터 n개 (이름 f0, f1, …).
  private static func savedFilters(_ count: Int) -> [SavedLogFilter] {
    (0 ..< count).map { number in
      SavedLogFilter(
        name: "f\(number)", conditions: [.init(kind: .contains, text: "x", isExcluded: false)], isCaseSensitive: false
      )!
    }
  }

  @Test("저장 조건은 빈 조건을 빼고 순서·종류·제외를 그대로 옮긴다")
  func savedConditions() throws {
    let filter = try Self.make([
      Spec(.prefix, "app", false), Spec(.contains, "", true), Spec(.regex, "b+", true), Spec(.contains, "c", false),
    ])
    #expect(filter.savedConditions() == [
      SavedLogFilter.Condition(kind: .prefix, text: "app", isExcluded: false),
      SavedLogFilter.Condition(kind: .regex, text: "b+", isExcluded: true),
      SavedLogFilter.Condition(kind: .contains, text: "c", isExcluded: false),
    ])
    #expect(LogFilter().savedConditions().isEmpty)
    for kind in LogFilter.Kind.allCases {
      #expect(LogFilter.Kind(kind.saved) == kind)
    }
  }

  @Test("불러오기는 조건·대소문자를 통째로 바꾸고 앞 조건 id 를 다시 쓰지 않는다")
  func loadReplacesWholeFilter() throws {
    var filter = try Self.make([Spec(.contains, "x", true), Spec(.prefix, "y", false), Spec(.contains, "z", false)])
    let oldIDs = Set(filter.conditions.map(\.id))
    filter.load(.sampleHTTP)
    #expect(filter.savedConditions() == SavedLogFilter.sampleHTTP.conditions)
    #expect(filter.conditions.count == SavedLogFilter.sampleHTTP.conditions.count)
    #expect(filter.isCaseSensitive)
    #expect(oldIDs.isDisjoint(with: filter.conditions.map(\.id)))
    filter.load(.sampleErrors)
    #expect(filter.savedConditions() == SavedLogFilter.sampleErrors.conditions)
    #expect(!filter.isCaseSensitive)
    let ids = filter.conditions.map(\.id)
    filter.addCondition()
    #expect(Set(filter.conditions.map(\.id)).count == ids.count + 1)
  }

  @Test("저장 막힘 이유 순서: 잠김 → 빈 필터 → 정규식 오류 → 조건 수 → 글자 수, 50개는 막힘 이유가 아니다")
  func saveBlockOrder() throws {
    let open = SavedLogFilterSetting(filters: [], isLocked: false)
    let locked = SavedLogFilterSetting(filters: [], isLocked: true)
    let empty = try Self.make([Spec(.contains, "", false), Spec(.regex, "", true)])
    let invalid = try Self.make([Spec(.regex, "(", false)])
    let problem = invalid.compiled().failure
    #expect(problem != nil)
    let longText = String(repeating: "a", count: SavedLogFilter.maxTextLength + 1)
    let tooMany = try Self.make(
      Array(repeating: Spec(.contains, longText, false), count: SavedLogFilter.maxConditions + 1)
    )
    let tooLong = try Self.make([Spec(.contains, "ok", false), Spec(.contains, longText, true)])
    let valid = try Self.make([Spec(.contains, "error", false)])
    let maxed = try Self.make(Array(
      repeating: Spec(.contains, String(repeating: "a", count: SavedLogFilter.maxTextLength), false),
      count: SavedLogFilter.maxConditions
    ))

    #expect(LogFilterSaveBlock.reason(filter: empty, problem: nil, saved: locked) == .locked)
    #expect(LogFilterSaveBlock.reason(filter: invalid, problem: problem, saved: locked) == .locked)
    #expect(LogFilterSaveBlock.reason(filter: empty, problem: nil, saved: open) == .emptyFilter)
    #expect(LogFilterSaveBlock.reason(filter: invalid, problem: problem, saved: open) == .invalidRegex)
    #expect(LogFilterSaveBlock.reason(filter: tooMany, problem: nil, saved: open) == .tooManyConditions)
    #expect(LogFilterSaveBlock.reason(filter: tooLong, problem: nil, saved: open) == .textTooLong)
    #expect(LogFilterSaveBlock.reason(filter: valid, problem: nil, saved: open) == nil)
    #expect(LogFilterSaveBlock.reason(filter: maxed, problem: nil, saved: open) == nil)
    let full = SavedLogFilterSetting(filters: Self.savedFilters(SavedLogFilter.maxCount), isLocked: false)
    #expect(LogFilterSaveBlock.reason(filter: valid, problem: nil, saved: full) == nil)
  }

  @Test("50개 상한은 새 이름에만 걸리고 같은 이름(대소문자 무시)·49개·빈 이름에는 걸리지 않는다")
  func overLimit() {
    let full = SavedLogFilterSetting(filters: Self.savedFilters(SavedLogFilter.maxCount), isLocked: false)
    let almost = SavedLogFilterSetting(filters: Self.savedFilters(SavedLogFilter.maxCount - 1), isLocked: false)
    #expect(LogFilterSaveDraft.isOverLimit(name: "new", saved: full))
    #expect(!LogFilterSaveDraft.isOverLimit(name: "F3", saved: full))
    #expect(!LogFilterSaveDraft.isOverLimit(name: "  f49 ", saved: full))
    #expect(!LogFilterSaveDraft.isOverLimit(name: "", saved: full))
    #expect(!LogFilterSaveDraft.isOverLimit(name: "   ", saved: full))
    #expect(!LogFilterSaveDraft.isOverLimit(name: "new", saved: almost))
  }
}

private extension Result {
  var failure: Failure? {
    if case let .failure(error) = self {
      return error
    }
    return nil
  }
}
