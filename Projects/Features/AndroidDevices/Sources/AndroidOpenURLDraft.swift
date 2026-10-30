import Core

/// 링크 열기 시트 초안. 기기는 "링크 열기…" 를 누른 시점의 값이다 (iOS `OpenURLDraft` 와 같은 모양).
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `openURLDraft` 를 읽기만 한다).
public struct AndroidOpenURLDraft: Hashable, Sendable {
  public let deviceID: AndroidVirtualDevice.ID
  /// 시트 제목과 실패 알림에 보일 기기 (누른 시점의 이름·API).
  public let device: AndroidDeviceLabel
  public private(set) var text = ""

  /// 입력한 링크의 첫 문제. 없으면 nil.
  public var problem: DeepLinkProblem? {
    DeepLink.problem(in: self.text)
  }

  /// 검사를 통과한 링크 (앞뒤 공백을 뺀 값). 문제가 있으면 nil.
  public var link: DeepLink? {
    DeepLink(self.text)
  }

  /// 열기를 누를 수 있는지: 입력한 링크에 문제가 없다.
  public var canSubmit: Bool {
    self.link != nil
  }

  mutating func textChanged(_ text: String) {
    self.text = text
  }
}
