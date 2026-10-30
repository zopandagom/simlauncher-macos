import Testing
@testable import AndroidEmulatorImpl

/// 원격 셸 인용: 작은따옴표로 감싸고 `'` 만 `'\''` 로 바꾼다. 그 밖의 글자는 그대로 둔다.
struct ADBShellTests {
  @Test(
    "작은따옴표로 감싸고 안의 작은따옴표만 '\\'' 로 바꾼다",
    arguments: [
      ("", "''"),
      ("https://example.com/a?b=1&c=2", "'https://example.com/a?b=1&c=2'"),
      ("it's", #"'it'\''s'"#),
      ("''", #"''\'''\'''"#),
      ("$(id)", "'$(id)'"),
      ("a;id", "'a;id'"),
      ("a&b", "'a&b'"),
      (#""a""#, #"'"a"'"#),
      (#"a\b"#, #"'a\b'"#),
      ("*", "'*'"),
      ("myapp://한글 경로", "'myapp://한글 경로'"),
      ("a\nb", "'a\nb'"),
      ("com.a/.Main$Inner", "'com.a/.Main$Inner'"),
      (
        #"https://e.com/x?q=it's&$(id);"a" *"#,
        #"'https://e.com/x?q=it'\''s&$(id);"a" *'"#
      ),
    ]
  )
  func quote(raw: String, expected: String) {
    #expect(ADBShell.quote(raw) == expected)
  }
}
