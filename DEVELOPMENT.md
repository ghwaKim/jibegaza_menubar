# Jibegaza MenuBar 개발자 가이드

이 문서는 로컬 실행, 테스트용 앱 공유, 업데이트 서명 키 관리, GitHub Actions를 통한 정식 릴리스를 설명합니다. 앱 사용법은 [README.md](README.md)를 참고하세요.

개발은 회사 Mac에서 진행할 수 있지만, 개인 프로젝트의 **업데이트 개인키 생성·백업은 개인 소유의 신뢰할 수 있는 환경에서** 진행합니다. 정식 배포 시에는 GitHub Actions가 개인키를 읽어 서명합니다.

## 목차

- [개발 환경](#개발-환경)
- [프로젝트 구조](#프로젝트-구조)
- [로컬 실행](#로컬-실행)
- [자동 테스트](#자동-테스트)
- [개발·테스트용 앱 빌드와 공유](#개발테스트용-앱-빌드와-공유)
- [업데이트 구조](#업데이트-구조)
- [최초 설정: 키 생성과 GitHub 등록](#최초-설정-키-생성과-github-등록)
- [정식 릴리스: GitHub Actions](#정식-릴리스-github-actions)
- [개인 환경에서 수동 릴리스](#개인-환경에서-수동-릴리스)
- [업데이트 동작 검증](#업데이트-동작-검증)
- [문제 해결](#문제-해결)
- [문서와 리소스 관리](#문서와-리소스-관리)

## 개발 환경

| 항목 | 필요 조건 |
| --- | --- |
| 운영체제 | macOS. 앱의 최소 지원 버전은 macOS 13 |
| Swift | Swift 6.1 이상을 지원하는 도구 모음 (`Package.swift` 기준) |
| Apple 개발 도구 | Xcode 또는 호환되는 Command Line Tools |
| 셸 | zsh. 빌드 스크립트는 `zsh scripts/…`로 실행 |
| Python | Python 3. 배포 검증은 표준 라이브러리만 사용 |
| Git | 소스 관리 |
| GitHub CLI (`gh`) | 개인 환경의 수동 배포에 필요. 일반 실행·테스트에는 불필요 |
| 네트워크 | 최초 Swift 의존성 다운로드, flex 연결, 업데이트 확인 및 배포 시 필요 |

설치된 도구를 확인합니다.

```sh
xcode-select -p
swift --version
python3 --version
git --version
```

Command Line Tools가 없다면 `xcode-select --install`로 설치합니다. 모든 명령은 별도 설명이 없으면 저장소 루트에서 실행합니다.

```sh
git clone https://github.com/ghwaKim/jibegaza_menubar.git
cd jibegaza_menubar
swift build
```

첫 빌드에서 Sparkle 의존성과 바이너리를 내려받습니다. `Package.resolved`는 의존성 버전을 고정하는 파일이므로 소스와 함께 관리합니다. Xcode 프로젝트 파일 없이 Swift Package Manager로 실행·빌드할 수 있습니다.

## 프로젝트 구조

| 경로 | 역할 |
| --- | --- |
| `Package.swift`, `Package.resolved` | 실행 대상, 테스트 대상, Sparkle 의존성 |
| `Sources/TimeCalculatorMenuBar/TimeCalculatorMenuBarApp.swift` | 앱 진입점, 메뉴바·팝오버, 업데이트 시작 |
| `Sources/TimeCalculatorMenuBar/ContentView.swift` | 오늘·주간 화면 및 업데이트 버튼 |
| `Sources/TimeCalculatorMenuBar/TimeCalculatorViewModel.swift` | 화면 상태, 계산 연동, 설정 저장 |
| `Sources/TimeCalculatorMenuBar/TimeMath.swift`, `Models.swift` | 근무시간 계산 및 데이터 모델 |
| `Sources/TimeCalculatorMenuBar/Flex*.swift` | flex 로그인·조회·가져오기·동기화 |
| `Sources/TimeCalculatorMenuBar/AppUpdater.swift` | Sparkle 업데이트 컨트롤러 |
| `Tests/TimeCalculatorMenuBarTests/` | Swift Testing 기반 계산·flex 테스트 |
| `Resources/Info.plist` | 앱 식별자, 버전, 업데이트 URL과 공개키 |
| `Resources/AppIcon.icns` | 앱 번들 아이콘 |
| `scripts/test.sh` | 환경에 맞는 Swift 테스트 실행 |
| `scripts/build_app.sh` | `.app` 조립, 공유 ZIP 및 업데이트 파일 생성 |
| `scripts/setup_updates.sh` | 기존 키와 충돌하지 않는 공개키 설정 |
| `scripts/check_release.py` | Actions 배포 전 버전·빌드·기존 릴리스 검사 |
| `scripts/validate_update.py`, `scripts/verify_update.swift` | 번들·피드·다운로드 파일 일치 및 공개키 서명 검증 |
| `scripts/publish_release.sh` | 초안 릴리스 생성, 파일 업로드 후 공개 |
| `scripts/tests/` | 배포 검증 코드의 Python 테스트 |
| `.github/workflows/release.yml` | 수동 실행 방식의 정식 배포 워크플로 |
| `.build/`, `dist/` | 자동 생성 결과물. Git에서 제외 |

## 로컬 실행

빠르게 화면과 계산 동작을 확인하려면 다음 명령을 사용합니다.

```sh
swift run TimeCalculatorMenuBar
```

실행 대상이 하나이므로 `swift run`만 입력해도 됩니다. 앱은 메뉴바 앱이므로 일반 앱처럼 메인 창이나 Dock 아이콘이 나타나지 않을 수 있습니다. 화면 상단 메뉴바의 앱 아이콘을 눌러 팝오버를 엽니다. 터미널 실행을 끝내려면 `Control-C`를 누릅니다.

`swift run`은 실행 파일을 직접 실행합니다. `Resources/Info.plist`, 아이콘 등을 포함하는 배포용 `.app`을 조립하지 않으므로 앱 버전이 `알 수 없음`으로 표시되거나 업데이트 버튼이 비활성화될 수 있습니다. 아이콘·버전·실제 앱 실행·업데이트 연결은 다음의 테스트용 `.app`으로 확인합니다.

설치된 앱이나 다른 개발용 인스턴스가 실행 중이면 먼저 종료하세요. 테스트용 `.app`도 정식 앱과 같은 번들 식별자 `com.jibegaza.menubar`를 사용하므로 설정과 flex 로그인 상태를 공유할 수 있습니다. 테스트용 빌드가 별도 계정·저장 영역을 만드는 것은 아닙니다.

## 자동 테스트

### Swift 테스트

```sh
zsh scripts/test.sh
```

이 스크립트는 Command Line Tools 환경에서 Swift Testing을 찾을 수 있도록 프레임워크·링커 경로를 보완합니다. 직접 `swift test`가 실패한다면 먼저 위 스크립트를 사용하세요.

특정 테스트만 실행할 수도 있습니다. 추가 인수는 `swift test`로 전달됩니다.

```sh
zsh scripts/test.sh --filter WeeklyTests
zsh scripts/test.sh --filter TodayTests
zsh scripts/test.sh --filter FlexTests
```

### 배포 검증 테스트

```sh
python3 -m unittest discover -s scripts/tests -v
```

버전·빌드 역행, 기존 릴리스 중복, 피드와 번들 불일치, 파일 크기·다운로드 주소 오류 등을 확인합니다. 이 테스트는 GitHub에 실제 릴리스를 만들거나 개인키를 읽지 않습니다.

자동 테스트가 통과해도 로그인 화면, 메뉴바 표시, 실제 업데이트 설치·재실행은 앱에서 별도로 확인해야 합니다.

## 개발·테스트용 앱 빌드와 공유

### 빌드와 실행

```sh
zsh scripts/build_app.sh --test
open "dist/test/Jibegaza MenuBar.app"
```

옵션 없이 `zsh scripts/build_app.sh`를 실행해도 `--test`와 같습니다.

이 명령은 **release 최적화로 컴파일**하되, 테스트 공유용으로 패키징합니다. `--test`는 Swift의 debug 빌드를 의미하지 않습니다.

| 항목 | 테스트 빌드 동작 |
| --- | --- |
| 버전·빌드 번호 | `Resources/Info.plist`의 현재 값 유지 |
| 개인키 | 불필요 |
| 서명 | 앱에 ad-hoc 코드 서명 적용 |
| Sparkle | 프레임워크와 라이선스를 앱에 포함 |
| 업로드 | GitHub 업로드 없음 |
| 업데이트 파일 | `appcast.xml`과 서명된 업데이트 ZIP을 생성하지 않음 |

현재 소스가 버전 `1.3`이라면 다음 파일이 생성됩니다. ZIP 이름은 소스 버전에 따라 달라집니다.

```text
dist/test/
├── Jibegaza MenuBar.app
├── Jibegaza MenuBar v1.3.zip
└── 앱_실행_방법.png          # 원본 안내 이미지가 있을 때
```

공유 ZIP 안에는 `Jibegaza MenuBar Package/` 폴더가 있고, 그 안에 앱과 안내 이미지가 들어갑니다. 테스터에게는 이 ZIP을 전달하면 됩니다. 압축을 풀고 앱을 `/Applications` 등 쓰기 가능한 위치에 복사해 실행하도록 안내하세요. macOS 보안 경고의 처리 방법은 [사용자 가이드](README.md#앱-실행-방법)를 참고합니다.

테스트 빌드는 버전 번호가 그대로이므로 서로 다른 테스트 결과물을 구분하려면 전달 메시지에 커밋 SHA나 테스트 날짜를 적어두는 것이 좋습니다.

### 공개키를 넣은 테스트 앱

공개키가 아직 없다면 일반 기능은 테스트할 수 있지만 업데이트 버튼은 비활성화됩니다. 키 등록 후 공개키만 다음과 같이 설정할 수 있습니다.

```sh
zsh scripts/setup_updates.sh "실제 base64 공개키"
zsh scripts/build_app.sh --test
```

이 명령은 공개키만 `Info.plist`에 기록하며 개인키를 생성하거나 가져오지 않습니다. 기존 공개키와 다른 값을 넣으면 교체를 거부합니다. 공개키가 들어간 테스트 앱은 정식 배포와 같은 업데이트 URL을 사용하므로 실제 정식 업데이트를 발견할 수 있습니다. 정식 앱과 분리하려면 아래 testing 채널 명령으로 빌드해야 합니다.

## 업데이트 구조

```text
사용자 앱 → 최신 릴리스의 appcast.xml 확인
         → 새 빌드 발견 및 업데이트 창 안내
         → 해당 버전의 ZIP 다운로드
         → 앱에 포함된 공개키로 서명 검증
         → 설치 및 재실행
```

| 구성 | 현재 설정 |
| --- | --- |
| 업데이트 프레임워크 | Sparkle 2.10.1 |
| 피드 URL | `https://github.com/ghwaKim/jibegaza_menubar/releases/latest/download/appcast.xml` |
| 자동 확인 간격 | `SUScheduledCheckInterval = 3600`초 |
| 공개키 | `Info.plist`의 `SUPublicEDKey` |
| 업데이트 검증 | 압축 해제 전 서명 검증 활성화 |
| 파일 호스팅 | 공개 GitHub Releases |

자동 확인은 앱 실행 상태와 Sparkle의 일정에 따라 진행됩니다. 배포 직후 실시간 푸시하는 방식은 아니며, 사용자는 **업데이트 확인…**으로 직접 확인할 수 있습니다.

Sparkle의 업데이트 파일 서명과 Apple의 Developer ID 코드 서명·공증은 서로 다른 기능입니다. 현재 빌드는 ad-hoc 코드 서명을 사용하며 Apple 공증을 수행하지 않습니다. 앱스토어 등록, Apple 개발자 계정 결제, 공증은 이 배포 절차에 포함되어 있지 않습니다.

## 최초 설정: 키 생성과 GitHub 등록

### 1. 개인 환경에서 키 생성

아래 작업은 회사 Mac이 아닌 **개인 소유의 신뢰할 수 있는 macOS 환경**에서 진행합니다. 개인 환경에서 저장소를 준비한 뒤 의존성을 받아 도구를 확보합니다.

```sh
swift build
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.jibegaza.menubar
```

도구는 개인키를 그 Mac의 로그인 키체인에 저장하고 공개키를 출력합니다. 같은 계정의 기존 키가 있으면 재사용합니다. 공개키만 다시 확인하려면 다음 명령을 사용합니다.

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.jibegaza.menubar -p
```

키를 새 버전마다 만들지 않습니다. 최초 배포 때 사용한 키를 이후 업데이트에서도 유지합니다.

### 2. 개인키 내보내기와 백업

GitHub에 등록할 개인키 파일을 내보냅니다. 다음 경로는 개인 환경에서 사용할 예시이며 프로젝트 폴더 밖입니다.

```sh
umask 077
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.jibegaza.menubar \
  -x "$HOME/jibegaza-update.key"
```

이 파일의 내용 자체가 개인키입니다. 개인 비밀번호 관리 도구나 암호화된 개인 보관함에 백업하세요. GitHub Secret은 등록 후 원문을 다시 읽는 백업 수단으로 사용할 수 없습니다. 백업과 등록을 확인한 뒤 임시로 내보낸 파일은 개인 환경에서 정리합니다.

개인키는 Git·공유 ZIP·채팅·빌드 로그에 넣지 않습니다. 공개키는 소스와 앱에 포함해도 됩니다. 개인키가 사라지면 현재처럼 Developer ID 없이 운영하는 구성에서는 기존 사용자가 새 앱을 직접 설치해야 할 수 있습니다.

### 3. GitHub Secret과 Variable 등록

저장소의 [Settings → Secrets and variables → Actions](https://github.com/ghwaKim/jibegaza_menubar/settings/secrets/actions)에서 다음 값을 등록합니다.

| 탭 | 이름 | 값 |
| --- | --- | --- |
| Secrets | `SPARKLE_PRIVATE_KEY` | Sparkle에서 내보낸 개인키 파일의 내용 전체 |
| Variables | `SPARKLE_PUBLIC_KEY` | `generate_keys`가 출력한 base64 공개키 문자열 |

개인키는 파일 이름이나 경로가 아니라 **파일 내용**을 등록합니다. 공개키는 `<string>` 같은 XML 태그 없이 문자열만 등록합니다. 회사 Mac에 개인키를 가져오지 않도록 이 등록도 개인 환경에서 진행합니다.

개인 환경에 GitHub CLI가 있다면 개인키를 화면이나 명령 인수에 출력하지 않고 파일에서 등록할 수 있습니다.

```sh
gh auth login
gh secret set SPARKLE_PRIVATE_KEY \
  --repo ghwaKim/jibegaza_menubar < "$HOME/jibegaza-update.key"
gh variable set SPARKLE_PUBLIC_KEY \
  --repo ghwaKim/jibegaza_menubar --body "실제 base64 공개키"
```

### 4. 공개키를 소스에 고정

회사 Mac에는 공개키만 전달하면 됩니다.

```sh
zsh scripts/setup_updates.sh "실제 base64 공개키"
git diff -- Resources/Info.plist
```

`SUPublicEDKey`가 추가됐는지 확인하고 소스와 함께 커밋합니다. 이렇게 하면 Actions의 Variable이 다른 공개키로 변경됐을 때 기존 값과의 충돌을 감지할 수 있습니다. 공개키를 소스에 넣지 않아도 Actions가 빌드 시 주입하지만, 로컬 테스트 앱의 업데이트 기능과 키 변경 방지를 위해 커밋해두는 것을 권장합니다.

### 5. 워크플로 반영

앱 코드, 스크립트, `Package.resolved`, `.github/workflows/release.yml`을 기본 브랜치 `main`에 반영합니다. 수동 실행 버튼은 워크플로가 기본 브랜치에 있어야 표시됩니다. 개인키가 포함되지 않았는지 커밋할 파일 목록을 확인하세요.

## 테스트 업데이트 배포: Pre-release

업데이트 설치 과정까지 시험할 때는 Actions의 `channel`을 **testing**으로 선택합니다. 기본 선택도 testing이며, 정식 배포는 명시적으로 stable을 선택해야 합니다.

| 항목 | testing | stable |
| --- | --- | --- |
| 실행 브랜치 | 수동으로 선택한 브랜치 | 기본 브랜치 `main`만 |
| 공개 위치 | 고정 태그 `testing`의 Pre-release | `v1.4` 등의 정식 릴리스 |
| Latest 변경 | 하지 않음 | 정식 릴리스를 Latest로 지정 |
| 업데이트 피드 | `releases/download/testing/appcast.xml` | `releases/latest/download/appcast.xml` |
| 표시 버전 | 다음 정식 버전 유지 (예: 1.4) | 이전 정식 버전보다 증가 |
| 빌드 번호 | 배포할 때마다 증가 | 테스트 배포를 포함한 기존 빌드보다 증가 |

Pre-release는 공개 Releases 목록에서 볼 수 있습니다. 정식 Latest와 정식 앱의 업데이트 대상에서만 분리됩니다. 테스트 앱도 정식 앱과 번들 식별자·설정 저장 영역을 공유하므로 두 앱을 동시에 실행하지 마세요.

### 최초 테스트 앱 설치

공개키가 소스에 설정된 상태에서 다음 명령으로 업데이트 기능이 있는 앱을 만듭니다. 소스가 1.3 / 빌드 4라면 1.4 / 빌드 4가 생성됩니다. 개인키는 필요 없습니다.

```sh
RELEASE_CHANNEL=testing zsh scripts/build_app.sh --test
open dist/test
```

생성되는 파일은 `Jibegaza MenuBar v1.4-test-build4.zip`처럼 테스트 빌드를 표시합니다. 앱을 응용 프로그램 폴더로 옮겨 실행합니다. 이 명령은 소스 `Info.plist`를 변경하지 않고, 조립된 앱에만 테스트 피드를 적용합니다. 표시 버전·빌드를 직접 지정할 수도 있습니다.

```sh
RELEASE_CHANNEL=testing RELEASE_VERSION=1.4 RELEASE_BUILD_NUMBER=4 \
  zsh scripts/build_app.sh --test
```

이미 테스트 배포가 있다면 Actions에서 만들어진 `-test-build<번호>.zip`을 직접 받아 최초 앱으로 설치해도 됩니다. 업데이트 기능이 없는 기존 1.3 앱은 먼저 이 테스트 앱을 직접 설치해야 합니다.

### 다음 테스트 빌드 배포 및 업데이트 확인

1. 워크플로 변경을 `main`에 반영해 수동 실행 메뉴를 표시합니다. 테스트할 브랜치에도 새 워크플로·스크립트가 있어야 합니다.
2. **Actions → Release macOS app → Run workflow**에서 테스트할 브랜치를 선택합니다.
3. `channel`은 **testing**, 버전·빌드는 빈칸으로 실행합니다.
4. 소스가 1.3 / 4이고 기존 배포가 없다면 1.4 / 5로 결정됩니다. 두 번째 실행은 1.4 / 6입니다. 정식 1.4가 이미 배포됐다면 다음 테스트 버전은 1.5입니다.
5. 기존 테스트 앱에서 업데이트 확인을 누르고 새 빌드 설치·재실행을 확인합니다.

`testing` Pre-release는 매번 새로 생성하지 않고 재사용합니다. 각 빌드의 ZIP은 서로 다른 이름으로 추가하고, 업로드가 끝난 뒤 `appcast.xml`을 최신 테스트 빌드로 교체합니다. 예전 테스트 앱은 같은 주소에서 새 빌드를 찾습니다. 기존 ZIP은 이전 피드로 이미 다운로드를 시작한 앱을 위해 유지합니다.

`testing` 태그는 피드의 고정 주소용입니다. 매번 Git 태그를 옮기지 않으므로 테스트한 실제 소스 커밋은 릴리스 설명의 소스 링크와 Actions 실행 기록으로 확인합니다. 테스트 배포는 정식 릴리스의 설명을 생성하기 위한 기준으로 사용하지 않는 것이 좋습니다.

### 테스트 완료 후 정식 배포

검증한 변경을 `main`에 병합한 뒤 같은 워크플로에서 **channel: stable**을 선택합니다. 1.4 / 5, 1.4 / 6을 테스트했다면 정식은 1.4 / 7로 생성됩니다. 테스트 빌드 번호가 정식 번호보다 높아지는 상황을 방지하기 위해 빌드는 두 채널 전체에서 증가합니다.

정식 앱은 계속 정식 피드를 읽습니다. 테스트 앱은 테스트 피드를 유지하므로 정식 사용으로 돌아가려면 정식 ZIP을 직접 설치하세요. 채널을 자동으로 전환하는 기능은 없습니다.

## 정식 릴리스: GitHub Actions

### 버전과 빌드 번호

| 값 | 예시 | 규칙 |
| --- | --- | --- |
| 표시 버전 (`CFBundleShortVersionString`) | `1.4` | `major.minor` 형식. 소스 및 기존 정식 배포보다 큰 값 |
| 빌드 번호 (`CFBundleVersion`) | `5` | 양의 정수. 소스 및 기존 업데이트 피드의 빌드보다 큰 값 |
| GitHub 태그 | `v1.4` | 표시 버전에서 자동 결정. 기존 릴리스와 중복 불가 |

현재 소스의 값은 아래 명령으로 확인합니다.

```sh
plutil -extract CFBundleShortVersionString raw Resources/Info.plist
plutil -extract CFBundleVersion raw Resources/Info.plist
```

소스가 `1.3` / `4`이고 그 이후 배포가 없다면 다음 값은 `1.4` / `5`가 될 수 있습니다. Actions에서 두 입력란을 비우면 소스와 기존 Releases·업데이트 피드의 최댓값을 조회해 표시 버전의 minor와 빌드 번호를 각각 1 증가시킵니다. 예를 들어 최신 배포가 `1.4` / `5`이면 `1.5` / `6`으로 결정됩니다. 정식 버전 형식의 초안 태그는 예약된 번호로 취급합니다. testing Pre-release는 정식 표시 버전을 올리지 않으며, 빌드 번호만 두 채널 전체를 기준으로 증가합니다. 버전은 숫자 단위로 비교하므로 `1.10`은 `1.9`보다 큽니다. `1.4.1`, `v1.4`, `1.4-beta`는 워크플로 입력 형식에 맞지 않습니다.

### 실행 절차

1. 배포할 코드가 `main`에 반영됐는지 확인합니다.
2. [Actions](https://github.com/ghwaKim/jibegaza_menubar/actions)에서 **Release macOS app**을 선택합니다.
3. **Run workflow**를 누르고 브랜치 `main`을 선택합니다.
4. `channel`을 **stable**로 선택하고, `version`과 `build_number`는 **비워두고 실행**합니다. 특정 버전이 필요할 때만 해당 입력란을 채우며, 나머지는 자동으로 정합니다.
5. 실행 Summary 또는 **Determine and validate next release version** 단계에서 자동 결정된 버전·빌드를 확인하고 마지막 Releases 공개 성공 여부를 확인합니다.

정식 stable 배포는 이 저장소의 기본 브랜치에서 **수동 실행한 경우에만** 가능합니다. testing은 다른 브랜치에서도 수동 실행할 수 있습니다. 코드 푸시나 PR 생성만으로 배포하지 않습니다. 동시 배포는 순서대로 처리합니다.

### Actions 내부 처리

1. 선택한 커밋을 체크아웃합니다.
2. 기존 릴리스·피드와 소스의 값을 읽어 다음 버전·빌드를 자동 결정하고 중복·역행을 검사합니다. 결정된 값을 이후 빌드 단계와 실행 Summary에 전달합니다. 공개 저장소인지도 검사합니다.
3. `SPARKLE_PUBLIC_KEY`를 앱 설정에 적용합니다.
4. Python 배포 검증 테스트와 Swift 테스트를 실행합니다.
5. 개인키를 실행 환경의 `RUNNER_TEMP`에 접근 권한이 제한된 임시 파일로 기록합니다.
6. 앱 빌드, 프레임워크 포함, ad-hoc 서명, 업데이트 ZIP·피드 생성을 진행합니다.
7. 번들 정보·파일 크기·URL을 대조하고, 앱에 넣은 공개키로 ZIP 서명을 검증합니다.
8. 두 파일을 초안 릴리스에 업로드합니다.
9. 업로드가 끝나면 릴리스를 공개하고 최신 릴리스로 지정합니다. 서명 단계 종료 시 개인키 임시 파일을 삭제합니다.

개인키를 회사 Mac이나 앱 번들에 복사하지 않으며 키체인에 가져오지 않습니다. Releases 쓰기에는 워크플로의 `GITHUB_TOKEN`을 사용하므로 별도 개인 액세스 토큰은 필요 없습니다. 저장소·조직 정책에서 Actions 쓰기가 차단돼 있으면 해당 정책을 확인해야 합니다.

워크플로는 `macos-15` 실행 환경에서 빌드합니다. 현재 빌드 스크립트는 실행 환경의 기본 CPU 아키텍처를 사용하며 Universal Binary를 별도로 만들지 않습니다. Intel Mac까지 배포 범위를 넓힐 때는 별도 아키텍처 빌드와 실제 실행 검증이 필요합니다.

### 결과물과 소스 버전의 관계

버전 `1.4`, 빌드 `5`의 릴리스 예시입니다.

```text
GitHub Release v1.4
├── Jibegaza-MenuBar-1.4.zip
└── appcast.xml
```

업데이트 ZIP은 앱만 포함합니다. 로컬 빌드 시 생성되는 설치 안내 이미지 포함 공유 ZIP과 다릅니다. 현재 Actions는 위 두 파일만 업로드하며 공유 ZIP을 추가로 업로드하지 않습니다. GitHub가 자동으로 표시하는 Source code ZIP은 실행용 앱이 아닙니다.

Actions에서 자동 결정하거나 직접 지정한 버전·빌드는 해당 실행의 앱과 피드에 적용됩니다. 워크플로가 수정한 `Info.plist`를 소스에 커밋·푸시하지는 않습니다. 릴리스 태그는 체크아웃한 소스 커밋을 가리키므로, 나중에 같은 버전을 재현하려면 실행 Summary에 남은 버전·빌드도 함께 확인합니다. 다음 실행도 입력을 비워두면 실제 배포 이력을 기준으로 증가합니다. 소스 버전 파일을 매번 수동으로 갱신할 필요가 없습니다.

사용자 앱이 최신 릴리스의 `appcast.xml`을 읽으므로 업데이트 파일이 없는 릴리스를 최신으로 지정하지 않습니다. 별도 서버나 GitHub Pages는 필요 없습니다. 공개 저장소의 표준 GitHub 호스팅 실행 환경은 무료로 사용할 수 있으며, 비공개 저장소로 전환하면 현재 공개 다운로드 구조와 실행 비용 조건을 다시 검토해야 합니다.

## 개인 환경에서 수동 릴리스

기본 배포 경로는 Actions입니다. 아래 절차는 필요할 때 **개인키를 사용할 수 있는 개인 환경**에서만 사용하는 보조 경로입니다. `RELEASE_CHANNEL=stable`이 기본이며, testing을 지정하면 Pre-release 경로를 사용합니다. 회사 Mac에서는 실행하지 않습니다.

### 빌드

```sh
export SPARKLE_PRIVATE_KEY_FILE="/Volumes/개인저장소/jibegaza-update.key"
export RELEASE_VERSION="1.4"
export RELEASE_BUILD_NUMBER="5"

zsh scripts/setup_updates.sh "실제 base64 공개키"
gh auth login
python3 scripts/check_release.py
zsh scripts/test.sh
python3 -m unittest discover -s scripts/tests -v
zsh scripts/build_app.sh --release
```

예시 버전은 실제 배포 이력에 맞게 바꾸세요. `RELEASE_VERSION`과 `RELEASE_BUILD_NUMBER`를 생략하면 소스의 minor 버전과 빌드를 각각 1 증가시킵니다. 로컬 빌드 자체는 GitHub 배포 이력을 조회하지 않으므로 오래된 소스를 기준으로 번호를 자동 증가시키지 않도록 주의합니다.

릴리스 빌드는 성공하면 **로컬 `Resources/Info.plist`를 새 버전·빌드로 갱신**합니다. Actions의 수정은 임시 체크아웃에만 남지만, 로컬에서는 `git diff`에 표시됩니다.

```text
dist/
├── Jibegaza MenuBar.app
├── Jibegaza MenuBar v1.4.zip         # 안내 이미지 포함 공유용
└── updates/5/
    ├── Jibegaza-MenuBar-1.4.zip      # 앱만 포함하는 업데이트용
    └── appcast.xml
```

### 검증 후 공개

앞에서 로그인한 GitHub 계정을 사용합니다. 릴리스 스크립트는 현재 HEAD 커밋을 태그 대상으로 사용하므로, 버전 변경을 포함한 배포 소스가 GitHub에 커밋·푸시되어 있는지 확인합니다.

```sh
zsh scripts/publish_release.sh
```

앞의 절차처럼 `check_release.py`는 **릴리스 빌드 전에** 실행합니다. 빌드 후에는 소스 버전도 증가하므로 같은 입력으로 사전 검사를 다시 실행하면 거부됩니다. 빌드 후 결과물만 재검증하려면 다음 명령을 사용합니다.

```sh
python3 scripts/validate_update.py \
  "dist/updates/5/Jibegaza-MenuBar-1.4.zip" \
  "dist/updates/5/appcast.xml" \
  Resources/Info.plist
```

`publish_release.sh`도 결과물을 다시 검증하고 초안 생성·업로드·공개를 수행합니다. 같은 버전 릴리스를 덮어쓰지 않습니다. 공개된 버전의 앱 파일을 나중에 바꿔 끼우지 말고 수정 버전을 새 번호로 배포하세요.

## 업데이트 동작 검증

정식 운영 전에 실제 앱 두 버전 사이에서 다운로드·설치·재실행을 확인해야 합니다. 현재 자동 테스트는 이 전체 과정을 대신하지 않습니다.

1. 동일 공개키와 번들 식별자를 가진 낮은 빌드의 `.app`을 테스트 Mac에 설치합니다.
2. 저장할 근무 설정을 입력하고 현재 버전을 확인합니다.
3. 동일 개인키로 서명한 높은 버전·빌드를 Actions에서 배포합니다. 이 배포는 정식 채널의 사용자에게도 노출됩니다.
4. 이전 앱에서 **업데이트 확인…**을 눌러 새 버전이 표시되는지 확인합니다.
5. 다운로드·설치를 진행하고 재실행 뒤 버전 표시와 저장한 설정을 확인합니다.
6. 새 앱에서 다시 확인해 최신 상태로 안내되는지 확인합니다.

업데이트 기능이 전혀 없는 기존 버전에는 이 기능을 소급해서 넣을 수 없습니다. 사용자는 업데이트 지원 버전을 한 번 직접 설치해야 합니다. 정식 공개 전에 검증하려면 앞의 testing 채널을 사용합니다. testing 피드와 정식 피드는 분리되어 있습니다.

## 문제 해결

| 증상 | 확인 및 대응 |
| --- | --- |
| `swift run` 후 창이 안 보임 | 메뉴바 아이콘을 확인. 이 앱은 팝오버 중심으로 동작 |
| 버전이 `알 수 없음` 또는 업데이트 버튼 비활성 | `swift run` 대신 테스트 `.app` 사용. 번들 `Info.plist`에 공개키가 있는지 확인 |
| `No such module 'Testing'` 또는 테스트 링크 실패 | `zsh scripts/test.sh` 사용. 선택된 개발 도구와 Swift 버전 확인 |
| SDK·컴파일러 버전 불일치 | `xcode-select -p`, `swift --version` 확인 후 서로 호환되는 Xcode/Command Line Tools 사용 |
| `Another app build is in progress` | 다른 빌드가 끝날 때까지 대기. 비정상 종료로 `dist/.build-app.lock`만 남았다면 실행 중인 빌드가 없는지 확인 후 잠금 폴더 정리 |
| Actions에 Run workflow가 없음 | 워크플로가 `main`에 반영됐는지, Actions가 활성화돼 있는지 확인 |
| Actions 배포 작업이 skipped | stable은 기본 브랜치에서 실행. 다른 브랜치 테스트는 channel을 testing으로 선택 |
| 공개키 설정 실패 | Variable 누락·잘못된 base64·기존 소스 공개키와 충돌 여부 확인. 기존 키를 새 키로 덮어쓰지 않기 |
| 개인키 없음 | Secret 이름과 파일 내용 등록 여부 확인. 파일 경로를 Secret 값으로 등록하지 않기 |
| 공개키 서명 검증 실패 | 공개키와 개인키가 같은 쌍인지 확인. 원래 키를 복원하고 다시 빌드 |
| 직접 지정한 버전·빌드가 작거나 중복됨 | 입력란을 비워 자동 결정하거나 소스와 Releases·피드보다 큰 번호 선택 |
| `gh release create` 권한 오류 | Actions의 `contents: write` 및 저장소·조직 정책 확인. 로컬이면 `gh` 로그인 계정 권한 확인 |
| 업로드 실패 후 초안이 남음 | 원인 수정 후 파일과 초안 상태를 확인. 미공개 초안을 정리하거나 다른 새 버전으로 재시도. 같은 태그 초안도 중복 검사 대상 |
| 공개 직전 실패 후 태그가 남음 | 태그와 릴리스 상태를 확인한 뒤 새 버전 사용을 우선 검토. 사용 중인 공개 태그를 임의로 재지정하지 않기 |
| 피드 404 또는 새 버전이 안 보임 | 최신 정식 릴리스에 정확히 `appcast.xml`이 있는지 확인. 초기 배포 전에는 피드가 없을 수 있음 |
| 읽기 전용 위치에서 업데이트 실패 | 앱을 ZIP·디스크 이미지 밖의 쓰기 가능한 설치 위치로 복사 후 재실행 |
| Intel Mac에서 앱 실행 불가 | 현재 빌드의 아키텍처 확인. Sparkle 프레임워크가 두 아키텍처여도 앱 실행 파일이 Universal인 것은 아님 |

피드만 고치거나 앱 ZIP만 교체하면 서명·파일 크기가 어긋날 수 있습니다. 배포된 파일을 수정해야 한다면 새 버전·빌드를 만들어 함께 배포합니다. 개인키 분실·유출 시에는 임의로 새 키를 등록해 배포를 계속하지 말고 기존 사용자 앱의 신뢰 관계와 재설치 필요성을 먼저 확인합니다.

## 문서와 리소스 관리

- `README.md`: 설치·사용·사용자 업데이트 안내.
- `DEVELOPMENT.md`: 실행·테스트·키 설정·릴리스·장애 대응.
- 앱 아이콘을 바꾸려면 `zsh scripts/generate_icon.sh "/path/to/icon.png"`를 실행하고 생성된 `Resources/AppIcon.icns`와 아이콘 리소스 변경을 검토합니다.
- 빌드 스크립트, 버전 규칙, Secret 이름, 릴리스 파일 이름을 바꾸면 이 문서도 함께 갱신합니다.

참고: [Sparkle 설정](https://sparkle-project.org/documentation/), [Sparkle 업데이트 배포](https://sparkle-project.org/documentation/publishing/), [GitHub Actions Secret](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
