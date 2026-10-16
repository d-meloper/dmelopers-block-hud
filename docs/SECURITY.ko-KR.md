# 보안 정책

[English](SECURITY.md) | 한국어

## 지원되는 버전

별도 정책이 추가되지 않는 한, 보안 수정은 최신 public GitHub release에만 제공합니다.

## 릴리스 및 업데이터 무결성

릴리스 노트에는 배포되는 각 ZIP 및 RMSKIN asset의 정확한 `SHA256 <hash> <asset>` 항목을 게시합니다. 공개 updater feed는 해당 릴리스 노트 항목과 GitHub release asset의 `sha256:` digest가 모두 존재하고 서로 일치할 때만 Korea 또는 Global updater ZIP의 hash를 게시합니다.

v1.4.1부터 네트워크 기반 update와 현재 버전 reset은 검증 실패 시 안전하게 중단됩니다.

- Repository, variant, 정확한 asset 이름과 SHA-256은 동일한 검증 metadata에서 가져와야 합니다.
- 다운로드한 ZIP은 staging 직후와 압축 해제 직전에 다시 검사합니다.
- Metadata나 package byte가 누락, 형식 오류, stale 또는 불일치 상태이면 압축 해제, compatibility 처리, 사용자 상태 변경 전에 작업을 중단합니다.

버전 1.4.0 및 이전 버전에는 이 runtime 검증이 소급 적용되지 않습니다. 기존 local package 및 import workflow는 compatibility 경로로 유지되며, network 또는 latest-update handoff로 호출되지 않는 한 공개 checksum을 요구하지 않습니다.

수동 다운로드 파일은 PowerShell에서 `Get-FileHash <file> -Algorithm SHA256`을 실행한 뒤 정확히 같은 파일 이름의 릴리스 노트 항목과 비교할 수 있습니다. Updater가 checksum 불일치를 알리면 우회하지 말고 version, variant, asset 이름, expected hash와 actual hash를 보존한 뒤 비공개로 제보해주세요.

SHA-256은 다운로드 손상, 잘못되었거나 교체된 asset, publication metadata drift를 감지합니다. Software의 악성 여부나 publisher 신원을 증명하지 않으며, 공격자가 artifact와 신뢰하는 checksum metadata를 모두 교체할 수 있는 상황까지 방어하지는 않습니다. 현재 Block HUD는 code signing 또는 TUF 방식의 signed metadata 보호를 제공한다고 주장하지 않습니다.

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
