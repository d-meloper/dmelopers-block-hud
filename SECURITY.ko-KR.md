# 보안 정책

[English](SECURITY.md) | 한국어

## 지원되는 버전

별도 정책이 추가되지 않는 한, 보안 수정은 최신 public GitHub release에만 제공합니다.

## 취약점 제보 방법

보안 문제를 공개 GitHub Issue로 올리지 마세요.

이 저장소에서 GitHub private vulnerability reporting을 사용할 수 있다면 그 경로를 사용하세요. 사용할 수 없다면 maintainer의 공개 프로필/지원 경로를 통해 비공개 제보 채널을 요청해주세요.

## 어떤 것이 보안 이슈인가요?

아래와 같은 문제를 제보해주세요.

- 안전하지 않은 updater 동작
- 안전하지 않은 ZIP 또는 RMSKIN 압축 해제 동작
- 예상치 못한 명령 실행
- 안전하지 않은 PowerShell helper 동작
- 경로 순회(path traversal)
- 개인 로컬 경로나 민감한 로컬 데이터 노출
- plugin binary 신뢰 문제
- 다운로드/업데이트 경로가 비정상적으로 바뀌는 문제

## 보통 보안 이슈가 아닌 경우

아래는 일반 GitHub Issues로 제보해주세요.

- 시각 레이아웃 버그
- 설정 동작 버그
- 일반적인 Rainmeter 설정 실수
- 지원하지 않는 수동 파일 수정 때문에 생긴 문제
- 기능 요청

## 응답 기대치

유효한 보안 제보는 가능한 범위에서 검토합니다. 공개 disclosure는 수정 또는 완화 방안이 준비된 뒤에 진행해주세요.
