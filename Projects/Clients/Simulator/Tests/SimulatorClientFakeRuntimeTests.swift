import Core
import SimulatorInterface
import SimulatorTesting
import Testing

struct SimulatorClientFakeRuntimeTests {
  @Test("기본값은 샘플 목록이고 호출을 기록한다")
  func defaultSamples() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    let images = try await fake.fetchRuntimeImages()

    #expect(images == RuntimeImage.samples)
    #expect(images.map(\.platform) == [.iOS, .iOS, .watchOS])
    #expect(fake.calls == [.fetchRuntimeImages])
  }

  @Test("설정한 목록·에러를 돌려주고, 에러를 지우면 다시 목록이다")
  func configured() async throws {
    let fake = SimulatorClientFake()
    fake.setRuntimeImages([SampleRuntimeImage.iOS27])
    #expect(try await fake.fetchRuntimeImages() == [SampleRuntimeImage.iOS27])

    fake.setRuntimeImagesError(.unexpectedOutput)
    await #expect(throws: SimulatorError.unexpectedOutput) { try await fake.fetchRuntimeImages() }

    fake.setRuntimeImagesError(nil)
    fake.setRuntimeImages([])
    #expect(try await fake.fetchRuntimeImages().isEmpty)
    #expect(fake.calls == [.fetchRuntimeImages, .fetchRuntimeImages, .fetchRuntimeImages])
  }

  @Test("런타임 이미지 목록은 기기 목록과 따로다")
  func independentOfInventory() async throws {
    let fake = SimulatorClientFake(inventory: .noRuntime)
    fake.setFetchError(.developerToolsUnavailable)

    #expect(try await fake.fetchRuntimeImages() == RuntimeImage.samples)
  }
}
