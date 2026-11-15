import Foundation
import Testing
@testable import Core

struct ReleaseRepositoryTests {
  @Test("기본 저장소의 버전 파일 주소와 다운로드 페이지 주소")
  func defaultRepository() throws {
    let repository = try #require(ReleaseRepository("zopandagom/simlauncher-macos"))
    #expect(repository.owner == "zopandagom")
    #expect(repository.name == "simlauncher-macos")
    #expect(
      repository.versionFileURL.url.absoluteString
        == "https://github.com/zopandagom/simlauncher-macos/releases/latest/download/SimLauncher-version.json"
    )
    #expect(
      repository.latestReleasePageURL.absoluteString
        == "https://github.com/zopandagom/simlauncher-macos/releases/latest"
    )
  }

  @Test("버전 파일 이름은 릴리스 쪽(scripts/release.sh·release.yml)과 같은 고정 이름")
  func versionFileName() {
    #expect(ReleaseRepository.versionFileName == "SimLauncher-version.json")
  }

  @Test("점이 든 이름의 버전 파일 주소")
  func versionFileURLWithDottedName() throws {
    let repository = try #require(ReleaseRepository("a/b.c"))
    #expect(
      repository.versionFileURL.url.absoluteString
        == "https://github.com/a/b.c/releases/latest/download/SimLauncher-version.json"
    )
  }

  @Test("이름의 . _ - 와 39자 소유자·100자 이름은 받는다")
  func acceptsLimits() {
    #expect(ReleaseRepository("a-b/x.y_z-1") != nil)
    #expect(ReleaseRepository(String(repeating: "a", count: 39) + "/" + String(repeating: "b", count: 100)) != nil)
    #expect(ReleaseRepository("owner/.github") != nil)
  }

  @Test(
    "거절: 빈 값·슬래시 없음·둘·공백·. ..·- 로 시작하는 소유자·40자 소유자·101자 이름·이름의 공백·한글·주소",
    arguments: [
      "", "owner", "owner/name/extra", "/name", "owner/", " owner/name", "owner/name ", "owner/..", "owner/.",
      "-owner/x", String(repeating: "a", count: 40) + "/x", "owner/" + String(repeating: "b", count: 101),
      "owner/na me", "owner/이름", "https://github.com/a/b", "own_er/x", "own.er/x",
    ]
  )
  func rejects(_ raw: String) {
    #expect(ReleaseRepository(raw) == nil)
  }
}
