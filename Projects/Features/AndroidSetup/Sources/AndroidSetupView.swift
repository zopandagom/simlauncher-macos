import AndroidSDKInterface
import AppKit
import Core
import SwiftUI

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
/// 화면 문자열은 `AndroidSetupText` 가 이 모듈의 `Localizable.xcstrings` 에서 찾는다.
/// 동의 시트는 View 상태가 아니라 Model 의 `plan`(`.awaitingConsent`)으로 띄우므로, 사이드바를 옮겼다 돌아와도 다시 보인다.
public struct AndroidSetupView: View {
  let model: AndroidSetupModel
  /// 지금 띄운 알림. 닫히는 동안 Model 값이 nil 이 되어도 글자가 비지 않도록 View 가 들고 있는다.
  @State private var presentedNotice: AndroidSetupNotice?

  public init(model: AndroidSetupModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      self.content
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task {
      await self.model.onAppear()
    }
    // macOS 에서는 다른 앱에 갔다 돌아와도 scenePhase 가 바뀌지 않아, 앱 활성화 알림으로 돌아옴을 안다.
    // 계획·설치 중에는 Model 이 무시한다.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task { await self.model.appBecameActive() }
    }
    .sheet(
      isPresented: Binding(
        get: { self.consent != nil },
        set: { isPresented in
          if !isPresented {
            self.model.planCancelButtonTapped()
          }
        }
      )
    ) {
      if let consent = self.consent {
        AndroidSetupConsentSheet(model: self.model, plan: consent.plan, licenses: consent.licenses)
      }
    }
    .onChange(of: self.model.notice, initial: true) { _, notice in
      if let notice {
        self.presentedNotice = notice
      }
    }
    .alert(
      AndroidSetupText.title(for: self.presentedNotice),
      isPresented: Binding(
        get: { self.model.notice != nil },
        set: { isPresented in
          if !isPresented {
            self.model.noticeDismissed()
          }
        }
      )
    ) {
      Button(AndroidSetupText.okButton) {}
    } message: {
      if let notice = self.presentedNotice {
        Text(AndroidSetupText.message(for: notice))
      }
    }
  }

  private var consent: (plan: AndroidSDKInstallPlan, licenses: [AndroidLicense])? {
    guard case let .awaitingConsent(plan, toConfirm) = self.model.plan else { return nil }
    return (plan, toConfirm)
  }

  @ViewBuilder
  private var content: some View {
    switch self.model.checkState {
    case .checking:
      HStack(spacing: 12) {
        ProgressView()
          .controlSize(.small)
        Text(AndroidSetupText.checkingTitle)
          .foregroundStyle(.secondary)
      }
    case let .checked(status):
      self.statusContent(status)
    }
  }

  private func statusContent(_ status: AndroidSDKStatus) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      self.headerView(status)
      AndroidSetupLocationSection(model: self.model, status: status)
      if case .unusable = status.location {
        EmptyView()
      } else {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(AndroidSDKComponent.allCases, id: \.self) { component in
            AndroidSetupComponentRow(model: self.model, component: component, status: status)
          }
        }
      }
      if let blocker = status.installBlocker {
        AndroidSetupBlockerRow(model: self.model, blocker: blocker)
      }
      self.actions(status)
      Divider()
      self.recheckRow
    }
    .frame(maxWidth: 560, alignment: .leading)
  }

  // MARK: - 머리말

  @ViewBuilder
  private func headerView(_ status: AndroidSDKStatus) -> some View {
    if self.model.install != nil {
      self.header(title: AndroidSetupText.installingTitle, message: AndroidSetupText.installingMessage)
    } else if self.model.isVerifyingInstall {
      HStack(spacing: 12) {
        ProgressView()
          .controlSize(.small)
        Text(AndroidSetupText.verifyingInstallTitle)
          .font(.title2)
          .bold()
      }
    } else if case .unusable = status.location {
      self.header(title: AndroidSetupText.locationProblemTitle, message: nil)
    } else if status.isReady {
      self.header(title: AndroidSetupText.readyTitle, message: AndroidSetupText.readyMessage)
    } else {
      self.header(title: AndroidSetupText.notReadyTitle, message: AndroidSetupText.notReadyMessage)
    }
  }

  private func header(title: String, message: String?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.title2)
        .bold()
      if let message {
        Text(message)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - 설치

  @ViewBuilder
  private func actions(_ status: AndroidSDKStatus) -> some View {
    if let install = self.model.install {
      AndroidSetupInstallPanel(model: self.model, install: install)
    } else if !self.model.isVerifyingInstall {
      VStack(alignment: .leading, spacing: 8) {
        if !status.isReady, status.location.root != nil, !self.isUnusable(status) {
          HStack(spacing: 8) {
            Button(AndroidSetupText.installButton) {
              Task { await self.model.installButtonTapped() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!self.model.canInstall)
            if self.model.plan == .fetching {
              ProgressView()
                .controlSize(.small)
              Text(AndroidSetupText.fetchingPlanLabel)
                .foregroundStyle(.secondary)
              Button(AndroidSetupText.cancelButton) {
                self.model.planCancelButtonTapped()
              }
            }
          }
        }
        if case let .failed(error) = self.model.plan, let message = AndroidSetupText.message(for: error) {
          self.resultLine(message)
        }
        if let result = self.model.lastResult {
          self.resultLine(AndroidSetupText.resultMessage(for: result))
          if result.locationChangedSince {
            self.note(AndroidSetupText.originalLocationNote(result.root))
          }
        }
        // 셋 다 설치됐으면 기기 목록으로 가는 길. 설치 직후에도 결과 줄을 볼 수 있게 자동으로 넘어가지 않는다.
        if status.isReady {
          Button(AndroidSetupText.deviceListButton) {
            self.model.deviceListButtonTapped()
          }
          .buttonStyle(.borderedProminent)
          .disabled(!self.model.canOpenDeviceList)
        }
      }
    }
  }

  private func isUnusable(_ status: AndroidSDKStatus) -> Bool {
    if case .unusable = status.location {
      return true
    }
    return false
  }

  private var recheckRow: some View {
    HStack(spacing: 8) {
      Button(AndroidSetupText.recheckButton) {
        Task { await self.model.recheckButtonTapped() }
      }
      .disabled(!self.model.canRecheck)
      if self.model.isChecking {
        ProgressView()
          .controlSize(.small)
        Text(AndroidSetupText.recheckingLabel)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func resultLine(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
