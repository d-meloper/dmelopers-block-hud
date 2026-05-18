# 기여 안내

[English](CONTRIBUTING.md) | 한국어

프로젝트 방향에 맞고 안전하게 검토할 수 있는 변경이라면 기여를 환영합니다.

## 시작 전에

큰 변경, 동작 변경, 패키징 변경, UI 변경은 먼저 이슈를 열어 방향을 맞춰주세요.

## 개발 메모

- Rainmeter `.ini`, `.inc` 파일은 UTF-16 LE BOM을 유지해야 합니다.
- Lua 런타임 코드는 Lua 5.1 호환을 유지해야 합니다.
- 로컬 런타임 상태, 로그, 백업, 생성 캐시, 개인 경로는 커밋하지 마세요.
- public-facing 문구는 사용자 친화적으로 유지하고, 내부 워크플로 용어는 쓰지 마세요.
- Korea와 Global 패키지는 같은 스킨 폴더 `DMeloper's Block HUD`에 설치됩니다.

## Pull Request

가능하면 아래 내용을 포함해주세요.

- 무엇이 바뀌었는지
- 왜 바꿨는지
- 어떻게 테스트했는지
- 시각 변경이 있으면 스크린샷 또는 녹화
- 패키징/업데이트 영향이 있으면 설명

## 공개 릴리즈 정책

GitHub Releases가 public version tag와 release notes를 담당합니다. ZIP과 RMSKIN asset 파일명은 variant만 담고 버전은 포함하지 않습니다.
