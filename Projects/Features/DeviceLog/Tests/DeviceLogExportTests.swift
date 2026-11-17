import AppLogInterface
import AppLogTesting
import Core
import Foundation
import Synchronization
import Testing
import WorkspaceInterface
import WorkspaceTesting
@testable import DeviceLogFeature

/// 로그 창 "복사"·"저장…" (Model + AppLog·Workspace Fake): 누를 수 있는 조건, 스냅숏, 성공·실패, 겹침·창 닫기·옛 요청.
@MainActor
struct DeviceLogExportTests {
  typealias Support = DeviceLogTestSupport

  static let file = URL(filePath: "/Users/tester/Desktop/log.txt", directoryHint: .notDirectory)

  struct Opened {
    let model: DeviceLogModel
    let fake: AppLogClientFake
    let workspace: WorkspaceClientFake
    let sleeper: ManualSleeper
    let session: AppLogSessionSummary
  }

  /// 세션 하나에 줄을 넣고 창을 열어 모두 보일 때까지 기다린다.
  func opened(_ lines: [String] = ["tick 1", "tick 2"], sessions extra: [AppLogSessionSummary] = []) async -> Opened {
    let session = Support.summary(at: 10)
    let workspace = WorkspaceClientFake()
    let sleeper = ManualSleeper()
    let (model, fake) = Support.fixture(
      extra + [session], workspace: workspace, sleep: { try await sleeper.sleep($0) }
    )
    if !lines.isEmpty {
      fake.append(lines, to: session.id)
    }
    await Support.openAndWait(model, expecting: session.id, visible: lines.count)
    if lines.isEmpty {
      await Support.settle()
    }
    return Opened(model: model, fake: fake, workspace: workspace, sleeper: sleeper, session: session)
  }

  func export(_ opened: Opened) -> DeviceLogWindow.ExportPhase {
    opened.model.window(for: Support.target).export
  }

  /// "저장…" 을 누르고 요청 번호를 돌려준다.
  func saveTapped(_ opened: Opened) throws -> Int {
    opened.model.saveTapped(in: Support.target)
    guard case let .choosingLocation(_, request) = self.export(opened) else {
      Issue.record("저장 위치 고르기가 아니다: \(self.export(opened))")
      throw CancellationError()
    }
    return request
  }

  // MARK: - 복사

  @Test("복사는 누른 순간의 보이는 줄과 머리말을 클립보드에 쓰고 복사됨이 된다")
  func copyWritesSnapshotText() async {
    let opened = await self.opened()
    let snapshot = LogExportSnapshot(
      window: opened.model.window(for: Support.target), session: opened.session, exportedAt: Support.exportDate,
      simLauncherVersion: "1.3.0 (45)"
    )
    let expected = await LogExportText.make(snapshot, timeZone: Support.seoul)

    await opened.model.copyTapped(in: Support.target)

    #expect(opened.workspace.copiedTexts == [expected])
    #expect(expected.contains("내보낸 시각: 2027-01-15 18:00:00 +09:00\n"))
    #expect(expected.contains("SimLauncher 버전: 1.3.0 (45)\n"))
    #expect(expected.contains("앱 버전: 1.2 (34)\n"))
    #expect(expected.hasSuffix("----------------------------------------\ntick 1\ntick 2\n"))
    #expect(self.export(opened) == .copied)
  }

  @Test("복사됨은 정한 시간이 지나면 사라진다")
  func copiedResetsAfterDuration() async {
    let opened = await self.opened()
    await opened.model.copyTapped(in: Support.target)
    #expect(self.export(opened) == .copied)
    await Support.waitUntil { opened.sleeper.count == 1 }
    #expect(opened.sleeper.durations == [.seconds(2)])

    opened.sleeper.fire(0)

    await Support.waitUntil { self.export(opened) == .idle }
  }

  @Test("복사됨 동안 다시 복사하면 처음부터 다시 하고 앞 타이머는 상태를 바꾸지 않는다")
  func copyAgainWhileCopiedRestartsTimer() async {
    let opened = await self.opened()
    await opened.model.copyTapped(in: Support.target)
    await Support.waitUntil { opened.sleeper.count == 1 }
    await opened.model.copyTapped(in: Support.target)
    await Support.waitUntil { opened.sleeper.count == 2 }
    #expect(opened.workspace.copiedTexts.count == 2)

    opened.sleeper.fire(0)
    await Support.settle()
    #expect(self.export(opened) == .copied)

    opened.sleeper.fire(1)
    await Support.waitUntil { self.export(opened) == .idle }
  }

  @Test("클립보드에 쓰지 못하면 이유를 보이고, 다음 복사를 누르면 지워진다")
  func copyFailureShowsReason() async {
    let opened = await self.opened()
    opened.workspace.setCopyError(.clipboardUnavailable)

    await opened.model.copyTapped(in: Support.target)

    #expect(self.export(opened) == .failed(.copy(.clipboardUnavailable)))
    #expect(DeviceLogText.exportFailed(.copy(.clipboardUnavailable)) == "클립보드에 복사하지 못했습니다. 다시 시도하세요.")
    #expect(opened.workspace.copiedTexts.isEmpty)
    opened.workspace.setCopyError(nil)
    await opened.model.copyTapped(in: Support.target)
    #expect(self.export(opened) == .copied)
  }

  @Test("복사할 글을 만드는 동안 창을 닫으면 클립보드에 쓰지 않는다")
  func closeWhileCopyingSkipsClipboard() async {
    let opened = await self.opened()
    let copy = Task { await opened.model.copyTapped(in: Support.target) }
    // `.copying` 이 보이면 복사는 글 만들기(메인 밖)를 기다리는 중이고, 메인을 놓지 않은 채 창을 닫는다.
    await Support.waitUntil { self.export(opened) == .copying }
    opened.model.windowDisappeared(Support.target)
    await copy.value

    #expect(!opened.workspace.calls.contains {
      if case .copyToClipboard = $0 {
        true
      } else {
        false
      }
    })
    #expect(self.export(opened) == .idle)
  }

  // MARK: - 누를 수 없음

  @Test("세션이 없거나 보이는 줄이 없거나 창이 닫혔으면 누를 수 없고 이벤트가 와도 무시한다")
  func disabledWithoutSessionOrLines() async {
    let workspace = WorkspaceClientFake()
    let (empty, _) = Support.fixture([], workspace: workspace)
    empty.windowAppeared(Support.target)
    await Support.waitUntil { empty.hasReceivedSessions }
    #expect(!empty.window(for: Support.target).canExport)
    await empty.copyTapped(in: Support.target)
    empty.saveTapped(in: Support.target)
    #expect(empty.window(for: Support.target).export == .idle)

    let noLines = await self.opened([])
    #expect(noLines.model.window(for: Support.target).selectedSessionID == noLines.session.id)
    #expect(!noLines.model.window(for: Support.target).canExport)
    await noLines.model.copyTapped(in: Support.target)
    noLines.model.saveTapped(in: Support.target)
    #expect(self.export(noLines) == .idle)

    let closed = await self.opened()
    #expect(closed.model.window(for: Support.target).canExport)
    closed.model.windowDisappeared(Support.target)
    #expect(!closed.model.window(for: Support.target).canExport)
    await closed.model.copyTapped(in: Support.target)
    #expect(workspace.calls.isEmpty)
    #expect(noLines.workspace.calls.isEmpty)
    #expect(closed.workspace.calls.isEmpty)
  }

  @Test("필터를 바꿔 전체 다시 거르기를 기다리는 동안은 누를 수 없다")
  func disabledWhileAwaitingFullFilter() async throws {
    let opened = await self.opened()
    let condition = try #require(opened.model.window(for: Support.target).filter.conditions.first).id
    opened.model.conditionTextChanged(condition, "tick 1", in: Support.target)
    #expect(opened.model.window(for: Support.target).isAwaitingFullFilter)
    #expect(!opened.model.window(for: Support.target).canExport)

    await opened.model.copyTapped(in: Support.target)
    #expect(opened.workspace.calls.isEmpty)

    await Support.waitUntil { opened.model.window(for: Support.target).visibleCount == 1 }
    #expect(opened.model.window(for: Support.target).canExport)
  }

  @Test("정규식을 읽지 못하면(보이는 줄이 앞 필터 결과라) 누를 수 없다")
  func disabledWithFilterProblem() async throws {
    let opened = await self.opened()
    let condition = try #require(opened.model.window(for: Support.target).filter.conditions.first).id
    opened.model.conditionKindChanged(condition, .regex, in: Support.target)
    opened.model.conditionTextChanged(condition, "(", in: Support.target)
    await Support.settle()
    let window = opened.model.window(for: Support.target)
    #expect(window.filterProblem != nil)
    #expect(window.visibleCount == 2)
    #expect(!window.canExport)

    opened.model.saveTapped(in: Support.target)
    await opened.model.copyTapped(in: Support.target)
    #expect(self.export(opened) == .idle)
    #expect(opened.workspace.calls.isEmpty)
  }

  @Test("복사 중에는 복사·저장 요청을 무시한다")
  func busyIgnoresSecondRequest() async {
    let opened = await self.opened()
    opened.workspace.suspendExports()
    let copy = Task { await opened.model.copyTapped(in: Support.target) }
    await Support.waitUntil { opened.workspace.calls.count == 1 }
    #expect(self.export(opened) == .copying)
    #expect(opened.model.window(for: Support.target).isExporting)

    opened.model.saveTapped(in: Support.target)
    await opened.model.copyTapped(in: Support.target)
    #expect(self.export(opened) == .copying)
    #expect(opened.workspace.calls.count == 1)

    opened.workspace.resumeExports()
    await copy.value
    #expect(self.export(opened) == .copied)
  }
}

// 구조체 본문 길이 상한(type_body_length) 때문에 나눈다. 같은 스위트다.
extension DeviceLogExportTests {
  // MARK: - 저장

  @Test("저장…은 앱·기기 이름과 누른 시각으로 기본 파일 이름을 정해 위치 고르기로 간다")
  func saveTappedSuggestsFileName() async throws {
    let opened = await self.opened()
    let request = try self.saveTapped(opened)
    #expect(self.export(opened) == .choosingLocation(
      suggestedFileName: "SimLauncher-probe-iPhone_17_Pro-20270115-180000.txt", request: request
    ))
    #expect(opened.model.window(for: Support.target).isExporting)
    #expect(opened.workspace.calls.isEmpty)
  }

  @Test("저장 패널을 취소하면 아무것도 쓰지 않고 돌아간다")
  func saveCancelledReturnsToIdle() async throws {
    let opened = await self.opened()
    let request = try self.saveTapped(opened)

    opened.model.saveLocationCancelled(request: request, in: Support.target)

    #expect(self.export(opened) == .idle)
    await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target)
    #expect(opened.workspace.calls.isEmpty)
    #expect(self.export(opened) == .idle)
  }

  @Test("저장은 저장…을 누른 순간의 줄을 쓴다 (그 뒤 도착한 줄은 없다)")
  func saveWritesTextTakenAtPress() async throws {
    let opened = await self.opened(["tick 1"])
    let request = try self.saveTapped(opened)
    opened.fake.append(["tick 2"], to: opened.session.id)
    await Support.waitUntil { opened.model.window(for: Support.target).visibleCount == 2 }

    await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target)

    #expect(self.export(opened) == .saved(Self.file))
    let text = try #require(opened.workspace.writtenFiles[Self.file])
    #expect(text.hasSuffix("----------------------------------------\ntick 1\n"))
    #expect(!text.contains("tick 2"))
    #expect(text.contains("줄: 보이는 1줄 / 전체 1줄\n"))
    #expect(DeviceLogText.saved(fileName: Self.file.lastPathComponent) == "저장했습니다: log.txt")
  }

  @Test("파일 쓰기 실패는 이유별 문구가 된다", arguments: [
    WorkspaceExportError.noPermission, .diskFull, .readOnlyVolume, .folderNotFound, .writeFailed,
  ])
  func saveFailureMapsReason(error: WorkspaceExportError) async throws {
    let opened = await self.opened()
    opened.workspace.setWriteError(error)
    let request = try self.saveTapped(opened)

    await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target)

    #expect(self.export(opened) == .failed(.save(error)))
    #expect(opened.workspace.writtenFiles.isEmpty)
    let texts = [WorkspaceExportError.noPermission, .diskFull, .readOnlyVolume, .folderNotFound, .writeFailed]
      .map { DeviceLogText.exportFailed(.save($0)) }
    #expect(Set(texts).count == texts.count)
    #expect(DeviceLogText.exportFailed(.save(.clipboardUnavailable)) == DeviceLogText.exportFailed(.save(.writeFailed)))
  }

  @Test("Finder 에서 보기는 저장한 파일을 보이고 저장 결과 줄은 그대로다")
  func revealSavedFile() async throws {
    let opened = await self.opened()
    let request = try self.saveTapped(opened)
    await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target)

    await opened.model.revealSavedFileTapped(in: Support.target)

    #expect(opened.workspace.calls.last == .revealInFinder(Self.file))
    #expect(self.export(opened) == .saved(Self.file))
  }

  @Test("저장한 파일이 옮겨졌거나 지워졌으면 찾지 못했다고 보인다")
  func revealMissingFileShowsReason() async throws {
    let opened = await self.opened()
    let request = try self.saveTapped(opened)
    await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target)
    opened.workspace.setRevealError(.fileNotFound)

    await opened.model.revealSavedFileTapped(in: Support.target)

    #expect(self.export(opened) == .failed(.revealedFileMissing))
    #expect(DeviceLogText.exportFailed(.revealedFileMissing) == "저장한 파일을 찾지 못했습니다. 옮겨졌거나 지워졌을 수 있습니다.")
  }

  @Test("저장 위치를 고르는 동안 창을 닫으면 잡아 둔 값을 버려 뒤에 온 결과로 쓰지 않는다")
  func closeWhileChoosingDropsSave() async throws {
    let opened = await self.opened()
    let request = try self.saveTapped(opened)

    opened.model.windowDisappeared(Support.target)
    #expect(self.export(opened) == .idle)
    await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target)

    #expect(opened.workspace.calls.isEmpty)
    opened.model.windowAppeared(Support.target)
    await Support.waitUntil { opened.model.window(for: Support.target).canExport }
    #expect(self.export(opened) == .idle)
  }

  @Test("파일을 쓰는 동안 창을 닫으면 쓰기는 끝나도 결과를 보이지 않는다")
  func closeWhileSavingHidesResult() async throws {
    let opened = await self.opened()
    opened.workspace.suspendExports()
    let request = try self.saveTapped(opened)
    let save = Task { await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target) }
    await Support.waitUntil { opened.workspace.calls.count == 1 }
    #expect(self.export(opened) == .saving)

    opened.model.windowDisappeared(Support.target)
    opened.workspace.resumeExports()
    await save.value

    #expect(opened.workspace.writtenFiles[Self.file] != nil)
    #expect(self.export(opened) == .idle)
    opened.model.windowAppeared(Support.target)
    #expect(self.export(opened) == .idle)
  }

  @Test("앞 저장 요청의 패널 결과는 무시하고 지금 요청의 결과만 받는다")
  func oldSaveRequestIgnored() async throws {
    let opened = await self.opened()
    let first = try self.saveTapped(opened)
    opened.model.saveLocationCancelled(request: first, in: Support.target)
    let second = try self.saveTapped(opened)
    #expect(first != second)

    await opened.model.saveLocationChosen(Self.file, request: first, in: Support.target)
    opened.model.saveLocationCancelled(request: first, in: Support.target)
    #expect(opened.workspace.calls.isEmpty)
    guard case .choosingLocation(_, second) = self.export(opened) else {
      Issue.record("지금 요청이 남아 있어야 한다: \(self.export(opened))")
      return
    }

    await opened.model.saveLocationChosen(Self.file, request: second, in: Support.target)
    #expect(self.export(opened) == .saved(Self.file))
  }

  @Test("저장·실패 결과는 세션·필터를 바꾸거나 일시정지·지우기를 해도 남는다")
  func exportStateSurvivesSessionAndFilterChange() async throws {
    let other = Support.summary("com.example.other", at: 0)
    let opened = await self.opened(sessions: [other])
    opened.fake.append(["other 1"], to: other.id)
    let request = try self.saveTapped(opened)
    await opened.model.saveLocationChosen(Self.file, request: request, in: Support.target)
    #expect(self.export(opened) == .saved(Self.file))

    opened.model.sessionSelected(other.id, in: Support.target)
    await Support.waitUntil { opened.model.window(for: Support.target).visibleCount == 1 }
    let condition = try #require(opened.model.window(for: Support.target).filter.conditions.first).id
    opened.model.conditionTextChanged(condition, "other", in: Support.target)
    opened.model.pauseTapped(in: Support.target)
    opened.model.clearTapped(in: Support.target)
    await Support.settle()
    #expect(self.export(opened) == .saved(Self.file))

    opened.model.pauseTapped(in: Support.target)
    opened.fake.append(["other 2"], to: other.id)
    await Support.waitUntil { opened.model.window(for: Support.target).visibleCount == 1 }
    opened.workspace.setCopyError(.clipboardUnavailable)
    await opened.model.copyTapped(in: Support.target)
    opened.model.conditionTextChanged(condition, "", in: Support.target)
    #expect(self.export(opened) == .failed(.copy(.clipboardUnavailable)))
  }
}

/// 테스트가 정할 때 깨는 기다리기 ("복사됨" 되돌리기). 깨우지 않은 기다리기는 남는다 (취소돼도 깨지 않는다).
final class ManualSleeper: Sendable {
  private struct State {
    var waiters: [CheckedContinuation<Void, any Error>?] = []
    var durations: [Duration] = []
  }

  private let state = Mutex(State())

  /// 지금까지 들어온 기다리기 수.
  var count: Int {
    self.state.withLock { $0.waiters.count }
  }

  var durations: [Duration] {
    self.state.withLock { $0.durations }
  }

  func sleep(_ duration: Duration) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      self.state.withLock { state in
        state.waiters.append(continuation)
        state.durations.append(duration)
      }
    }
  }

  /// `index` 번째 기다리기를 깨운다 (한 번만).
  func fire(_ index: Int) {
    let waiter = self.state.withLock { state -> CheckedContinuation<Void, any Error>? in
      guard state.waiters.indices.contains(index) else { return nil }
      defer { state.waiters[index] = nil }
      return state.waiters[index]
    }
    waiter?.resume()
  }
}
