import Testing
@testable import Core

struct LocationRouteTests {
  @Test("빈 줄·공백 줄은 건너뛰고 \\n·\\r\\n 으로 나눈다")
  func parsesLines() throws {
    let text = "37.5665, 126.9780\r\n\n   \n-33.8688,151.2093\n35.6812 139.7671\n"
    let waypoints = try LocationRoute.parseWaypoints(text).get()
    #expect(waypoints == [
      GeoCoordinate(latitude: 37.5665, longitude: 126.978),
      GeoCoordinate(latitude: -33.8688, longitude: 151.2093),
      GeoCoordinate(latitude: 35.6812, longitude: 139.7671),
    ].compactMap(\.self))
  }

  @Test("줄 문제는 원문 줄 번호(빈 줄 포함, 1부터)와 함께 처음 하나만")
  func lineProblem() {
    let text = "37.5665,126.9780\r\n\n37,5665\n95,0\n"
    #expect(LocationRoute.parseWaypoints(text) == .failure(.line(number: 3, .format)))
    #expect(LocationRoute.parseWaypoints("1,2\n\n0,181") == .failure(.line(number: 3, .longitudeOutOfRange)))
    #expect(LocationRoute.parseWaypoints("91,0\n1,2") == .failure(.line(number: 1, .latitudeOutOfRange)))
  }

  @Test("지점이 2개 미만이면 tooFewWaypoints", arguments: ["", "  \n\n", "1,2", "\n1,2\n"])
  func tooFew(text: String) {
    #expect(LocationRoute.parseWaypoints(text) == .failure(.tooFewWaypoints))
  }

  @Test("100개는 받고 101개는 tooManyWaypoints")
  func limit() throws {
    let hundred = (0 ..< 100).map { "\(Double($0) / 10), 1" }.joined(separator: "\n")
    #expect(try LocationRoute.parseWaypoints(hundred).get().count == LocationRoute.waypointLimit)
    #expect(LocationRoute.parseWaypoints(hundred + "\n1,1") == .failure(.tooManyWaypoints))
  }

  @Test("속도는 모두 0 보다 크고 기본은 걷기")
  func speeds() {
    #expect(LocationRouteSpeed.allCases.allSatisfy { $0.metersPerSecond > 0 })
    #expect(LocationRouteSpeed.default == .walking)
    #expect(LocationRouteSpeed.walking.metersPerSecond == 1.4)
  }
}
