import SwiftUI

@main
struct SampleApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

struct ContentView: View {
  private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "iphone")
        .font(.system(size: 48))
      Text(verbatim: "SimLauncher Sample")
        .font(.title2)
      Text(verbatim: "\(self.version) (\(self.build))")
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}
