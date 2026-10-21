import Core

/// URL 에서 설치 시트 초안. 기기는 "URL 에서…" 를 누른 시점의 값이다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `installURLDraft` 를 읽기만 한다).
public struct InstallURLDraft: Hashable, Sendable {
  public let deviceID: VirtualDevice.ID
  /// 시트 제목과 실패 알림에 보일 기기 (누른 시점의 이름·런타임 이름).
  public let device: LauncherNotice.Device
  public private(set) var text = ""

  /// 입력한 주소의 첫 문제. 없으면 nil.
  public var problem: DownloadURLProblem? {
    DownloadURL.problem(in: self.text)
  }

  /// 검사를 통과한 주소 (앞뒤 공백을 뺀 값). 문제가 있으면 nil.
  public var url: DownloadURL? {
    DownloadURL(self.text)
  }

  /// 받아서 설치를 누를 수 있는지: 입력한 주소에 문제가 없다.
  public var canSubmit: Bool {
    self.url != nil
  }

  mutating func textChanged(_ text: String) {
    self.text = text
  }
}
