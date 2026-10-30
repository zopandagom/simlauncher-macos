import Foundation

// catalog.json 하나를 앱과 같은 규칙(Core `BuildCatalog(jsonData:)` 와 크기 상한)으로 검사한다.
// schemaVersion 1(앱은 모두 iOS, platform 무시)과 2(앱마다 platform 필수)를 읽는다.
// Core 소스와 함께 컴파일해 쓴다: make catalog-check CATALOG=<catalog.json>
// 종료 코드: 0 통과, 1 규격 위반(크기 초과 포함), 2 사용법·파일 읽기 실패.
@main
enum ValidateCatalog {
  static func main() {
    let arguments = CommandLine.arguments
    guard arguments.count == 2 else {
      self.fail("사용: validate-catalog <catalog.json>", status: 2)
    }
    let path = arguments[1]
    guard let data = FileManager.default.contents(atPath: path) else {
      self.fail("파일을 읽지 못했습니다: \(path)", status: 2)
    }
    // BuildCatalog(jsonData:) 는 크기를 보지 않는다. 앱은 받을 때 상한을 넘으면 거절한다.
    guard data.count <= BuildCatalog.maxByteCount else {
      self.fail("크기 초과: \(data.count) 바이트 (상한 \(BuildCatalog.maxByteCount))", status: 1)
    }
    let catalog: BuildCatalog
    do {
      catalog = try BuildCatalog(jsonData: data)
    } catch {
      self.fail("규격 위반: \(error)", status: 1)
    }
    print("OK \(path): schemaVersion \(catalog.schemaVersion), 앱 \(catalog.apps.count)개")
    for app in catalog.apps {
      print("  \(app.id.rawValue) (\(app.platform.rawValue)): 버전 \(app.versions.count)개")
    }
  }

  private static func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
  }
}
