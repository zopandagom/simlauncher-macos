import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import Testing

struct AndroidSDKClientFakeTests {
  @Test("기본값: 상태 absentSample, 계획 sample, 설치는 진행 firstSample 뒤 계획 패키지 모두 설치, 호출 기록")
  func defaults() async throws {
    let fake = AndroidSDKClientFake()
    let plan = AndroidSDKInstallPlan.sample
    let accepted = Set(plan.licenses.map(\.fingerprint))

    #expect(await fake.checkSDK() == .absentSample)
    #expect(try await fake.fetchInstallPlan() == plan)
    let outcome = try await fake.install(plan, acceptedLicenses: accepted) { _ in }
    await fake.removeLeftovers()
    let candidate = await fake.inspectCandidateFolder(URL(filePath: "/x"))

    #expect(outcome == AndroidSDKInstallOutcome(
      installed: [.platformTools, .emulator, .systemImage],
      alreadyPresent: []
    ))
    #expect(candidate.candidate == .empty)
    #expect(candidate.writable)
    #expect(fake.calls == [
      .checkSDK, .fetchInstallPlan, .install(plan, acceptedLicenses: accepted), .removeLeftovers,
      .inspectCandidateFolder(URL(filePath: "/x")),
    ])
  }

  @Test("동의하지 않은 원문이 있으면 알림 없이 licenseNotAccepted")
  func licenseNotAccepted() async {
    let fake = AndroidSDKClientFake()
    let received = ProgressBox()
    do throws(AndroidSDKInstallError) {
      _ = try await fake.install(.sample, acceptedLicenses: []) { received.append($0) }
      Issue.record("던져야 한다")
    } catch {
      #expect(error == .licenseNotAccepted)
    }
    #expect(received.values.isEmpty)
  }

  @Test("멈춘 설치에 진행을 보내고, 취소하면 cancelled")
  func suspendedInstall() async throws {
    let fake = AndroidSDKClientFake()
    fake.suspendInstalls()
    let plan = AndroidSDKInstallPlan.sample
    let received = ProgressBox()
    let task = Task { () -> Result<AndroidSDKInstallOutcome, AndroidSDKInstallError> in
      do throws(AndroidSDKInstallError) {
        return try await .success(fake.install(plan, acceptedLicenses: Set(plan.licenses.map(\.fingerprint))) {
          received.append($0)
        })
      } catch {
        return Result<AndroidSDKInstallOutcome, AndroidSDKInstallError>.failure(error)
      }
    }

    while fake.suspendedInstallCount == 0 {
      try await Task.sleep(for: .milliseconds(5))
    }
    let finishing = AndroidSDKInstallProgress.sample(index: 3, phase: .finishing)
    await fake.sendInstallProgress(finishing)
    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(received.values == [.firstSample, finishing])
    #expect(fake.suspendedInstallCount == 0)
  }

  @Test("멈춘 계획 받기는 취소되면 cancelled, 재개하면 설정한 결과")
  func suspendedPlan() async throws {
    let fake = AndroidSDKClientFake()
    fake.setPlanResult(.failure(.download(.offline)))
    fake.suspendPlans()
    let first = Task { () -> AndroidSDKPlanError? in
      do throws(AndroidSDKPlanError) {
        _ = try await fake.fetchInstallPlan()
        return nil
      } catch {
        return error
      }
    }
    while fake.suspendedPlanCount == 0 {
      try await Task.sleep(for: .milliseconds(5))
    }
    first.cancel()
    #expect(await first.value == .cancelled)

    fake.resumePlans()
    do throws(AndroidSDKPlanError) {
      _ = try await fake.fetchInstallPlan()
      Issue.record("던져야 한다")
    } catch {
      #expect(error == .download(.offline))
    }
  }

  @Test("후보: 경로별 결과가 공통 결과보다 먼저")
  func candidates() async {
    let fake = AndroidSDKClientFake()
    fake.setCandidateResult((.otherContents, true))
    fake.setCandidateResult((.sdk, false), for: URL(filePath: "/sdk"))

    #expect(await fake.inspectCandidateFolder(URL(filePath: "/sdk")).candidate == .sdk)
    #expect(await fake.inspectCandidateFolder(URL(filePath: "/sdk")).writable == false)
    #expect(await fake.inspectCandidateFolder(URL(filePath: "/docs")).candidate == .otherContents)
  }

  @Test("샘플 값이 규칙과 맞는다: 계획 라이선스 지문·바이트, 진행 샘플")
  func samples() {
    #expect(AndroidSDKInstallPlan.sample.downloadBytes == 16_110_554 + 416_112_708 + 2_104_098_168)
    #expect(AndroidSDKInstallPlan.sample.licensesToConfirm(accepted: []).count == 2)
    #expect(AndroidSDKStatus.readySample.isReady)
    #expect(AndroidSDKStatus.absentSample.canInstallMissing)
    #expect(!AndroidSDKStatus.notWritableSample.canInstallMissing)
    let last = AndroidSDKInstallProgress.sample(index: 3, phase: .finishing)
    #expect(last.completedBytes == last.totalBytes)
    #expect(!last.canCancel)
  }
}

final class ProgressBox: Sendable {
  private let recorder = Recorder<AndroidSDKInstallProgress>()

  func append(_ value: AndroidSDKInstallProgress) {
    self.recorder.append(value)
  }

  var values: [AndroidSDKInstallProgress] {
    self.recorder.all
  }
}
