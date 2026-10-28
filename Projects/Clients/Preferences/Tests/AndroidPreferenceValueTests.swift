import Core
import Foundation
import Testing
@testable import PreferencesImpl

struct AndroidPreferenceValueTests {
  @Test("SDK 위치: nil → absent, 문자열(빈 문자열·공백 포함) → path 그대로")
  func sdkPathStrings() {
    #expect(AndroidPreferenceValue.sdkPath(from: nil) == .absent)
    #expect(AndroidPreferenceValue.sdkPath(from: "/Volumes/Tools/SDK") == .path("/Volumes/Tools/SDK"))
    #expect(AndroidPreferenceValue.sdkPath(from: "") == .path(""))
    #expect(AndroidPreferenceValue.sdkPath(from: NSString(string: " ~/sdk ")) == .path(" ~/sdk "))
  }

  @Test("SDK 위치: 문자열이 아닌 값(숫자·배열·Data·사전)은 malformed")
  func sdkPathMalformed() {
    let values: [Any] = [NSNumber(value: 1), ["/a"], Data([1]), ["k": "v"]]
    for value in values {
      #expect(AndroidPreferenceValue.sdkPath(from: value) == .malformed)
    }
  }

  @Test("지문: 배열이면 문자열 항목만 순서대로")
  func licenseArray() {
    let value: Any = ["a", NSNumber(value: 1), "b", Data([1])] as [Any]
    #expect(AndroidPreferenceValue.strings(from: value) == ["a", "b"])
  }

  @Test("지문: 배열이 아니면(nil·문자열 하나·숫자·사전) 빈 목록")
  func licenseNotArray() {
    let values: [Any?] = [nil, "a", NSNumber(value: 1), ["k": "v"]]
    for value in values {
      #expect(AndroidPreferenceValue.strings(from: value).isEmpty)
    }
  }
}
