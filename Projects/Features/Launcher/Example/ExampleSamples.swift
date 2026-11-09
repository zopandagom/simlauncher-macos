import Core
import DownloadInterface
import SimulatorInterface
import SimulatorTesting

/// "앱 실행…" 시트가 보일 설치된 앱 (번들 ID 는 예시 값).
enum ExampleInstalledApps {
  static let all: [InstalledApp] = [
    InstalledApp(bundleID: AppBundleID("com.example.sample")!, displayName: "Sample", version: "1.3.0", build: "42"),
    InstalledApp(bundleID: AppBundleID("com.example.rig")!, displayName: "Rig", version: nil, build: nil),
    InstalledApp(bundleID: AppBundleID("com.example.rig.debug")!, displayName: "Rig", version: nil, build: "7"),
  ]

  /// 모든 샘플 기기에 같은 목록을 둔다 (꺼진 기기는 Fake 가 켜기 전까지 `.deviceNotBooted` 로 실패한다).
  @MainActor
  static func install(on fake: SimulatorClientFake, apps: [InstalledApp] = all) {
    for device in DeviceInventory.sample.devices {
      fake.setInstalledApps(apps, on: device.id)
    }
  }
}

extension DownloadProgress {
  /// 48 MB 를 4.8 MB 씩 받는 진행 (Example·프리뷰가 행의 바이트·진행 막대를 보이게).
  static let example: [DownloadProgress] = (0 ... 10).map { (step: Int64) -> DownloadProgress in
    DownloadProgress(receivedBytes: step * 4_800_000, expectedBytes: 48_000_000)
  }
}
