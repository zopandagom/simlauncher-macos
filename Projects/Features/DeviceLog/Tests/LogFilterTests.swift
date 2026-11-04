import AppLogInterface
import Foundation
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
