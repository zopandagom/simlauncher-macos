import AppKit
import AppLogInterface
import SwiftUI

/// 로그 줄 목록. SwiftUI `List` 는 5만 줄에 묶음마다 메인을 90~130ms 잡고 `scrollTo` 가 재진입 경고를 내서, `NSTableView` 를
/// 부분 갱신(앞 버림 `removeRows`·끝 추가 `insertRows`)으로 쓴다 (같은 부하에서 추가 부하가 거의 없었다. 2026-11-03 실측).
/// 행은 줄바꿈 레이블(고정폭 글꼴, 자동 행 높이)이고, 거르기가 계산해 넘긴 강조 범위만 배경색으로 칠한다 (메인에서 정규식을 돌리지 않는다).
/// 같은 세대 안에서 같은 번호 줄의 강조는 바뀌지 않는다 (강조가 바뀌는 필터 바꿈은 전체 다시 거르기라 세대가 바뀐다). 세대(`generation`)가 바뀌면 전부 다시 읽는다.
/// 사용자 스크롤(휠·트랙패드·스크롤 막대 끌기)만 맨 아래를 떠났는지·닿았는지 알린다 (따라가기 스크롤과 창 크기 바꾸기는 알리지 않는다).
struct LogLineTable: NSViewRepresentable {
  let lines: [VisibleLogLine]
  let generation: Int
  let isFollowing: Bool
  let scrolledAwayFromBottom: @MainActor () -> Void
  let scrolledToBottom: @MainActor () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> LogScrollView {
    let table = NSTableView()
    let column = NSTableColumn(identifier: Coordinator.columnID)
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.usesAutomaticRowHeights = true
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.selectionHighlightStyle = .none
    table.intercellSpacing = NSSize(width: 0, height: 2)
    table.style = .plain
    table.dataSource = context.coordinator
    table.delegate = context.coordinator
    let scrollView = LogScrollView()
    scrollView.documentView = table
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.onUserScroll = { [weak coordinator = context.coordinator] atBottom in
      coordinator?.userScrolled(atBottom: atBottom)
    }
    context.coordinator.tableView = table
    return scrollView
  }

  func updateNSView(_ scrollView: LogScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.scrolledAwayFromBottom = self.scrolledAwayFromBottom
    coordinator.scrolledToBottom = self.scrolledToBottom
    coordinator.update(lines: self.lines, generation: self.generation, isFollowing: self.isFollowing)
  }

  @MainActor
  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let columnID = NSUserInterfaceItemIdentifier("line")
    private static let cellID = NSUserInterfaceItemIdentifier("lineCell")
    private static let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    private static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.4)

    weak var tableView: NSTableView?
    var scrolledAwayFromBottom: @MainActor () -> Void = {}
    var scrolledToBottom: @MainActor () -> Void = {}
    private var lines: [VisibleLogLine] = []
    private var generation: Int?
    /// 마지막으로 알린 사용자 스크롤 위치 (같은 알림을 거듭 보내지 않게).
    private var reportedAtBottom: Bool?

    func update(lines: [VisibleLogLine], generation: Int, isFollowing: Bool) {
      guard let tableView = self.tableView else { return }
      let old = self.lines
      self.lines = lines
      if generation != self.generation || !self.applyIncrementally(old: old, new: lines, to: tableView) {
        self.generation = generation
        tableView.reloadData()
      }
      if isFollowing, !lines.isEmpty {
        tableView.scrollRowToVisible(lines.count - 1)
        self.reportedAtBottom = true
      }
    }

    /// 앞에서 버린 줄과 끝에 붙은 줄만 반영한다. 그 모양이 아니면 거짓 (전부 다시 읽는다).
    private func applyIncrementally(old: [VisibleLogLine], new: [VisibleLogLine], to tableView: NSTableView) -> Bool {
      guard old.count == tableView.numberOfRows else { return false }
      let firstKept = new.first?.index ?? Int.max
      let dropped = old.firstIndex { $0.index >= firstKept } ?? old.count
      let kept = old.count - dropped
      let appended = new.count - kept
      guard appended >= 0 else { return false }
      if kept > 0 {
        // 남은 줄이 그대로 이어지는지 양 끝만 본다 (번호는 줄마다 하나라 끝이 같으면 가운데도 같다).
        guard new[0].index == old[dropped].index, new[kept - 1].index == old[old.count - 1].index else { return false }
      }
      guard dropped > 0 || appended > 0 else { return true }
      tableView.beginUpdates()
      if dropped > 0 {
        tableView.removeRows(at: IndexSet(integersIn: 0 ..< dropped), withAnimation: [])
      }
      if appended > 0 {
        tableView.insertRows(at: IndexSet(integersIn: kept ..< new.count), withAnimation: [])
      }
      tableView.endUpdates()
      return true
    }

    func userScrolled(atBottom: Bool) {
      guard atBottom != self.reportedAtBottom else { return }
      self.reportedAtBottom = atBottom
      if atBottom {
        self.scrolledToBottom()
      } else {
        self.scrolledAwayFromBottom()
      }
    }

    // MARK: - NSTableViewDataSource·Delegate

    func numberOfRows(in _: NSTableView) -> Int {
      self.lines.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
      let field = (tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTextField) ?? Self.makeField()
      guard self.lines.indices.contains(row) else { return field }
      field.attributedStringValue = self.attributed(self.lines[row])
      return field
    }

    private func attributed(_ line: VisibleLogLine) -> NSAttributedString {
      let string = NSMutableAttributedString(
        string: line.line.text, attributes: [.font: Self.font, .foregroundColor: NSColor.labelColor]
      )
      let length = string.length
      for range in line.highlights.map(\.nsRange) where range.location >= 0 && range.upperBound <= length {
        string.addAttribute(.backgroundColor, value: Self.highlightColor, range: range)
      }
      return string
    }

    private static func makeField() -> NSTextField {
      let field = NSTextField(wrappingLabelWithString: "")
      field.identifier = Self.cellID
      field.font = Self.font
      field.isSelectable = false
      field.lineBreakMode = .byCharWrapping
      return field
    }
  }
}

/// 사용자 스크롤만 알리는 스크롤 뷰. 휠·트랙패드는 `scrollWheel`, 스크롤 막대 끌기는 live scroll 알림으로 본다.
/// 프로그램 스크롤(`scrollRowToVisible`)과 창 크기 바꾸기는 이 경로를 지나지 않는다.
final class LogScrollView: NSScrollView {
  var onUserScroll: (@MainActor (_ atBottom: Bool) -> Void)?
  private var liveScrollObservers: [NSObjectProtocol] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    let center = NotificationCenter.default
    for name in [NSScrollView.didLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
      let observer = center.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.reportScroll()
        }
      }
      self.liveScrollObservers.append(observer)
    }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  isolated deinit {
    for observer in self.liveScrollObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  override func scrollWheel(with event: NSEvent) {
    super.scrollWheel(with: event)
    self.reportScroll()
  }

  private func reportScroll() {
    guard let document = self.documentView else { return }
    let visible = self.contentView.bounds
    // 표는 뒤집힌 좌표라 아래 끝이 maxY 다. 내용이 창보다 짧으면 맨 아래로 본다. 2pt 는 반올림 여유.
    let atBottom = visible.maxY >= document.frame.maxY - 2
    self.onUserScroll?(atBottom)
  }
}
