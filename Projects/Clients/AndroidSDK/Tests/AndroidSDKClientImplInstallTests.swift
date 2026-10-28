import AndroidSDKInterface
import CommandInterface
import CommandTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Testing
@testable import AndroidSDKImpl

/// `install(_:acceptedLicenses:progress:)`: 받은 파일은 테스트가 쓴 작은 바이트 열이고 체크섬 확인은 실제로 돈다.
struct AndroidSDKClientImplInstallTests {
  @Test("셋 다 설치: 순서·인자·빈 환경, 최종 경로에 트리, 스테이징·받은 폴더 지움, 기본 위치는 중간 폴더까지 만든다")
  func installsAll() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan()

    let (result, _) = await harness.install(plan)

    #expect(try result.get() == AndroidSDKInstallOutcome(
      installed: [.platformTools, .emulator, .systemImage],
      alreadyPresent: []
    ))
    for component in AndroidSDKComponent.allCases {
      let spec = PackageSpec(component)
      for file in spec.files {
        #expect(FileTree.read(spec.destination(in: harness.sdk).appending(path: file.name)) == file.contents)
      }
    }
    #expect(harness.stagingNames.isEmpty)
    #expect(Set(harness.removedDownloads.map(\.folder.lastPathComponent)) == [
      "SimLauncher-Download-0", "SimLauncher-Download-1", "SimLauncher-Download-2",
    ])
    #expect(harness.executables == [
      PackageZipCommand.zipinfo, PackageZipCommand.unzip,
      PackageZipCommand.zipinfo, PackageZipCommand.unzip,
      PackageZipCommand.zipinfo, PackageZipCommand.unzip,
    ])
    let unzip = try #require(harness.command.invocations.first { $0.executable == PackageZipCommand.unzip })
    #expect(unzip.environment.isEmpty)
    #expect(unzip.isCancellable)
    #expect(unzip.timeout == nil)
    #expect(unzip.arguments[0 ... 1] == ["-q", "-n"])
    #expect(unzip.arguments[2].hasSuffix("/source.zip"))
    #expect(unzip.arguments[3] == "-d")
    #expect(unzip.arguments[4].hasSuffix("/contents/"))
    let zipinfo = try #require(harness.command.invocations.first)
    #expect(zipinfo.arguments == ["-s", "-T", unzip.arguments[2]])
    #expect(!zipinfo.isCancellable)
    #expect(harness.download.calls.contains(.download(PackageSpec(.systemImage).url.url)))
  }

  @Test("진행: 패키지마다 받기 → 확인 → 풀기 → 마무리, 번호·전체 바이트, 마지막 completed == total")
  func progressOrder() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan([.platformTools, .emulator])
    let sizes = plan.packages.map(\.archive.size)

    let (_, progress) = await harness.install(plan)

    let total = sizes.reduce(0, +)
    #expect(progress.allSatisfy { $0.totalBytes == total && $0.packageCount == 2 })
    // Fake 받기 진행(0·512·1024 바이트)은 계획 크기까지로 자르고, 같은 값은 거른다.
    #expect(progress.map(\.phase) == [
      .downloading(received: 0, expected: sizes[0]),
      .downloading(received: sizes[0], expected: sizes[0]),
      .verifying, .extracting, .finishing,
      .downloading(received: 0, expected: sizes[1]),
      .downloading(received: sizes[1], expected: sizes[1]),
      .verifying, .extracting, .finishing,
    ])
    #expect(progress.map(\.packageIndex) == [1, 1, 1, 1, 1, 2, 2, 2, 2, 2])
    #expect(progress.map(\.completedBytes) == [
      0, sizes[0], sizes[0], sizes[0], sizes[0], sizes[0], total, total, total, total,
    ])
    #expect(progress.first?.packageIndex == 1)
    #expect(progress.last?.packageIndex == 2)
    #expect(progress.map(\.component).first == .platformTools)
    #expect(progress.last?.completedBytes == total)
    #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.completedBytes <= $1.completedBytes })
    #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 != $1 })
    #expect(progress.filter { !$0.canCancel }.map(\.phase) == [.finishing, .finishing])
  }

  @Test("시작 때 최종 경로에 무엇이든 있으면 건너뛰고(alreadyPresent) 전체 바이트에서 뺀다, 기존 내용 그대로")
  func skipsPresentAtStart() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    try FileTree.file(harness.sdk, "emulator/mine.txt", contents: "keep")
    let plan = try harness.plan()

    let (result, progress) = await harness.install(plan)

    #expect(try result.get() == AndroidSDKInstallOutcome(
      installed: [.platformTools, .systemImage],
      alreadyPresent: [.emulator]
    ))
    #expect(FileTree.names(harness.sdk.appending(path: "emulator")) == ["mine.txt"])
    let total = plan.packages[0].archive.size + plan.packages[2].archive.size
    #expect(progress.allSatisfy { $0.totalBytes == total })
    #expect(progress.last?.completedBytes == total)
    #expect(!harness.download.calls.contains(.download(PackageSpec(.emulator).url.url)))
  }

  @Test("설치 도중 다음 패키지의 최종 경로가 생기면 건너뛰고 전체에서 빼서 다시 알린다 (마지막 completed == total)")
  func skipsAppearedDuringInstall() async throws {
    let sdkBox = Recorder<URL>()
    let harness = try Harness(unzip: { spec, contents in
      try spec.extract(into: contents)
      if spec.component == .emulator, let sdk = sdkBox.all.first {
        try FileTree.directory(sdk, "system-images/android-37.0/google_apis/arm64-v8a")
      }
      return .success()
    })
    defer { harness.directory.remove() }
    sdkBox.append(harness.sdk)
    let plan = try harness.plan()

    let (result, progress) = await harness.install(plan)

    #expect(try result.get() == AndroidSDKInstallOutcome(
      installed: [.platformTools, .emulator],
      alreadyPresent: [.systemImage]
    ))
    let reduced = plan.packages[0].archive.size + plan.packages[1].archive.size
    #expect(progress.first?.totalBytes == plan.downloadBytes)
    #expect(progress.last?.totalBytes == reduced)
    #expect(progress.last?.completedBytes == reduced)
  }

  @Test("동의하지 않은 원문이 있으면 아무것도 하지 않고 licenseNotAccepted")
  func licenseNotAccepted() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan()

    let (result, progress) = await harness.install(plan, accepted: ["other"])

    #expect(result == .failure(.licenseNotAccepted))
    #expect(progress.isEmpty)
    #expect(harness.download.calls.isEmpty)
    #expect(!FileTree.exists(harness.sdk))
  }

  @Test("시작 때 provider 의 위치가 계획과 다르면 아무것도 하지 않고 sdkLocationChanged")
  func locationChanged() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan()
    harness.provider.set(.root(AndroidSDKRoot(url: harness.directory.child("other"), isDefault: false)))

    #expect(await harness.install(plan).result == .failure(.sdkLocationChanged))
    #expect(harness.download.calls.isEmpty)
    #expect(harness.provider.calls == 1)
  }

  @Test("설치 중 provider 가 바뀌어도 계획 위치에 끝까지 설치하고 provider 를 다시 부르지 않는다")
  func providerChangesDuringInstall() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan([.platformTools, .emulator])
    let provider = harness.provider
    let other = AndroidSDKRoot(url: harness.directory.child("other"), isDefault: false)

    let (result, _) = await harness.install(plan) { _ in provider.set(.root(other)) }

    #expect(try result.get().installed == [.platformTools, .emulator])
    #expect(FileTree.exists(harness.sdk.appending(path: "emulator/emulator")))
    #expect(!FileTree.exists(other.url))
    #expect(harness.provider.calls == 1)
  }

  @Test("크기·체크섬이 다르면 checksumMismatch, 받은 폴더를 지우고 SDK 에 아무것도 생기지 않는다")
  func checksumMismatch() async throws {
    for corrupt in [true, false] {
      let harness = try Harness()
      defer { harness.directory.remove() }
      let plan = try corrupt ? harness.plan([.platformTools], corrupt: [.platformTools]) : harness.plan(
        [.platformTools],
        wrongSize: [.platformTools]
      )

      let (result, progress) = await harness.install(plan)

      #expect(result == .failure(.checksumMismatch(.platformTools)))
      #expect(harness.removedDownloads.count == 1)
      #expect(!FileTree.exists(harness.sdk))
      #expect(harness.command.invocations.isEmpty)
      #expect(progress.last?.phase == .verifying)
    }
  }

  @Test("받기 실패는 구성 요소와 원인을 옮기고, 앞서 끝난 패키지는 남고 나머지는 하지 않는다")
  func downloadFailure() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan()
    harness.download.setDownloadResult(.failure(.connectionLost), for: PackageSpec(.emulator).url)

    #expect(await harness.install(plan).result == .failure(.download(.emulator, .connectionLost)))
    #expect(FileTree.exists(harness.sdk.appending(path: "platform-tools/adb")))
    #expect(!harness.download.calls.contains(.download(PackageSpec(.systemImage).url.url)))
    #expect(harness.stagingNames.isEmpty)
  }
}

extension PackageInstaller {
  /// 테스트용: 기본 위치가 없으면 만든다.
  static func prepareRootIsCreated(_ root: AndroidSDKRoot) -> Bool {
    (try? self.prepareRoot(root)) != nil && FileTree.exists(root.url)
  }
}

/// 직접 만든 zipinfo 출력.
enum ZipinfoText {
  static func listing(_ lines: [String]) -> String {
    (["Archive:  /x/source.zip", "Zip file size: 100 bytes, number of entries: \(lines.count)"] + lines
      + ["\(lines.count) files, 0 bytes uncompressed, 0 bytes compressed:  0.0%", ""]).joined(separator: "\n")
  }
}
