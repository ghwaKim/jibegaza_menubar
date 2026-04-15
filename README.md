# Jibegaza MenuBar

macOS 메뉴바에서 바로 여는 시간 계산기

## 개발 실행

```bash
swift run
```

실행하면 Dock 아이콘 없이 메뉴바에 시계 아이콘이 생기고, 클릭하면 팝오버가 열립니다.

## 앱 번들 만들기

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

완료되면 아래 파일이 생성됩니다.

- `dist/Jibegaza MenuBar.app`
- `dist/Jibegaza MenuBar.zip`

앱 실행:

```bash
open "dist/Jibegaza MenuBar.app"
```

다른 사람과 공유:

- 보통 `dist/Jibegaza MenuBar.zip` 파일을 전달하면 됩니다.
- 아직 Apple notarization은 하지 않았기 때문에, 다른 Mac에서는 보안 경고가 뜰 수 있습니다.
- 그런 경우 상대방은 앱을 우클릭해서 `열기`를 한 번 눌러야 할 수 있습니다.

## 현재 포함된 기능

- 총 근무시간/ 남은 근무시간 선택
- 목표 근무 시간 선택
- 출근 시간 / 퇴근 시간 입력시 남은시간 자동 계산
- 총 근무 시간 계산
- 목표 시간을 채우는 예상 퇴근 시각 계산
- 입력값 자동 저장
