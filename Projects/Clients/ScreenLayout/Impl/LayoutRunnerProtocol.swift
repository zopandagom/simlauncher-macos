import Foundation

/// 호스트(SimLauncher)와 러너가 세션 폴더의 파일로 주고받는 규약 (프로토콜 1). 순수 함수만 둔다.
/// 모든 파일은 `<이름>.tmp` 에 쓴 뒤 `rename(2)` 로 내놓는다 (호스트도 러너도). 이름·키는 이 타입의 상수만 쓰고,
/// `runnerContract` 를 러너 원문(`LayoutRunnerSource.tests`)과 대조하는 테스트가 두 쪽이 어긋나지 않게 막는다.
enum LayoutRunnerProtocol {
  static let version = 1

  static let readyFile = "ready.json"
  static let requestFile = "request.json"
  static let responseFile = "response.json"
  /// xcodebuild 결과 번들 (호스트만 쓴다. 러너가 SIGTERM 등으로 실패하면 자동 화면 캡처가 남을 수 있다).
  static let resultBundle = "result.xcresult"

  /// 러너 안에서 보이는 환경 이름. xcodebuild 에는 `TEST_RUNNER_` 를 붙여 넘긴다 (러너 안에서는 떼고 보인다, 실측).
  static let directoryVariable = "SIMLAUNCHER_LAYOUT_DIR"
  static let sessionVariable = "SIMLAUNCHER_LAYOUT_SESSION"
  static let idleVariable = "SIMLAUNCHER_LAYOUT_IDLE"
  static let testRunnerPrefix = "TEST_RUNNER_"

  /// JSON 키.
  enum Key {
    static let protocolVersion = "protocol"
    static let session = "session"
    static let pid = "pid"
    static let scale = "scale"
    static let id = "id"
    static let command = "command"
    static let bundleIDs = "bundleIDs"
    static let settle = "settle"
    static let apps = "apps"
    static let system = "system"
    static let truncated = "truncated"
    static let nodes = "nodes"
    static let acknowledged = "ok"
    static let error = "error"
    static let depth = "d"
    static let type = "t"
    static let x = "x"
    static let y = "y"
    static let width = "w"
    static let height = "h"
    static let identifier = "i"
    static let label = "l"
    static let title = "ti"
    static let value = "v"
  }

  /// request 의 `command` 값.
  static let snapshotCommand = "snapshot"
  static let quitCommand = "quit"

  /// 응답 파일 크기 상한. 넘으면 읽지 않고 거절한다 (기기 안 앱이 정한 문자열을 담는 신뢰하지 않는 입력).
  static let maxResponseBytes = 32 * 1024 * 1024
  /// 노드 수 상한 (러너가 넘으면 `truncated`).
  static let maxNodes = 20000
  /// ready.json 크기 상한.
  static let maxReadyBytes = 64 * 1024

  /// 러너 원문에 따옴표 문자열(`"<값>"`)로 들어 있어야 하는 이름 전부.
  static var runnerContract: [String] {
    [
      self.readyFile, self.requestFile, self.responseFile,
      self.directoryVariable, self.sessionVariable, self.idleVariable,
      Key.protocolVersion, Key.session, Key.pid, Key.scale,
      Key.id,
      Key.apps, Key.system, Key.truncated, Key.nodes, Key.acknowledged, Key.error,
      Key.depth, Key.type, Key.x, Key.y, Key.width, Key.height, Key.identifier, Key.label, Key.title, Key.value,
      self.snapshotCommand, self.quitCommand,
    ] + RunnerFailure.allCases.map(\.rawValue)
  }

  /// 러너가 `Decodable` 프로퍼티 이름(`let <이름>:`)으로 읽는 request 키. 따옴표 문자열이 아니라 따로 대조한다.
  static var runnerRequestFields: [String] {
    [Key.id, Key.command, Key.bundleIDs, Key.settle]
  }

  // MARK: ready.json

  /// 받아들인 ready.json.
  struct Ready: Hashable, Sendable {
    let pid: Int32
    let scale: Double
  }

  /// protocol == 1, session == `token`(nil 이면 보지 않는다: 남은 러너 정리), pid > 1, scale 이 유한하고 1…4 일 때만 받아들인다.
  static func ready(from data: Data, token: String?) -> Ready? {
    guard data.count <= self.maxReadyBytes,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let version = object[Key.protocolVersion] as? Int, version == self.version,
          let pid = object[Key.pid] as? Int, pid > 1, pid <= Int(Int32.max),
          let scale = object[Key.scale] as? Double, scale.isFinite, (1 ... 4).contains(scale)
    else {
      return nil
    }
    if let token {
      guard let session = object[Key.session] as? String, session == token else { return nil }
    }
    return Ready(pid: Int32(pid), scale: scale)
  }

  // MARK: request.json

  enum Command: Hashable, Sendable {
    /// 후보 번들 ID 중 앞 앱(없으면 SpringBoard)을 읽는다. 러너가 `settle` 초까지 앞 앱이 하나가 되기를 기다린다.
    case snapshot(bundleIDs: [String], settle: Double)
    /// 러너가 응답을 쓰고 테스트 메서드에서 돌아온다 (xcodebuild 정상 종료).
    case quit
  }

  static func requestData(id: String, command: Command) -> Data {
    var object: [String: Any] = [Key.id: id]
    switch command {
    case let .snapshot(bundleIDs, settle):
      object[Key.command] = self.snapshotCommand
      object[Key.bundleIDs] = bundleIDs
      object[Key.settle] = settle
    case .quit:
      object[Key.command] = self.quitCommand
    }
    // 키·값이 모두 문자열·배열·유한한 수라 실패하지 않는다. 실패하면 빈 데이터 (러너가 badRequest 로 답한다).
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
  }

  // MARK: response.json

  /// 러너 응답의 노드 하나 (pt, 현재 방향).
  struct Node: Hashable, Sendable {
    let depth: Int
    let type: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let identifier: String?
    let label: String?
    let title: String?
    let value: String?
  }

  /// 성공한 스냅샷 응답.
  struct Snapshot: Hashable, Sendable {
    let apps: [String]
    let system: Bool
    let truncated: Bool
    let nodes: [Node]
  }

  /// 러너가 쓴 실패 값.
  enum RunnerFailure: String, CaseIterable, Hashable, Sendable {
    case notForeground
    case snapshotFailed
    case badRequest
    case unknownCommand
  }

  enum Response: Hashable, Sendable {
    case snapshot(Snapshot)
    case quit
    case failure(RunnerFailure)
  }

  /// response.json 을 읽은 결과.
  enum ResponseRead: Hashable, Sendable {
    /// 아직 이 요청의 응답이 아니다 (파일 없음, JSON 객체 아님, 다른 id: 취소된 앞 요청의 늦은 응답일 수 있다). 계속 기다린다.
    case pending
    /// 이 요청의 응답.
    case response(Response)
    /// 받아들일 수 없다 (id 가 빈 응답: 러너가 요청을 해석하지 못해 맞는 응답이 오지 않는다, 맞는 id 인데 형식이 틀림). 곧바로 실패.
    case rejected
  }

  /// 크기 검사는 호출한 쪽이 먼저 한다 (`maxResponseBytes`).
  static func response(from data: Data, id: String) -> ResponseRead {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let responseID = object[Key.id] as? String
    else {
      return .pending
    }
    if responseID.isEmpty {
      return .rejected
    }
    guard responseID == id else { return .pending }
    if let error = object[Key.error] {
      guard let raw = error as? String, let failure = RunnerFailure(rawValue: raw) else { return .rejected }
      return .response(.failure(failure))
    }
    if object[Key.acknowledged] as? Bool == true {
      return .response(.quit)
    }
    guard let snapshot = self.snapshot(from: object) else { return .rejected }
    return .response(.snapshot(snapshot))
  }

  private static func snapshot(from object: [String: Any]) -> Snapshot? {
    guard let apps = object[Key.apps] as? [String],
          let system = object[Key.system] as? Bool,
          let truncated = object[Key.truncated] as? Bool,
          let rawNodes = object[Key.nodes] as? [Any]
    else {
      return nil
    }
    var nodes: [Node] = []
    nodes.reserveCapacity(rawNodes.count)
    for raw in rawNodes {
      guard let dictionary = raw as? [String: Any], let node = self.node(from: dictionary) else { return nil }
      nodes.append(node)
    }
    return Snapshot(apps: apps, system: system, truncated: truncated, nodes: nodes)
  }

  private static func node(from object: [String: Any]) -> Node? {
    guard let depth = object[Key.depth] as? Int,
          let type = object[Key.type] as? Int,
          let x = self.number(object[Key.x]),
          let y = self.number(object[Key.y]),
          let width = self.number(object[Key.width]),
          let height = self.number(object[Key.height])
    else {
      return nil
    }
    return Node(
      depth: depth,
      type: type,
      x: x,
      y: y,
      width: width,
      height: height,
      identifier: object[Key.identifier] as? String,
      label: object[Key.label] as? String,
      title: object[Key.title] as? String,
      value: object[Key.value] as? String
    )
  }

  /// JSON 수 (정수로 쓰인 0 도 Double 로). 불·문자열은 nil.
  private static func number(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    return number.doubleValue
  }
}
