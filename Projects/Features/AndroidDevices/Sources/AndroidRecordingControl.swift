import SwiftUI

/// 행의 녹화 진행 표시: 단계가 없으면 아무것도 없고("녹화" 는 ⋯ 메뉴 항목), 시작 중이면 작은 진행 표시와 "중지",
/// 녹화 중이면 빨간 점·경과 시간과 "중지", 저장 중이면 작은 진행 표시. 경과 시간은 SwiftUI 가 스스로 다시 그리는
/// `Text(_:style: .timer)` 라 Model 은 시작 시각만 갖는다.
struct AndroidRecordingControl: View {
  let phase: AndroidRecordingPhase?
  let stopTapped: () -> Void

  var body: some View {
    switch self.phase {
    case .none:
      EmptyView()
    case .starting:
      ProgressView()
        .controlSize(.small)
        .help(AndroidDevicesText.startingRecordingLabel)
        .accessibilityLabel(AndroidDevicesText.startingRecordingLabel)
      self.stopButton
    case let .recording(startedAt):
      HStack(spacing: 4) {
        Image(systemName: "record.circle.fill")
          .foregroundStyle(.red)
          .accessibilityLabel(AndroidDevicesText.recordingLabel)
        Text(startedAt, style: .timer)
          .monospacedDigit()
      }
      .fixedSize()
      .accessibilityElement(children: .combine)
      .help(AndroidDevicesText.recordingLabel)
      self.stopButton
    case .stopping:
      ProgressView()
        .controlSize(.small)
        .help(AndroidDevicesText.stoppingRecordingLabel)
        .accessibilityLabel(AndroidDevicesText.stoppingRecordingLabel)
    }
  }

  private var stopButton: some View {
    Button(AndroidDevicesText.stopRecordingButton, action: self.stopTapped)
      .fixedSize()
      .accessibilityLabel(AndroidDevicesText.stopRecordingAccessibilityLabel)
      .help(AndroidDevicesText.stopRecordingHelp)
  }
}
