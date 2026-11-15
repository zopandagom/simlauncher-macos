import Foundation
import Testing
@testable import Core

/// 푸시 payload 검사. 경계·순서는 TC-B 실측(simctl 이 입력 UTF-8 바이트를 그대로 세어 4096 통과·4097 거절, 형식별 22·14) 기준이다.
struct PushPayloadTests {
  // MARK: - 폼

  @Test("폼: 키 정렬 JSON 바이트 그대로 (제목 있음·없음), / 는 이스케이프하지 않는다")
  func formBytes() throws {
    let both = try PushPayload.alert(title: "제목 a/b", body: "본문").get()
    #expect(both.data == Data(#"{"aps":{"alert":{"body":"본문","title":"제목 a/b"}}}"#.utf8))

    let bodyOnly = try PushPayload.alert(title: "", body: "hi").get()
    #expect(bodyOnly.data == Data(#"{"aps":{"alert":{"body":"hi"}}}"#.utf8))
    #expect(bodyOnly.byteCount == 31)
  }

  @Test("폼: 본문이 공백·줄바꿈뿐이면 emptyBody, 제목이 공백뿐이면 넣지 않는다, 넣는 값은 입력 그대로")
  func formTrimming() throws {
    #expect(PushPayload.alert(title: "제목", body: " \n\t ") == .failure(.emptyBody))
    #expect(PushPayload.alert(title: "", body: "") == .failure(.emptyBody))
    let payload = try PushPayload.alert(title: "  \n", body: " 본문 ").get()
    #expect(payload.data == Data(#"{"aps":{"alert":{"body":" 본문 "}}}"#.utf8))
  }

  @Test("폼: 한글 본문은 UTF-8 3바이트로 세고, 4096 바이트를 넘으면 tooLarge")
  func formSize() throws {
    // `{"aps":{"alert":{"body":"` 25바이트 + 본문 + `"}}}` 4바이트.
    let fits = String(repeating: "가", count: 1355) + "a"
    let payload = try PushPayload.alert(title: "", body: fits).get()
    #expect(payload.byteCount == 25 + 1355 * 3 + 1 + 4)
    #expect(payload.byteCount == 4095)

    let over = String(repeating: "가", count: 1356)
    #expect(PushPayload.alert(title: "", body: over) == .failure(.tooLarge(byteCount: 25 + 1356 * 3 + 4)))
  }

  // MARK: - JSON 직접 입력

  struct Case: Sendable, CustomTestStringConvertible {
    let text: String
    let problem: PushPayloadProblem

    var testDescription: String {
      self.text.debugDescription
    }
  }

  @Test(
    "JSON 검사: 문제별 결과",
    arguments: [
      Case(text: "", problem: .empty),
      Case(text: " \n\t", problem: .empty),
      Case(text: #"{"aps":"#, problem: .notJSON),
      Case(text: "aps", problem: .notJSON),
      Case(text: "{\u{201C}aps\u{201D}:{}}", problem: .smartQuotes),
      Case(text: "{'aps':{\u{2018}alert\u{2019}:1}}", problem: .smartQuotes),
      Case(text: "[1]", problem: .rootNotObject),
      Case(text: "5", problem: .rootNotObject),
      Case(text: #""aps""#, problem: .rootNotObject),
      Case(text: "null", problem: .rootNotObject),
      Case(text: #"{"x":1}"#, problem: .missingAPS),
      Case(text: #"{"aps":"x"}"#, problem: .apsNotObject),
      Case(text: #"{"aps":[]}"#, problem: .apsNotObject),
      Case(text: #"{"aps":{}}"#, problem: .apsEmpty),
      Case(text: #"{"aps":{"alert":5}}"#, problem: .alertInvalid),
      Case(text: #"{"aps":{"alert":null}}"#, problem: .alertInvalid),
      Case(text: #"{"aps":{"alert":["a"]}}"#, problem: .alertInvalid),
      Case(text: #"{"aps":{"alert":true}}"#, problem: .alertInvalid),
    ]
  )
  func jsonProblems(_ testCase: Case) {
    #expect(PushPayload.json(testCase.text) == .failure(testCase.problem))
  }

  @Test("JSON 검사 순서: 형식 문제를 크기보다 먼저 알린다")
  func jsonOrder() {
    let bigBroken = #"{"aps":"# + String(repeating: " ", count: 5000)
    #expect(PushPayload.json(bigBroken) == .failure(.notJSON))
    let bigMissing = #"{"x":""# + String(repeating: "a", count: 5000) + #""}"#
    #expect(PushPayload.json(bigMissing) == .failure(.missingAPS))
  }

  @Test(
    "JSON 통과: alert 문자열·사전, alert 없는 aps (badge·sound·content-available), Simulator Target Bundle 키는 보지 않는다",
    arguments: [
      #"{"aps":{"alert":"hi"}}"#,
      #"{"aps":{"alert":{"title":"TCB 배너 제목","body":"본문입니다"}}}"#,
      #"{"aps":{"badge":3}}"#,
      #"{"aps":{"content-available":1}}"#,
      #"{"Simulator Target Bundle":"com.example.none","aps":{"alert":"hi"}}"#,
    ]
  )
  func jsonPasses(_ text: String) throws {
    let payload = try PushPayload.json(text).get()
    #expect(payload.data == Data(text.utf8))
  }

  @Test("JSON: 입력 바이트를 그대로 보낸다 (공백·줄바꿈·이스케이프·키 순서를 다시 직렬화하지 않는다)")
  func jsonKeepsBytes() throws {
    let text = "\n  { \"aps\" :{\"sound\":\"default\",  \"alert\":\"\\uac00\\n\"}}  \n"
    let payload = try PushPayload.json(text).get()
    #expect(payload.data == Data(text.utf8))
    #expect(payload.byteCount == text.utf8.count)
  }

  @Test("JSON 4096/4097 경계: ASCII·한글 3바이트·공백 패딩 모두 입력 UTF-8 바이트로 센다")
  func jsonBoundary() {
    // `{"aps":{"alert":"` 17바이트 + 채움 + `"}}` 3바이트.
    func ascii(_ total: Int) -> String {
      #"{"aps":{"alert":""# + String(repeating: "a", count: total - 20) + #""}}"#
    }
    #expect(PushPayload.json(ascii(4096)).map(\.byteCount) == .success(4096))
    #expect(PushPayload.json(ascii(4097)) == .failure(.tooLarge(byteCount: 4097)))

    // 한글 1358자(4074바이트) + ASCII 로 맞춘다.
    func korean(_ total: Int) -> String {
      let hangul = String(repeating: "가", count: 1358)
      return #"{"aps":{"alert":""# + hangul + String(repeating: "a", count: total - 20 - 1358 * 3) + #""}}"#
    }
    #expect(PushPayload.json(korean(4096)).map(\.byteCount) == .success(4096))
    #expect(PushPayload.json(korean(4097)) == .failure(.tooLarge(byteCount: 4097)))

    // 압축하면 22바이트인 payload 도 공백까지 센다 (실측 5022 → 거절).
    let padded = #"{"aps":{"alert":"hi"}}"# + String(repeating: " ", count: 5000)
    #expect(PushPayload.json(padded) == .failure(.tooLarge(byteCount: 5022)))
  }

  @Test("최대 바이트 수는 4096")
  func maxByteCount() {
    #expect(PushPayload.maxByteCount == 4096)
  }
}
