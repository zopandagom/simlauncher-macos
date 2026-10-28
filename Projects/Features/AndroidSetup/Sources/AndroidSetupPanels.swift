import AndroidSDKInterface
import Core
import SwiftUI

/// 라이선스 동의 시트: 동의 기록에 없는 원문마다 스크롤 글, 받을 크기·설치 후 어림·필요한 저장 공간, "동의하고 설치"·"취소".
/// 원문과 id 는 Google 저장소 XML 의 값 그대로 보인다. 시트를 닫거나 "취소" 하면 동의하지 않은 것이다.
struct AndroidSetupConsentSheet: View {
  let model: AndroidSetupModel
  let plan: AndroidSDKInstallPlan
  let licenses: [AndroidLicense]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(AndroidSetupText.consentTitle)
        .font(.title2)
        .bold()
      Text(AndroidSetupText.consentMessage)
        .fixedSize(horizontal: false, vertical: true)
      ForEach(self.licenses, id: \.fingerprint) { license in
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: license.id)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
          ScrollView {
            Text(verbatim: license.text)
              .font(.callout)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(8)
          }
          .frame(height: self.licenses.count > 1 ? 160 : 260)
          .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        }
      }
      self.sizes
      Text(AndroidSetupText.consentRecordNote)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button(AndroidSetupText.cancelButton, role: .cancel) {
          self.model.planCancelButtonTapped()
        }
        .keyboardShortcut(.cancelAction)
        Button(AndroidSetupText.acceptButton) {
          Task { await self.model.licenseAccepted() }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 560)
  }

  private var sizes: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
      GridRow {
        Text(AndroidSetupText.downloadSizeLabel)
          .foregroundStyle(.secondary)
        Text(verbatim: AndroidSetupText.bytes(self.plan.downloadBytes, locale: .current))
      }
      GridRow {
        Text(AndroidSetupText.installSizeLabel)
          .foregroundStyle(.secondary)
        Text(AndroidSetupText.approximateInstallSize(self.plan, locale: .current))
      }
      GridRow(alignment: .top) {
        Text(AndroidSetupText.requiredSpaceLabel)
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 2) {
          ForEach(AndroidSetupText.requiredSpaceLines(self.plan, locale: .current), id: \.self) { line in
            Text(line)
          }
        }
      }
    }
    .font(.callout)
  }
}

/// 진행 중인 설치: 설치 위치, 패키지 번호·이름, 단계, 그 패키지의 받은 바이트, 전체 막대·바이트, 취소, 종료 대기 안내.
struct AndroidSetupInstallPanel: View {
  let model: AndroidSetupModel
  let install: AndroidSetupInstall

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text(AndroidSetupText.installLocationLabel)
          .foregroundStyle(.secondary)
        Text(verbatim: AndroidSetupText.path(self.install.plan.root.url))
          .textSelection(.enabled)
      }
      .font(.callout)
      if let progress = self.install.progress {
        self.progressRows(progress)
      } else {
        Text(AndroidSetupText.startingLabel)
          .bold()
        ProgressView()
          .progressViewStyle(.linear)
      }
      HStack(spacing: 8) {
        if self.install.isCancelling {
          ProgressView()
            .controlSize(.small)
          Text(AndroidSetupText.cancellingLabel)
            .foregroundStyle(.secondary)
        } else {
          Button(AndroidSetupText.cancelButton) {
            self.model.cancelInstallButtonTapped()
          }
          .disabled(!self.model.canCancelInstall)
          if self.install.progress?.phase == .finishing {
            self.note(AndroidSetupText.cannotCancelNote)
          }
        }
      }
      if self.install.endsWithTermination {
        self
          .note(self.install.isCancelling ? AndroidSetupText.quitAfterCancelNote : AndroidSetupText
            .quitAfterInstallNote)
      }
    }
  }

  @ViewBuilder
  private func progressRows(_ progress: AndroidSDKInstallProgress) -> some View {
    Text(verbatim: AndroidSetupText.packageLine(progress))
      .bold()
    HStack(spacing: 8) {
      Text(AndroidSetupText.phaseTitle(progress.phase))
      if let bytes = AndroidSetupText.packageBytes(progress, locale: .current) {
        Text(verbatim: bytes)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .font(.callout)
    if let fraction = AndroidSetupText.totalFraction(progress) {
      ProgressView(value: fraction)
    } else {
      ProgressView()
        .progressViewStyle(.linear)
    }
    Text(verbatim: AndroidSetupText.totalBytes(progress, locale: .current))
      .font(.callout)
      .monospacedDigit()
      .foregroundStyle(.secondary)
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
