import SwiftUI

/// 행의 녹화 표시: 단계가 없으면 "녹화" 버튼, 시작 중이면 작은 진행 표시와 "중지", 녹화 중이면 빨간 점·경과 시간과 "중지",
/// 저장 중이면 작은 진행 표시. 경과 시간은 SwiftUI 가 스스로 다시 그리는 `Text(_:style: .timer)` 라 Model 은 시작 시각만 갖는다.
struct AndroidRecordingControl: View {
  let phase: AndroidRecordingPhase?
  let canStart: Bool
  /// 버튼이 막힌 이유 (툴팁). nil 이면 도움말을 보인다.
  let blockReason: String?
  let recordTapped: () -> Void
  let stopTapped: () -> Void

  var body: some View {
    switch self.phase {
    case .none:
      Button(AndroidDevicesText.recordButton, action: self.recordTapped)
        .disabled(!self.canStart)
        .help(self.blockReason ?? AndroidDevicesText.recordHelp)
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
  }
}
