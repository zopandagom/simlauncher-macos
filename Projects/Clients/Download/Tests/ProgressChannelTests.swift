import DownloadInterface
import Testing
@testable import DownloadImpl

/// 진행 값 통로. 값을 모두 넣고 닫은 뒤 읽어서, 소비자가 첫 값을 읽기 전에 delegate 가 값을 여럿 넣는 경우를
/// 시간에 기대지 않고 만든다.
struct ProgressChannelTests {
  @Test("읽기 전에 첫 값·중간 값들·마지막 값이 들어와도 첫 값과 마지막 값이 넘어간다")
  func firstSurvivesValuesBeforeReading() async {
    let channel = ProgressChannel()
    channel.yieldFirst(progress(0, 5000))
    channel.yield(progress(1000, 5000))
    channel.yield(progress(3000, 5000))
    channel.yield(progress(5000, 5000))
    channel.finish()
    let log = ProgressLog()

    await channel.forEach { log.append($0) }

    #expect(log.values == [progress(0, 5000), progress(5000, 5000)])
  }

  @Test("첫 값만 넣고 닫으면 첫 값 하나")
  func onlyFirst() async {
    let channel = ProgressChannel()
    channel.yieldFirst(progress(0, nil))
    channel.finish()
    let log = ProgressLog()

    await channel.forEach { log.append($0) }

    #expect(log.values == [progress(0, nil)])
  }

  @Test("값 없이 닫으면(응답 전 실패) 아무것도 넘기지 않고 돌아간다")
  func finishWithoutValues() async {
    let channel = ProgressChannel()
    channel.finish()
    let log = ProgressLog()

    await channel.forEach { log.append($0) }

    #expect(log.values.isEmpty)
  }

  @Test("넘기는 중에 Task 가 취소되면 남은 값은 넘기지 않는다")
  func stopsWhenCancelled() async {
    let channel = ProgressChannel()
    channel.yieldFirst(progress(0, 5000))
    channel.yield(progress(5000, 5000))
    channel.finish()
    let log = ProgressLog()

    await Task {
      await channel.forEach { value in
        log.append(value)
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }.value

    #expect(log.values == [progress(0, 5000)])
  }
}
