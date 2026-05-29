# 기여 안내

[English](CONTRIBUTING.md) | 한국어

프로젝트 방향에 맞고 안전하게 검토할 수 있는 변경이라면 기여를 환영합니다.

이 공개 저장소는 스킨의 distribution surface이자 review surface입니다. 구현의 최종 원본 저장소가 아닙니다. 유지관리자가 준비한 릴리즈 브랜치는 실제 공개 릴리즈가 되기 전에 이곳에서 검토되며, 구현 변경은 먼저 유지관리자의 private development workspace에서 준비됩니다.

커뮤니티 Pull Request는 proposal 및 검토 입력으로 환영합니다. 커뮤니티 PR이 public `main`에 직접 merge될 것을 기대하지 말아 주세요. proposal이 채택되면 maintainer가 private development workspace에 반영하고 그곳에서 검증한 뒤, maintainer release approval PR 또는 maintainer metadata-only PR을 통해 이 공개 저장소에 다시 게시합니다.

## 시작 전에

큰 변경, 동작 변경, 패키징 변경, UI 변경은 먼저 이슈를 열어 방향을 맞춰주세요.

## 개발 메모

- Rainmeter `.ini`, `.inc` 파일은 UTF-16 LE BOM을 유지해야 합니다.
- Lua 런타임 코드는 Lua 5.1 호환을 유지해야 합니다.
- 빌드된 배포 트리, ZIP/RMSKIN release asset, 생성 캐시, 로컬 런타임 상태, 로그, 백업, 개인 경로는 커밋하지 마세요.
- public-facing 문구는 사용자 친화적으로 유지하고, private/internal workflow 용어는 피하되 PR 동작을 설명할 때 필요한 public branch/check policy 용어만 사용하세요.
- Korea와 Global 패키지는 같은 스킨 폴더 `DMeloper's Block HUD`에 설치됩니다.

## Pull Request

가능하면 아래 내용을 포함해주세요.

- 무엇이 바뀌었는지
- 왜 바꿨는지
- 어떻게 테스트했는지
- 시각 변경이 있으면 스크린샷 또는 녹화
- 패키징/업데이트 영향이 있으면 설명

커뮤니티 Pull Request는 제안으로 검토됩니다. 변경 사항이 채택되면 유지관리자가 비공개 개발 작업 공간에 반영한 뒤, 변경 유형에 따라 릴리즈 승인 Pull Request 또는 metadata-only Pull Request를 통해 이 공개 저장소에 다시 게시합니다.

유지관리자가 공식 릴리즈 승인 PR을 준비하는 경우가 아니라면 `publish/v<version>` 브랜치를 만들지 마세요. 유지관리자가 승인된 public metadata-only PR을 준비하는 경우가 아니라면 `publish/metadata-<topic>` 브랜치도 만들지 마세요. 이 브랜치 패턴들과 `public-export-approval` 검사는 일반 커뮤니티 PR 요구 사항이 아니라 maintainer publication 전용 도구입니다.

커뮤니티 PR에서 `public-export-approval` 검사가 실패할 수 있습니다. 릴리즈 브랜치가 아닌 변경은 의도적으로 보호되기 때문이며, 이 실패가 proposal 논의나 리뷰 자체를 막는 신호는 아닙니다.

릴리즈 승인 Pull Request는 maintainer 전용입니다. 이 PR은 `publish/v<version>` 브랜치를 사용하고, `public-export-approval` 검사를 통과해야 하며, 수동으로 merge된 뒤 GitHub Release tag와 assets가 확정됩니다.

Metadata-only Pull Request도 maintainer 전용입니다. 이 PR은 `publish/metadata-<topic>` 브랜치를 사용하고, 승인된 public metadata 경로만 변경할 수 있으며, GitHub Release tag나 assets를 생성하거나 업데이트하지 않습니다.

## 공개 릴리즈 정책

GitHub Releases가 public version tag와 release notes를 담당합니다. ZIP과 RMSKIN asset 파일명은 variant만 담고 버전은 포함하지 않습니다.
