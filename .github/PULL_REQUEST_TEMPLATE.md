## Summary / 요약

Describe the change.

변경 내용을 적어주세요.

For community PRs, describe the proposal. Accepted changes are validated by the maintainer and published here through a release approval PR or metadata-only PR, depending on the change.

커뮤니티 PR이라면 proposal 내용을 적어주세요. 채택된 변경은 maintainer 검증 후 변경 유형에 따라 release approval PR 또는 metadata-only PR을 통해 이곳에 게시됩니다.

## PR Type / PR 유형

- [ ] Community proposal PR / 커뮤니티 proposal PR
- [ ] Maintainer release approval PR / maintainer release approval PR
- [ ] Maintainer metadata-only PR / maintainer metadata-only PR

Community PRs are reviewed as proposal and review input. They do not need to use a `publish/v<version>` branch, and a `public-export-approval` failure on a community branch may be an intentional guard rather than a review blocker.

커뮤니티 PR은 proposal 및 검토 입력으로 리뷰됩니다. `publish/v<version>` 브랜치를 사용할 필요가 없으며, 커뮤니티 브랜치의 `public-export-approval` 실패는 리뷰 차단 신호가 아니라 의도된 보호 장치일 수 있습니다.

Maintainer release approval PRs are maintainer-only. They use `publish/v<version>` and must pass `public-export-approval` before manual merge.

Maintainer release approval PR은 maintainer 전용입니다. `publish/v<version>`을 사용하고 수동 merge 전에 `public-export-approval`을 통과해야 합니다.

Maintainer metadata-only PRs are maintainer-only. They use `publish/metadata-<topic>`, may change only approved public metadata paths, and do not publish release tags or assets.

Maintainer metadata-only PR은 maintainer 전용입니다. `publish/metadata-<topic>`을 사용하고 승인된 public metadata 경로만 변경할 수 있으며 release tag나 asset을 배포하지 않습니다.

## Testing / 테스트

List what you tested.

어떤 테스트를 했는지 적어주세요.

## Screenshots / 스크린샷

Add screenshots or recordings for visual changes.

시각 변경이 있으면 스크린샷이나 녹화를 추가해주세요.

## Community PR Checklist / 커뮤니티 PR 체크리스트

- [ ] I described this PR as a proposal or review input.
- [ ] I did not include private paths, logs, backups, generated runtime state, generated caches, built distribution trees, or ZIP/RMSKIN release assets.
- [ ] Rainmeter `.ini` / `.inc` files remain UTF-16 LE with BOM if touched.
- [ ] Lua changes were syntax-checked if touched.
- [ ] Public-facing text avoids private/internal workflow terminology except necessary public branch/check policy terms.
- [ ] Packaging/update behavior is noted if affected.
- [ ] 이 PR을 proposal 또는 검토 입력으로 설명했습니다.
- [ ] 개인 경로, 로그, 백업, 생성된 런타임 상태, 생성 캐시, 빌드된 배포 트리, ZIP/RMSKIN release asset을 포함하지 않았습니다.
- [ ] Rainmeter `.ini` / `.inc` 파일을 수정했다면 UTF-16 LE BOM을 유지했습니다.
- [ ] Lua를 수정했다면 문법 검사를 했습니다.
- [ ] 공개 문구에 private/internal workflow 용어를 쓰지 않았으며, 필요한 public branch/check policy 용어만 사용했습니다.
- [ ] 패키징/업데이트 영향이 있다면 설명했습니다.

## Maintainer Release Approval Checklist / Maintainer 릴리즈 승인 체크리스트

- [ ] This is a maintainer-only release approval PR.
- [ ] The branch is `publish/v<version>`.
- [ ] The `public-export-approval` check passes.
- [ ] The diff contains only approved public distribution content and public metadata.
- [ ] 이 PR은 maintainer 전용 release approval PR입니다.
- [ ] 브랜치가 `publish/v<version>`입니다.
- [ ] `public-export-approval` 검사를 통과했습니다.
- [ ] diff에는 승인된 공개 배포 내용과 공개 metadata만 포함되어 있습니다.

## Maintainer Metadata-Only Checklist / Maintainer metadata-only 체크리스트

- [ ] This is a maintainer-only metadata PR.
- [ ] The branch is `publish/metadata-<topic>`.
- [ ] The `public-export-approval` check passes.
- [ ] The diff contains only approved public metadata paths.
- [ ] This PR does not publish a GitHub Release, tag, ZIP, RMSKIN, or runtime payload.
- [ ] 이 PR은 maintainer 전용 metadata PR입니다.
- [ ] 브랜치가 `publish/metadata-<topic>`입니다.
- [ ] `public-export-approval` 검사를 통과했습니다.
- [ ] diff에는 승인된 public metadata 경로만 포함되어 있습니다.
- [ ] 이 PR은 GitHub Release, tag, ZIP, RMSKIN, runtime payload를 배포하지 않습니다.
