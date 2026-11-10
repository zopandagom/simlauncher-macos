import AppKit
import Core
import ScreenLayoutInterface
import SwiftUI

/// 기기 하나의 레이아웃 창 내용: 위는 "새로 고침"·마지막 갱신 시각·앱 식별자, 그 아래 안내 배너(새로 고침 실패·시스템 화면),
/// 왼쪽 캔버스(스크린샷 + 뷰 테두리, 클릭해 고르기), 오른쪽 "이 위치의 뷰" 목록과 속성.
/// App 이 `WindowGroup(id: LayoutTarget.windowID, for: LayoutTarget.self)` 로 대상마다 창 하나를 띄운다.
/// 창을 닫으면(onDisappear) 읽기를 취소하고 스냅샷을 버린다.
public struct LayoutInspectorView: View {
  let model: LayoutInspectorModel
  let target: LayoutTarget
  /// 스냅샷 PNG 를 렌더마다 풀지 않게, 읽은 시각이 바뀔 때만 만든 이미지 (화면 일시 상태).
  @State private var decoded: DecodedImage?

  public init(model: LayoutInspectorModel, target: LayoutTarget) {
    self.model = model
    self.target = target
  }

  public var body: some View {
    let window = self.model.window(for: self.target)
    VStack(alignment: .leading, spacing: 0) {
      self.header(window)
        .padding(.horizontal)
        .padding(.vertical, 8)
      if let snapshot = window.snapshot {
        self.banners(window, snapshot: snapshot)
        Divider()
        self.content(window, snapshot: snapshot)
      } else {
        Divider()
        self.placeholder(window)
      }
    }
    .frame(minWidth: 760, minHeight: 520)
    .navigationTitle(self.model.title(for: self.target))
    .task(id: window.snapshot?.capturedAt) {
      self.decodeImage(window.snapshot)
    }
    .onAppear { self.model.windowAppeared(self.target) }
    .onDisappear { self.model.windowDisappeared(self.target) }
  }

  // MARK: - 위

  private func header(_ window: LayoutInspectorWindow) -> some View {
    HStack(spacing: 12) {
      Button {
        self.model.refreshTapped(in: self.target)
      } label: {
        Label(LayoutInspectorText.refreshButton, systemImage: "arrow.clockwise")
      }
      .disabled(window.isLoading)
      .help(LayoutInspectorText.refreshHelp)
      // 이전 화면이 있으면 그대로 두고 여기에 진행을 보인다. iOS 러너를 다시 준비하면(10분 유휴·기기 다시 켜기 뒤 등, 최대 1~2분)
      // 작은 진행 표시만으로는 오래 도는 이유를 모르므로 준비 문구도 함께 보인다.
      if window.isLoading, window.snapshot != nil {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(window.loading == .preparing ? LayoutInspectorText.preparing : LayoutInspectorText
            .reading)
        if window.loading == .preparing {
          Text(LayoutInspectorText.preparing)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(LayoutInspectorText.preparing)
        }
      }
      if let snapshot = window.snapshot {
        Text(LayoutInspectorText.lastUpdated(snapshot.capturedAt))
          .monospacedDigit()
          .foregroundStyle(.secondary)
        if let app = snapshot.appIdentifier {
          Text(verbatim: app)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
      }
      Spacer()
    }
  }

  @ViewBuilder
  private func banners(_ window: LayoutInspectorWindow, snapshot: LayoutSnapshot) -> some View {
    if let failure = window.failure {
      self.banner(
        "\(LayoutInspectorText.failure(failure)) \(LayoutInspectorText.lastScreen(snapshot.capturedAt))",
        systemImage: "exclamationmark.triangle.fill",
        tint: .orange
      )
    }
    if snapshot.isSystemScreen {
      self.banner(LayoutInspectorText.systemScreen, systemImage: "info.circle.fill", tint: .secondary)
    }
  }

  private func banner(_ text: String, systemImage: String, tint: Color) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
      Text(verbatim: text)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal)
    .padding(.vertical, 6)
    .background(tint.opacity(0.08))
  }

  // MARK: - 스냅샷 있음

  private func content(_ window: LayoutInspectorWindow, snapshot: LayoutSnapshot) -> some View {
    HSplitView {
      LayoutCanvas(
        image: self.decoded?.capturedAt == snapshot.capturedAt ? self.decoded?.image : nil,
        snapshot: snapshot,
        selectedID: window.pick?.selected,
        clicked: { [model = self.model, target = self.target] point in
          model.canvasClicked(at: point, in: target)
        }
      )
      .overlay {
        if snapshot.visibleNodes.isEmpty {
          Text(LayoutInspectorText.noNodes)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
      }
      .padding(12)
      .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
      VStack(alignment: .leading, spacing: 12) {
        LayoutNodeStackList(model: self.model, target: self.target)
          .frame(minHeight: 160)
        Divider()
        LayoutNodeDetail(
          node: self.model.selectedNode(for: self.target),
          unit: snapshot.unit,
          pixelsPerUnit: snapshot.pixelsPerUnit
        )
      }
      .padding(12)
      .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .top)
    }
  }

  // MARK: - 스냅샷 없음

  /// 처음 읽는 중이면 진행과 단계 문구, 처음 실패면 실패 문구와 "다시 시도".
  private func placeholder(_ window: LayoutInspectorWindow) -> some View {
    VStack(spacing: 12) {
      if let failure = window.failure, !window.isLoading {
        Image(systemName: "exclamationmark.triangle")
          .font(.largeTitle)
          .foregroundStyle(.orange)
        Text(LayoutInspectorText.failure(failure))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        Button(LayoutInspectorText.retryButton) {
          self.model.refreshTapped(in: self.target)
        }
      } else {
        ProgressView()
        Text(window.loading == .preparing ? LayoutInspectorText.preparing : LayoutInspectorText.reading)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - 이미지

  private func decodeImage(_ snapshot: LayoutSnapshot?) {
    guard let snapshot else {
      self.decoded = nil
      return
    }
    guard self.decoded?.capturedAt != snapshot.capturedAt else { return }
    self.decoded = NSImage(data: snapshot.screenshotPNG).map {
      DecodedImage(capturedAt: snapshot.capturedAt, image: $0)
    }
  }
}

/// 스냅샷 시각과 그 PNG 로 만든 이미지.
private struct DecodedImage {
  let capturedAt: Date
  let image: NSImage
}
