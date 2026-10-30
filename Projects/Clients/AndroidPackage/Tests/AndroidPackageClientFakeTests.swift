import AndroidPackageInterface
import AndroidPackageTesting
import Core
import Foundation
import Testing

struct AndroidPackageClientFakeTests {
  private static let url = URL(filePath: "/tmp/Picked.apk")

  @Test("기본은 .sample() 을 돌려주고 호출을 기록한다")
  func defaultSample() async throws {
    let fake = AndroidPackageClientFake()

    let info = try await fake.inspect(Self.url)

    #expect(info == .sample())
    #expect(info.packageName.rawValue == "com.example.sample")
    #expect(info.minSDK == .level(24))
    #expect(info.nativeABIs.isEmpty)
    #expect(fake.calls == [Self.url])
  }

  @Test("setResult 뒤에는 바꾼 값·에러를 쓴다")
  func setResult() async throws {
    let fake = AndroidPackageClientFake()
    fake.setResult(.failure(.appBundle))

    await #expect(throws: AndroidPackageError.appBundle) { try await fake.inspect(Self.url) }

    let x86 = AndroidPackageInfo.sample(nativeABIs: ["x86_64"])
    fake.setResult(.success(x86))
    #expect(try await fake.inspect(Self.url) == x86)
  }

  @Test("멈춘 검사는 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspend() async throws {
    let fake = AndroidPackageClientFake()
    fake.suspend()
    let task = Task { try await fake.inspect(Self.url) }
    while fake.calls.isEmpty {
      await Task.yield()
    }

    fake.setResult(.failure(.unsigned))
    fake.resume()

    await #expect(throws: AndroidPackageError.unsigned) { try await task.value }
    fake.setResult(.success(.sample()))
    #expect(try await fake.inspect(Self.url) == .sample())
  }

  @Test("setDelay 만큼 기다린 뒤 돌려준다")
  func delay() async throws {
    let fake = AndroidPackageClientFake()
    fake.setDelay(.milliseconds(50))
    let clock = ContinuousClock()

    let elapsed = try await clock.measure { _ = try await fake.inspect(Self.url) }

    #expect(elapsed >= .milliseconds(50))
  }

  @Test("sample 은 넘긴 값을 담는다")
  func sample() {
    let info = AndroidPackageInfo.sample(packageName: "org.example.b", minSDK: .unresolved, nativeABIs: ["arm64-v8a"])

    #expect(info.packageName.rawValue == "org.example.b")
    #expect(info.minSDK == .unresolved)
    #expect(info.nativeABIs == ["arm64-v8a"])
    #expect(info.location.path(percentEncoded: false) == "/tmp/Sample.apk")
  }
}
