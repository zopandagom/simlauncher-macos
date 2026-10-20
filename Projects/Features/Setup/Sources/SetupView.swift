import AppKit
import Core
import DevEnvironmentInterface
import SwiftUI

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
/// 화면 문자열은 `SetupText` 가 이 모듈의 `Localizable.xcstrings` 에서 찾는다.
public struct SetupView: View {
  let model: SetupModel
  /// 지금 띄운 알림. 닫히는 동안 Model 값이 nil 이 되어도 글자가 비지 않도록 View 가 들고 있는다.
  @State private var presentedNotice: SetupNotice?

  public init(model: SetupModel) {
    self.model = model
  }

  public var body: some View {
    self.content
      .padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .task {
        await self.model.onAppear()
      }
      // macOS 에서는 다른 앱에 갔다 돌아와도 scenePhase 가 바뀌지 않아, 앱 활성화 알림으로 돌아옴을 안다.
      // 이 화면이 보일 때만 구독되므로 기기 목록 화면에서는 다시 확인하지 않는다.
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        Task { await self.model.appBecameActive() }
      }
      .onChange(of: self.model.notice, initial: true) { _, notice in
        if let notice {
          self.presentedNotice = notice
        }
      }
      .alert(
        SetupText.title(for: self.presentedNotice),
        isPresented: Binding(
          get: { self.model.notice != nil },
          set: { isPresented in
            if !isPresented {
              self.model.noticeDismissed()
            }
          }
        )
      ) {
        Button(SetupText.okButton) {}
      } message: {
        if let notice = self.presentedNotice {
          Text(SetupText.message(for: notice))
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    switch self.model.checkState {
    case .checking:
      VStack(spacing: 12) {
        ProgressView()
        Text(SetupText.checkingTitle)
          .foregroundStyle(.secondary)
      }
    case let .checked(status):
      self.statusContent(status)
    case let .failed(error):
      self.failedContent(error)
    }
  }

  private func statusContent(_ status: DevEnvironmentStatus) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      self.header(title: SetupText.title(for: status), message: SetupText.message(for: status))
      VStack(alignment: .leading, spacing: 10) {
        ForEach(self.model.steps) { step in
          SetupStepRow(step: step)
        }
      }
      self.actions(for: status)
      if let xcode = status.xcode {
        VStack(alignment: .leading, spacing: 4) {
          Text(SetupText.currentXcodeLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(verbatim: "Xcode \(xcode.version) · \(SetupText.xcodeLocation(xcode.bundleURL))")
            .font(.callout)
            .textSelection(.enabled)
        }
      }
      Divider()
      self.recheckRow
    }
    .frame(maxWidth: 520, alignment: .leading)
  }

  @ViewBuilder
  private func actions(for status: DevEnvironmentStatus) -> some View {
    switch status {
    case .xcodeNotInstalled, .commandLineToolsOnly:
      VStack(alignment: .leading, spacing: 8) {
        self.openAppStoreButton
        self.note(SetupText.autoRecheckNote)
      }
    case .licenseNotAccepted, .firstLaunchRequired:
      VStack(alignment: .leading, spacing: 8) {
        Button(SetupText.openXcodeButton) {
          Task { await self.model.openXcodeButtonTapped() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(self.model.isOpening)
        self.note(SetupText.adminPasswordNote)
        self.note(SetupText.autoRecheckNote)
      }
    case .ready:
      Button(SetupText.finishButton) {
        self.model.doneButtonTapped()
      }
      .buttonStyle(.borderedProminent)
      .disabled(!self.model.canFinish)
    }
  }

  private func failedContent(_ error: DevEnvironmentError) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      self.header(title: SetupText.failedTitle, message: SetupText.message(for: error))
      self.openAppStoreButton
      Divider()
      self.recheckRow
    }
    .frame(maxWidth: 520, alignment: .leading)
  }

  private func header(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.title2)
        .bold()
      Text(message)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var openAppStoreButton: some View {
    Button(SetupText.openAppStoreButton) {
      Task { await self.model.openAppStoreButtonTapped() }
    }
    .buttonStyle(.borderedProminent)
    .disabled(self.model.isOpening)
  }

  private var recheckRow: some View {
    HStack(spacing: 8) {
      Button(SetupText.recheckButton) {
        Task { await self.model.recheckButtonTapped() }
      }
      .disabled(!self.model.canRecheck)
      if self.model.isChecking {
        ProgressView()
          .controlSize(.small)
        Text(SetupText.recheckingLabel)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// 단계 한 줄: 끝난 단계는 체크, 지금 할 단계는 강조, 남은 단계는 흐리게.
private struct SetupStepRow: View {
  let step: SetupStep

  var body: some View {
    HStack(spacing: 8) {
      switch self.step.progress {
      case .done:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text(SetupText.stepTitle(self.step.kind))
      case .current:
        Image(systemName: "arrow.right.circle.fill")
          .foregroundStyle(.tint)
        Text(SetupText.stepTitle(self.step.kind))
          .bold()
      case .pending:
        Image(systemName: "circle")
          .foregroundStyle(.secondary)
        Text(SetupText.stepTitle(self.step.kind))
          .foregroundStyle(.secondary)
      }
    }
  }
}
