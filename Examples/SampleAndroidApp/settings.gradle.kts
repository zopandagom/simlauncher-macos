// SimLauncher 카탈로그 예시 워크플로가 빌드하는 최소 Android 앱 (README.md). Gradle 래퍼는 두지 않는다:
// 워크플로가 setup-gradle 의 gradle-version 으로 버전을 고정한다 (래퍼 jar 는 검토할 수 없는 바이너리다).
pluginManagement {
  repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
  }
}

dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
  }
}

rootProject.name = "SampleAndroidApp"
