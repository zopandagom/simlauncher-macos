import AppLogInterface
import Core
import SwiftUI

/// 기기 하나의 로그 창 내용: 위는 앱(세션) 고르기·상태·다시 실행, 가운데 필터와 줄 목록, 아래 줄 수와 일시정지·따라가기·지우기.
/// App 이 `WindowGroup(id: AppLogTarget.windowID, for: AppLogTarget.self)` 로 대상마다 창 하나를 띄운다.
/// 창을 닫으면(onDisappear) 줄과 필터 저장 시트만 버리고 앱과 받기는 계속된다.
public struct DeviceLogView: View {
  let model: DeviceLogModel
  let target: AppLogTarget

  public init(model: DeviceLogModel, target: AppLogTarget) {
    self.model = model
    self.target = target
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !self.model.hasReceivedSessions {
        // 세션 목록 첫 알림 전: "로그가 없습니다" 로 보이지 않게 비워 둔다.
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if self.model.sessions(for: self.target).isEmpty {
        self.emptyState
      } else {
        self.header
          .padding([.horizontal, .top])
          .padding(.bottom, 8)
        LogFilterBar(model: self.model, target: self.target)
          .padding(.horizontal)
          .padding(.bottom, 8)
        Divider()
        self.lineList
        Divider()
        self.footer
          .padding(.horizontal)
          .padding(.vertical, 8)
      }
    }
    .frame(minWidth: 640, minHeight: 360)
    .navigationTitle(self.model.title(for: self.target))
    .sheet(isPresented: Binding(
      get: { self.model.window(for: self.target).saveDraft != nil },
      set: { isPresented in
        if !isPresented {
          self.model.saveCancelled(in: self.target)
        }
      }
    )) {
      LogFilterSaveSheet(model: self.model, target: self.target)
    }
    .onAppear { self.model.windowAppeared(self.target) }
    .onDisappear { self.model.windowDisappeared(self.target) }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text(DeviceLogText.noSessions)
        .font(.title3)
      Text(DeviceLogText.noSessionsGuide)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - 위

  @ViewBuilder
  private var header: some View {
    let sessions = self.model.sessions(for: self.target)
    let selected = self.model.selectedSession(for: self.target)
    let window = self.model.window(for: self.target)
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 12) {
        if sessions.count > 1 {
          Picker(
            DeviceLogText.appPickerLabel,
            selection: Binding(
              get: { self.model.window(for: self.target).selectedSessionID },
              set: { id in
                if let id {
                  self.model.sessionSelected(id, in: self.target)
                }
              }
            )
          ) {
            ForEach(sessions) { session in
              Text(DeviceLogText.sessionLabel(
                appName: session.appName, startedAt: session.startedAt, state: session.state
              ))
              .tag(Optional(session.id))
            }
          }
          .fixedSize()
        } else if let selected {
          Text(selected.appName)
            .font(.headline)
        }
        if let selected {
          self.stateLabel(selected.state)
          if case .ended = selected.state {
            self.relaunchButton(window.relaunch)
          }
        }
        Spacer()
      }
      if case let .failed(error) = window.relaunch {
        Text(DeviceLogText.relaunchFailed(error, platform: self.target.platform))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func stateLabel(_ state: AppLogSessionState) -> some View {
    HStack(spacing: 4) {
      Image(systemName: state == .receiving ? "dot.radiowaves.left.and.right" : "stop.circle")
        .foregroundStyle(state == .receiving ? Color.green : Color.secondary)
      Text(DeviceLogText.state(state, platform: self.target.platform))
        .foregroundStyle(.secondary)
    }
  }

  private func relaunchButton(_ state: DeviceLogWindow.RelaunchState) -> some View {
    HStack(spacing: 6) {
      Button(DeviceLogText.relaunchButton) {
        Task { await self.model.relaunchTapped(in: self.target) }
      }
      .disabled(state == .running)
      .help(DeviceLogText.relaunchHelp)
      if state == .running {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  // MARK: - 가운데

  private var lineList: some View {
    let window = self.model.window(for: self.target)
    return LogLineTable(
      lines: window.visibleLines,
      generation: window.displayGeneration,
      isFollowing: window.isFollowing && !window.isPaused,
      scrolledAwayFromBottom: { [model = self.model, target = self.target] in
        model.scrolledAwayFromBottom(in: target)
      },
      scrolledToBottom: { [model = self.model, target = self.target] in model.scrolledToBottom(in: target) }
    )
    .overlay {
      // 거르기 결과를 기다리는 동안은 보이지 않는다 (`showsNoMatchingNotice`).
      if window.showsNoMatchingNotice {
        Text(DeviceLogText.noMatchingLines)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - 아래

  private var footer: some View {
    let window = self.model.window(for: self.target)
    return HStack(spacing: 12) {
      Text(DeviceLogText.lineCounts(visible: window.visibleCount, total: window.totalCount))
        .monospacedDigit()
        // 결과를 기다리는 동안의 "보이는 0줄" 은 숨긴다. 자리는 남겨 옆 표시가 밀리지 않게 한다.
        .opacity(window.hidesLineCounts ? 0 : 1)
      if let discarded = window.discardedNotice {
        Text(DeviceLogText.discarded(discarded))
          .foregroundStyle(.secondary)
      }
      if window.isPaused {
        Text(DeviceLogText.newWhilePaused(window.newWhilePaused))
          .monospacedDigit()
          .foregroundStyle(.orange)
      }
      Spacer()
      Button(window.isPaused ? DeviceLogText.resumeButton : DeviceLogText.pauseButton) {
        self.model.pauseTapped(in: self.target)
      }
      Toggle(
        DeviceLogText.followToggle,
        isOn: Binding(
          get: { self.model.window(for: self.target).isFollowing },
          set: { self.model.followChanged($0, in: self.target) }
        )
      )
      .toggleStyle(.checkbox)
      .help(DeviceLogText.followHelp)
      Button(DeviceLogText.clearButton) {
        self.model.clearTapped(in: self.target)
      }
      .help(DeviceLogText.clearHelp)
    }
  }
}
