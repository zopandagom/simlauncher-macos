import Foundation
import Testing
@testable import ScreenLayoutImpl

struct LayoutRunnerProtocolTests {
  static func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
  }

  @Test("request: snapshot 은 id·command·bundleIDs·settle, quit 는 id·command")
  func request() throws {
    let snapshot = LayoutRunnerProtocol.requestData(
      id: "R1",
      command: .snapshot(bundleIDs: ["a.b", "c.d"], settle: 8)
    )
    let object = try #require(try JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
    #expect(object["id"] as? String == "R1")
    #expect(object["command"] as? String == "snapshot")
    #expect(object["bundleIDs"] as? [String] == ["a.b", "c.d"])
    #expect(object["settle"] as? Double == 8)

    let quit = try #require(
      try JSONSerialization.jsonObject(with: LayoutRunnerProtocol.requestData(
        id: "R2",
        command: .quit
      )) as? [String: Any]
    )
    #expect(quit.count == 2)
    #expect(quit["command"] as? String == "quit")
  }

  @Test("ready: 프로토콜·토큰·pid·scale 이 맞을 때만 받아들인다")
  func ready() {
    let good: [String: Any] = ["protocol": 1, "session": "T", "pid": 4321, "scale": 3.0]
    #expect(LayoutRunnerProtocol.ready(from: Self.json(good), token: "T") == .init(pid: 4321, scale: 3))
    #expect(LayoutRunnerProtocol.ready(from: Self.json(good), token: nil) == .init(pid: 4321, scale: 3))
    #expect(LayoutRunnerProtocol.ready(from: Self.json(good.merging(["scale": 1]) { $1 }), token: "T")?.scale == 1)
    #expect(LayoutRunnerProtocol.ready(from: Self.json(good.merging(["scale": 4]) { $1 }), token: "T")?.scale == 4)
    let rejected: [[String: Any]] = [
      good.merging(["protocol": 2]) { $1 },
      good.merging(["session": "other"]) { $1 },
      good.merging(["pid": 1]) { $1 },
      good.merging(["pid": 0]) { $1 },
      good.merging(["pid": Int(Int32.max) + 1]) { $1 },
      good.merging(["scale": 0.5]) { $1 },
      good.merging(["scale": 4.5]) { $1 },
      good.merging(["scale": "3"]) { $1 },
      good.filter { $0.key != "pid" },
    ]
    for object in rejected {
      #expect(LayoutRunnerProtocol.ready(from: Self.json(object), token: "T") == nil, "\(object)")
    }
    #expect(LayoutRunnerProtocol.ready(from: Data("{".utf8), token: "T") == nil)
  }

  static var node: [String: Any] {
    ["d": 0, "t": 2, "x": 0, "y": 0.5, "w": 402, "h": 874, "i": "root", "l": "앱"]
  }

  @Test("response: 성공 스냅샷을 노드까지 읽는다 (정수로 쓰인 좌표도 수)")
  func snapshot() {
    let data = Self.json([
      "id": "R", "apps": ["a.b"], "system": false, "truncated": false, "nodes": [Self.node],
    ])
    let expected = LayoutRunnerProtocol.Snapshot(
      apps: ["a.b"],
      system: false,
      truncated: false,
      nodes: [
        .init(
          depth: 0, type: 2, x: 0, y: 0.5, width: 402, height: 874,
          identifier: "root", label: "앱", title: nil, value: nil
        ),
      ]
    )
    #expect(LayoutRunnerProtocol.response(from: data, id: "R") == .response(.snapshot(expected)))
  }

  @Test(
    "response: 실패 값",
    arguments: LayoutRunnerProtocol.RunnerFailure.allCases
  )
  func failure(_ failure: LayoutRunnerProtocol.RunnerFailure) {
    let data = Self.json(["id": "R", "error": failure.rawValue])
    #expect(LayoutRunnerProtocol.response(from: data, id: "R") == .response(.failure(failure)))
  }

  @Test("response: quit 응답")
  func quit() {
    #expect(LayoutRunnerProtocol.response(from: Self.json(["id": "R", "ok": true]), id: "R") == .response(.quit))
  }

  @Test("response: 다른 id·JSON 아님·id 없음은 기다린다, 빈 id·맞는 id 의 틀린 형식은 거절")
  func pendingAndRejected() {
    #expect(LayoutRunnerProtocol.response(from: Self.json(["id": "old", "ok": true]), id: "R") == .pending)
    #expect(LayoutRunnerProtocol.response(from: Data("{\"id\":".utf8), id: "R") == .pending)
    #expect(LayoutRunnerProtocol.response(from: Self.json(["ok": true]), id: "R") == .pending)
    #expect(LayoutRunnerProtocol.response(from: Self.json(["id": "", "error": "badRequest"]), id: "R") == .rejected)
    #expect(LayoutRunnerProtocol.response(from: Self.json(["id": "R", "error": "boom"]), id: "R") == .rejected)
    #expect(LayoutRunnerProtocol.response(from: Self.json(["id": "R", "apps": ["a"]]), id: "R") == .rejected)
    var badNode = Self.node
    badNode["x"] = "0"
    let data = Self.json(["id": "R", "apps": [], "system": true, "truncated": false, "nodes": [badNode]])
    #expect(LayoutRunnerProtocol.response(from: data, id: "R") == .rejected)
    var boolNode = Self.node
    boolNode["w"] = true
    let boolData = Self.json(["id": "R", "apps": [], "system": true, "truncated": false, "nodes": [boolNode]])
    #expect(LayoutRunnerProtocol.response(from: boolData, id: "R") == .rejected)
  }

  @Test("32 MiB 를 넘는 응답 파일은 읽지 않고 거절한다")
  func oversized() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "LayoutRunnerProtocol-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "response.json")
    #expect(await LayoutRunnerPool.readResponse(at: file, id: "R") == .pending)

    FileManager.default.createFile(atPath: file.path, contents: nil)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: UInt64(LayoutRunnerProtocol.maxResponseBytes + 1))
    try handle.close()

    #expect(await LayoutRunnerPool.readResponse(at: file, id: "R") == .rejected)
  }
}
