# 로컬·CI·Claude Code 가 모두 이 타깃을 쓴다. 명령을 바꿀 때는 여기만 고친다.
SHELL := /bin/bash
MISE := mise exec --

WORKSPACE := SimLauncher.xcworkspace
SCHEME ?= SimLauncher-Workspace
DESTINATION ?= platform=macOS,arch=$(shell uname -m)
RESULT_BUNDLE := build/TestResults.xcresult

# 카탈로그 예시 워크플로(.github/workflows/sample-catalog.yml)가 빌드하는 샘플 iOS 앱. 워크스페이스·make test 밖의 독립 Tuist 프로젝트
SAMPLE_DIR := Examples/SampleApp
SAMPLE_BUILD_NUMBER ?= 1
SAMPLE_DERIVED_DATA := build/SampleApp
SAMPLE_APP := $(SAMPLE_DERIVED_DATA)/Build/Products/Release-iphonesimulator/SampleApp.app
SAMPLE_ZIP := build/SampleApp.zip
# catalog.json 검증기: Core 소스와 함께 컴파일해 앱과 같은 규칙(schemaVersion 1·2)으로 검사한다. mise 없이 돈다 (워크플로 publish 잡)
CATALOG_VALIDATOR := build/validate-catalog
CATALOG_FIXTURES := .github/scripts/Fixtures
# make release 가 쓰는 공증 키체인 프로필 이름 (xcrun notarytool store-credentials 로 저장, docs/RELEASING.md)
NOTARY_PROFILE ?= simlauncher-notary

.PHONY: bootstrap generate project build test test-hooks lint format clean sample catalog-check catalog-test release

## 최초 1회: 도구 설치 + git 훅 연결
bootstrap:
	mise install
	git config core.hooksPath .githooks

## 워크스페이스를 생성하고 Xcode 로 연다 (사람이 쓰는 타깃)
generate:
	$(MISE) tuist generate

## 생성만 하고 열지 않는다. build·test·CI 는 이 타깃을 거친다
project:
	$(MISE) tuist generate --no-open

build: project
	set -o pipefail && $(MISE) xcodebuild build \
		-workspace $(WORKSPACE) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO | $(MISE) xcbeautify

test: project
	rm -rf $(RESULT_BUNDLE)
	$(MAKE) --no-print-directory test-hooks
	set -o pipefail && $(MISE) xcodebuild test \
		-workspace $(WORKSPACE) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-resultBundlePath $(RESULT_BUNDLE) \
		CODE_SIGNING_ALLOWED=NO | $(MISE) xcbeautify

## git 훅 동작 테스트: 임시 레포에서 main 커밋·머지 커밋·push 차단과 기능 브랜치 통과 확인 (make test 가 포함)
test-hooks:
	./.githooks/test-hooks.sh

# SwiftFormat 은 숨김 폴더(.github)를 순회하지 않아 그 안의 Swift 가 든 폴더를 경로로 넘긴다. SwiftLint 는 순회한다.
lint:
	$(MISE) swiftformat --lint . .github/scripts
	$(MISE) swiftlint lint --strict --quiet

format:
	$(MISE) swiftformat . .github/scripts
	$(MISE) swiftlint lint --fix --quiet

## 샘플 iOS 앱을 시뮬레이터용(arm64·x86_64, 서명 없음)으로 빌드해 build/SampleApp.zip 으로 묶는다. 빌드 번호: SAMPLE_BUILD_NUMBER=42 make sample
## zip 은 확장 속성·리소스 포크를 빼고 묶는다 (넣으면 .app 안에 ._ 파일이 생긴다)
sample:
	$(MISE) tuist generate --no-open --path $(SAMPLE_DIR)
	rm -rf $(SAMPLE_APP) $(SAMPLE_ZIP)
	set -o pipefail && $(MISE) xcodebuild build \
		-workspace $(SAMPLE_DIR)/SampleApp.xcworkspace -scheme SampleApp \
		-sdk iphonesimulator -configuration Release -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(SAMPLE_DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION=$(SAMPLE_BUILD_NUMBER) | $(MISE) xcbeautify
	ditto -c -k --norsrc --noextattr --noacl --keepParent $(SAMPLE_APP) $(SAMPLE_ZIP)

$(CATALOG_VALIDATOR): .github/scripts/validate-catalog.swift $(wildcard Projects/Shared/Core/Sources/*.swift)
	mkdir -p $(@D)
	xcrun swiftc -swift-version 6 -parse-as-library $^ -o $@

## catalog.json 하나를 앱과 같은 규칙으로 검사한다: make catalog-check CATALOG=<catalog.json>
catalog-check: $(CATALOG_VALIDATOR)
	@[[ -n "$(CATALOG)" ]] || { echo "사용: make catalog-check CATALOG=<catalog.json>" >&2; exit 2; }
	$(CATALOG_VALIDATOR) "$(CATALOG)"

## 샘플 카탈로그 생성기·검증기 회귀 테스트 (.github/scripts/Fixtures)
## 양성: 릴리스 목록 → 손으로 쓴 기대값(schemaVersion 2, iOS·Android 앱 둘)과 같고 검사 통과, 빈 목록이면 앱 둘·버전 0,
## schemaVersion 1 카탈로그(valid-v1.json)도 통과. 음성: 규격 위반 카탈로그마다 종료 1 과 그 문제
catalog-test: $(CATALOG_VALIDATOR)
	set -o pipefail && .github/scripts/sample-catalog.sh $(CATALOG_FIXTURES)/releases.json | jq -S . > build/catalog-test.json
	jq -S . $(CATALOG_FIXTURES)/expected-catalog.json | diff -u - build/catalog-test.json
	$(CATALOG_VALIDATOR) build/catalog-test.json
	.github/scripts/sample-catalog.sh $(CATALOG_FIXTURES)/releases-empty.json > build/catalog-test-empty.json
	jq -e '.apps | length == 2 and all(.[]; .versions | length == 0)' build/catalog-test-empty.json > /dev/null
	$(CATALOG_VALIDATOR) build/catalog-test-empty.json
	$(CATALOG_VALIDATOR) $(CATALOG_FIXTURES)/valid-v1.json
	for entry in invalid-http-url:invalidBuildURL invalid-duplicate-id:duplicateVersionID invalid-created-at:invalidCreatedAt \
		invalid-platform:unsupportedPlatform invalid-missing-platform:missingField; do \
		file=$(CATALOG_FIXTURES)/$${entry%%:*}.json; \
		output=$$($(CATALOG_VALIDATOR) "$$file" 2>&1); status=$$?; \
		if [[ $$status != 1 || $$output != *"$${entry#*:}"* ]]; then \
			echo "$$file: 종료 1 과 $${entry#*:} 를 기대했으나 종료 $$status: $$output" >&2; exit 1; \
		fi; \
		echo "거절 확인 $$file: $$output"; \
	done

## 배포 dmg: archive → Developer ID 내보내기 → (확인 뒤) 앱 공증·staple → dmg 서명·공증·staple → 검사. 준비·절차: docs/RELEASING.md
## 공증 자격 증명은 키체인 프로필 이름만 넘긴다: NOTARY_PROFILE=<이름> make release
release: project
	NOTARY_PROFILE=$(NOTARY_PROFILE) WORKSPACE=$(WORKSPACE) ./scripts/release.sh

clean:
	$(MISE) tuist clean
	rm -rf build *.xcworkspace
	find . -path ./.git -prune -o \( -name '*.xcodeproj' -o -name Derived \) -prune -exec rm -rf {} +
