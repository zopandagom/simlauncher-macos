/// 닫지 않은 알림 줄. 쌓인 순서이고, 화면은 첫 항목을 보인다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `notices` 를 읽기만 한다).
public struct LauncherNotices: Hashable, Sendable {
  public private(set) var items: [LauncherNoticeItem] = []
  /// 다음에 쌓을 항목의 id. 닫아도 줄어들지 않는다 (같은 내용이 다시 쌓여도 새 id).
  private var nextID = 0

  public init() {}

  /// 기기 작업 실패는 늘 쌓는다. 새로 고침 실패는 같은 원인이 이미 줄에 있으면 쌓지 않는다.
  mutating func enqueue(_ notice: LauncherNotice) {
    if case .refreshFailed = notice, self.items.contains(where: { $0.notice == notice }) {
      return
    }
    self.items.append(LauncherNoticeItem(id: self.nextID, notice: notice))
    self.nextID += 1
  }

  /// id 가 같은 항목만 지운다. 없으면 아무것도 하지 않아, 두 번 불려도 다음 알림을 지우지 않는다.
  mutating func dismiss(_ id: LauncherNoticeItem.ID) {
    self.items.removeAll { $0.id == id }
  }
}
