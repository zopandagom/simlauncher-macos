import AppLogInterface
import Core
import SwiftUI

/// 로그 창 아래 줄 끝의 "복사"·"저장…" 과 진행·"복사됨" 표시. 저장 패널(`LogSavePanel`)도 여기에 붙인다 (이 창의 NSWindow 에 시트).
/// 누를 수 없을 때(창 닫힘·세션 없음·보이는 줄 없음·전체 다시 거르기 기다림·필터 문제·다른 내보내기 진행 중) 두 버튼을 끈다.
struct LogExportButtons: View {
  let model: DeviceLogModel
  let target: AppLogTarget

  var body: some View {
    let window = self.model.window(for: self.target)
    HStack(spacing: 8) {
      switch window.export {
      case .copying, .saving:
        ProgressView()
          .controlSize(.small)
      case .copied:
        Label(DeviceLogText.copied, systemImage: "checkmark")
          .foregroundStyle(.green)
      case .idle, .choosingLocation, .saved, .failed:
        EmptyView()
      }
      Button(DeviceLogText.copyButton) {
        Task { await self.model.copyTapped(in: self.target) }
      }
      .help(DeviceLogText.copyHelp)
      Button(DeviceLogText.saveExportButton) {
        self.model.saveTapped(in: self.target)
      }
      .help(DeviceLogText.saveExportHelp)
    }
    .disabled(!window.canExport || window.isExporting)
    .background(
      LogSavePanel(
        request: Self.saveRequest(window.export),
        chosen: { [model = self.model, target = self.target] url, request in
          Task { await model.saveLocationChosen(url, request: request, in: target) }
        },
        cancelled: { [model = self.model, target = self.target] request in
          model.saveLocationCancelled(request: request, in: target)
        }
      )
    )
  }

  private static func saveRequest(_ phase: DeviceLogWindow.ExportPhase) -> LogSavePanel.Request? {
    guard case let .choosingLocation(name, request) = phase else { return nil }
    return LogSavePanel.Request(suggestedFileName: name, number: request)
  }
}

/// 아래 줄 밑의 내보내기 결과 한 줄: 저장 성공(파일 이름만, 경로 없음)과 "Finder 에서 보기", 또는 실패 이유. 없으면 비어 있다.
struct LogExportResultLine: View {
  let model: DeviceLogModel
  let target: AppLogTarget

  var body: some View {
    switch self.model.window(for: self.target).export {
    case let .saved(file):
      HStack(spacing: 8) {
        Text(DeviceLogText.saved(fileName: file.lastPathComponent))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Button(DeviceLogText.revealInFinder) {
          Task { await self.model.revealSavedFileTapped(in: self.target) }
        }
        Spacer()
      }
    case let .failed(failure):
      Text(DeviceLogText.exportFailed(failure))
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .idle, .copying, .copied, .choosingLocation, .saving:
      EmptyView()
    }
  }
}
