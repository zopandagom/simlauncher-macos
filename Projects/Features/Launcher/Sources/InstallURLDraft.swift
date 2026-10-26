import Core

/// URL 에서 설치 시트 초안. 대상 기기는 "URL 에서…" 를 누른 시점의 값이다 (행 메뉴면 1대, 툴바면 고른 기기 전부).
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `installURLDraft` 를 읽기만 한다).
public struct InstallURLDraft: Hashable, Sendable {
  /// 시트 제목과 실패 알림에 보일 대상 기기 (1대 이상, 누른 시점의 목록 순서·이름·런타임 이름).
  /// 설치할 수 없는 기기도 들어 있을 수 있다 (설치를 시작할 때 판정해 이유와 함께 건너뛴다).
  public let targets: [TargetDevice]
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
