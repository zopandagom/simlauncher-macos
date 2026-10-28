import AndroidSDKInterface
import Core
import SwiftUI

/// SDK 위치 절: 경로·기본 위치 표시, 잠김·없음 안내, 위치 문제와 그 버튼.
struct AndroidSetupLocationSection: View {
  let model: AndroidSetupModel
  let status: AndroidSDKStatus
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(AndroidSetupText.locationLabel)
        .font(.caption)
        .foregroundStyle(.secondary)
      if let root = self.status.location.root {
        HStack(spacing: 6) {
          Text(verbatim: AndroidSetupText.path(root.url))
            .font(.callout)
            .textSelection(.enabled)
          if root.isDefault {
            Text(AndroidSetupText.defaultLocationNote)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      // 위치 문제가 있으면 문제 안내가 잠김(담당자 문의)을 함께 알린다.
      if self.model.isLocationLocked, !self.isUnusable {
        self.note(AndroidSetupText.lockedLocationNote)
      }
      switch self.status.location {
      case .absent:
        self.note(AndroidSetupText.absentLocationNote)
      case .folder:
        EmptyView()
      case let .unusable(_, problem):
        self.locationProblem(problem)
      }
    }
  }

  private var isUnusable: Bool {
    if case .unusable = self.status.location {
      return true
    }
    return false
  }

  private func locationProblem(_ problem: AndroidSDKLocationProblem) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(AndroidSetupText.locationTitle(for: problem), systemImage: "exclamationmark.triangle")
        .bold()
      Text(AndroidSetupText.locationMessage(for: problem, isLocked: self.model.isLocationLocked))
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        if problem == .notDirectory || problem == .brokenLink || problem == .unreadable {
          AndroidSetupRevealButton(model: self.model, target: .location)
        }
        if !self.model.isLocationLocked {
          Button(AndroidSetupText.openSettingsButton) {
            self.openSettings()
          }
        }
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

/// 설치를 막는 이유 한 줄과 그 버튼.
struct AndroidSetupBlockerRow: View {
  let model: AndroidSetupModel
  let blocker: AndroidSDKInstallBlocker
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(AndroidSetupText.blockerMessage(self.blocker), systemImage: "exclamationmark.triangle")
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        if case .notWritable = self.blocker {
          AndroidSetupRevealButton(model: self.model, target: .blockedFolder)
        }
        if !self.model.isLocationLocked {
          Button(AndroidSetupText.openSettingsButton) {
            self.openSettings()
          }
        }
      }
    }
  }
}

/// 구성 요소 한 줄: 상태 아이콘·이름·상태·자세히, 쓸 수 없으면 문제 안내와 Finder 버튼.
struct AndroidSetupComponentRow: View {
  let model: AndroidSetupModel
  let component: AndroidSDKComponent
  let status: AndroidSDKStatus

  var body: some View {
    let componentStatus = self.status.components[self.component] ?? .missing
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        self.statusIcon(componentStatus)
        Text(AndroidSetupText.componentTitle(self.component))
        Text(AndroidSetupText.statusLabel(componentStatus))
          .foregroundStyle(.secondary)
        if let detail = AndroidSetupText.componentDetail(
          self.component,
          status: componentStatus,
          installedSystemImages: self.status.installedSystemImages
        ) {
          Text(verbatim: detail)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      if case let .unusable(problem) = componentStatus {
        HStack(spacing: 8) {
          Text(AndroidSetupText.problemMessage(problem))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          AndroidSetupRevealButton(model: self.model, target: .component(self.component))
        }
        .padding(.leading, 24)
      }
    }
  }

  @ViewBuilder
  private func statusIcon(_ status: AndroidComponentStatus) -> some View {
    switch status {
    case .installed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .missing:
      Image(systemName: "circle")
        .foregroundStyle(.secondary)
    case .unusable:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }
}

/// "Finder 에서 보기" 버튼.
struct AndroidSetupRevealButton: View {
  let model: AndroidSetupModel
  let target: AndroidSetupRevealTarget

  var body: some View {
    Button(AndroidSetupText.revealButton) {
      Task { await self.model.revealButtonTapped(self.target) }
    }
  }
}
