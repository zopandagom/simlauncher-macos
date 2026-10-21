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
      // 이 화면이 보일 때만 구독되므로 기기 목록 화면에서는 다시 확인하지 않는다. 설치 중에는 Model 이 무시한다.
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
      if case .ready = status {
        self.readyHeader
      } else {
        self.header(title: SetupText.title(for: status), message: SetupText.message(for: status))
      }
      VStack(alignment: .leading, spacing: 10) {
        ForEach(self.model.steps) { step in
          SetupStepRow(step: step)
        }
      }
      self.actions(for: status)
      if case .ready = status, let defaultRuntime = self.defaultRuntimeToInstall {
        VStack(alignment: .leading, spacing: 4) {
          Text(SetupText.defaultRuntimeLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(verbatim: "iOS \(defaultRuntime.version)")
            .font(.callout)
        }
      }
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
      self.runtimeActions
    }
  }

  // MARK: - iOS 시뮬레이터 (Xcode 준비됨)

  /// 설치 중이면 설치 머리말, 설치 결과를 확인하는 중이면 진행 표시만, 아니면 런타임 상태의 제목·본문.
  @ViewBuilder
  private var readyHeader: some View {
    if self.model.runtimeInstall != nil {
      self.header(title: SetupText.installingTitle, message: SetupText.installingMessage)
    } else if self.model.isVerifyingInstall {
      self.progressHeader(SetupText.verifyingInstallTitle)
    } else if let message = SetupText.message(for: self.model.runtimeState) {
      self.header(title: SetupText.title(for: self.model.runtimeState), message: message)
    } else {
      self.progressHeader(SetupText.title(for: self.model.runtimeState))
    }
  }

  /// 설치할 기본 iOS. 설치되지 않았거나 준비 중·쓸 수 없을 때만 (설치 결과를 확인하는 중에는 보이지 않는다).
  private var defaultRuntimeToInstall: DefaultIOSRuntime? {
    guard !self.model.isVerifyingInstall, case let .checked(defaultRuntime, status) = self.model.runtimeState else {
      return nil
    }
    if case .installed = status {
      return nil
    }
    return defaultRuntime
  }

  @ViewBuilder
  private var runtimeActions: some View {
    if let install = self.model.runtimeInstall {
      SetupInstallPanel(model: self.model, install: install)
    } else if !self.model.isVerifyingInstall {
      let resultMessage = SetupText.installResultMessage(
        for: self.model.lastInstallResult,
        runtime: self.model.runtimeState
      )
      switch self.model.runtimeState {
      case .checked(_, .installed):
        VStack(alignment: .leading, spacing: 8) {
          if let resultMessage {
            self.resultLine(resultMessage)
          }
          self.finishButton(prominent: true)
        }
      case .checked(_, .notInstalled):
        VStack(alignment: .leading, spacing: 8) {
          Button(SetupText.installButton) {
            Task { await self.model.installRuntimeButtonTapped() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!self.model.canInstallRuntime)
          if let resultMessage {
            self.resultLine(resultMessage)
          }
          HStack(spacing: 8) {
            self.finishButton(prominent: false)
            self.note(SetupText.otherVersionNote)
          }
        }
      case .checked(_, .preparing), .checked(_, .unusable), .defaultRuntimeUnknown, .failed, .notChecked:
        VStack(alignment: .leading, spacing: 8) {
          if let resultMessage {
            self.resultLine(resultMessage)
          }
          self.finishButton(prominent: false)
        }
      }
    }
  }

  /// "기기 목록 열기". 기본 iOS 가 설치됨이면 강조, 아니면 일반 버튼.
  @ViewBuilder
  private func finishButton(prominent: Bool) -> some View {
    let button = Button(SetupText.finishButton) {
      self.model.doneButtonTapped()
    }
    .disabled(!self.model.canFinish)
    if prominent {
      button.buttonStyle(.borderedProminent)
    } else {
      button
    }
  }

  private func resultLine(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func progressHeader(_ title: String) -> some View {
    HStack(spacing: 12) {
      ProgressView()
        .controlSize(.small)
      Text(title)
        .font(.title2)
        .bold()
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

/// 진행 중인 설치: 단계 글자, 진행 막대(내려받기면 퍼센트), 숫자, 무진행 안내, 취소, 종료 대기 안내.
private struct SetupInstallPanel: View {
  let model: SetupModel
  let install: SetupRuntimeInstall

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(SetupText.phaseTitle(self.install.progress.phase))
        .bold()
      if self.install.progress.phase == .downloading, let fraction = self.install.progress.fractionCompleted {
        ProgressView(value: fraction)
      } else {
        ProgressView()
          .progressViewStyle(.linear)
      }
      if let detail = SetupText.downloadDetail(self.install.progress, locale: .current) {
        Text(verbatim: detail)
          .font(.callout)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      if self.install.isStalled {
        Label(SetupText.stalledNote, systemImage: "exclamationmark.triangle")
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 8) {
        if self.install.isCancelling {
          ProgressView()
            .controlSize(.small)
          Text(SetupText.cancellingLabel)
            .foregroundStyle(.secondary)
        } else {
          Button(SetupText.cancelInstallButton) {
            self.model.cancelInstallButtonTapped()
          }
          .disabled(!self.model.canCancelRuntimeInstall)
          if self.install.progress.phase == .installing {
            self.note(SetupText.cannotCancelNote)
          }
        }
      }
      if self.install.endsWithTermination {
        self.note(self.install.isCancelling ? SetupText.quitAfterCancelNote : SetupText.quitAfterInstallNote)
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
