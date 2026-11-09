# 07. 자동화 파이프라인

"자동화"의 범위: **에이전트가 기획 문서 → 코드 → 에셋 → 테스트 → 스테이징 게시 → 지표 리포트**까지 수행하고,
사람은 **돈·계정·정책·최종 공개** 관문만 승인한다.

## 1. 단계와 도구

| # | 단계 | 담당 | 도구 | 산출물 |
|---|---|---|---|---|
| 0 | 리서치 갱신 (주 1회) | 에이전트 | WebSearch, Creator Hub `llms.txt`, 차트 사이트 | `research/charts-YYYY-MM-DD.md`, 01·02 문서 갱신 PR |
| 1 | 설계 → 작업 분해 | 에이전트 | 이 문서들, `DECISIONS.md` | 작업 목록(마일스톤 단위) |
| 2 | 코드 생성 | 에이전트 | Claude Code + Rojo 파일 구조 | `game/src/**` |
| 3 | 정적 검사 | 자동 | `check.ps1`: luau-lsp, selene, stylua, lune 테스트, rojo build | PASS/FAIL |
| 4 | 에셋 탐색 | 에이전트 | Creator Store 공개 API(`tools/asset_search.mjs`), Studio MCP `search_asset` | `research/assets-*.md` 후보 |
| 5 | 에셋 생성/업로드 | 에이전트 | Python/Pillow 아이콘·텍스처, Studio MCP `generate_mesh`·`generate_material`·`generate_procedural_model`, Asphalt / Open Cloud Assets API | `AssetIds` |
| 6 | 플레이테스트 | 에이전트 | Studio MCP `start_stop_play`, `character_navigation`, `user_mouse_input`, `screen_capture`, `get_console_output`, `subagent(playtest)` | 테스트 리포트 + 스크린샷 |
| 7 | 헤드리스 테스트 | 자동 | Open Cloud **Luau Execution** API (게시된 테스트 플레이스에서 스크립트 실행) | 서버 로직 회귀 결과 |
| 8 | 스테이징 게시 | 자동 | Open Cloud Place Publishing `POST /cloud/v2/universes/{u}/places/{p}/versions` | **테스트 전용 유니버스**(비공개) |
| 9 | 운영 게시 | **사람 승인** 후 자동 | 같은 API, 운영 유니버스 | 버전 번호 |
| 10 | 지표 수집·리포트 | 에이전트 | Creator Analytics, Open Cloud Analytics, DataStore 조회 | 주간 KPI 리포트(09) |

### 핵심 API 메모 (공식 문서로 확인, 2026-10-16 갱신본) [S27][S28]
- 인증: `x-api-key` 헤더. 키는 Creator Dashboard → Credentials, **허용 IP 제한**, 최소 권한.
- Luau Execution: `POST /cloud/v2/universes/{u}/places/{p}/luau-execution-session-tasks`, scope `universe.place.luau-execution-session:write/read`, **키 소유자당 분당 5회** — 회귀 테스트는 묶어서 1회 실행.
- 데이터스토어(v2): `GET/PATCH/DELETE /cloud/v2/universes/{u}/data-stores/{store}/scopes/{scope}/entries/{id}`, 생성은 `POST .../entries?id=...`, PATCH는 `If-Match: etag`로 낙관적 동시성.
- 에셋 업로드: `POST /assets/v1/assets` (multipart). 오디오는 모더레이션 대기.
- 그 밖에 자동화 후보: Bans(`user-restrictions`), 알림(`notifications`), 실험(Experiments), 게임 설정(Configs), 에러 리포팅, 시크릿 스토어.

## 2. Studio MCP 사용 규칙
- Studio MCP는 Studio에 내장된 공식 MCP 서버다 [S29]. 연결된 Studio가 없으면(`list_roblox_studios` 빈 목록) 6단계는 건너뛰고 리포트에 "미실행"으로 남긴다.
- `execute_luau`는 Edit / Server / Client 데이터모델을 명시. 게시 플레이스(운영)를 연 Studio에는 **쓰기 작업 금지**.
- `insert_asset`은 08 §4 보안 규칙을 통과한 id만. 다른 소유자 인벤토리 에셋은 사용자 확인 후.
- `upload_image`는 이미지 전용. 오디오·메시는 Open Cloud/Asphalt.

## 3. 사람이 해야 하는 일 (관문)

| 관문 | 이유 | 시점 |
|---|---|---|
| 계정 ID 인증, 2단계 인증, Roblox Plus 구독 | Kids/Select 노출 자격, 오디오 업로드, DevEx [S8] | Phase 1 전 |
| Open Cloud API 키 발급 (테스트/운영 분리) | 비밀 정보 | Phase 1 전 |
| 성숙도 설문 | 법적 책임 | 첫 공개 전 |
| 패스·상품 생성과 가격 확정, 판매 켜기 | 돈 | 출시 전 |
| 운영 게시 승인, 공개 전환 | 되돌리기 어려움 | 매 릴리스 |
| 광고비 집행 | 돈 | 리텐션 검증 후 |
| 아이콘·썸네일 최종 선택 | PTR 최중요 신호, 브랜드 | 출시 전 |

## 4. 자동화 금지 사항
- 운영 DataStore 대량 쓰기/삭제를 승인 없이 실행하지 않는다.
- 키·쿠키를 저장소에 커밋하지 않는다(`.env`는 gitignore, 키 파일은 저장소 밖).
- `.ROBLOSECURITY` 쿠키 인증 사용 금지(공식 문서도 비권장).
- 서드파티 모델을 스크립트 포함 상태로 삽입하지 않는다.
- AI 생성 콘텐츠를 무검수로 대량 게시하지 않는다 — RDC 2026 Build 탭 이후 저품질 AI 게임 경쟁이 커지고, 비독창 감점 대상이다(02).

## 5. 에이전트 구성 (Phase 1에서 `.claude/`에 생성)
`00_ProjectSettings/agent-skill-guide.md`의 규모 기준(소규모: 에이전트 1~3, 스킬 3~5)을 따른다.

| 종류 | 이름 | 역할 |
|---|---|---|
| 에이전트 | `economy-guardian` | 모든 잔액 변경이 EconomyService 경유인지, ProcessReceipt 멱등, PolicyService 게이트 검사 |
| 에이전트 | `policy-reviewer` | 02 §4 금지 패턴, 메타데이터 규칙, 성숙도 영향 검토 |
| 스킬 | `/add-content` | Catalog에 큐브/변이/퀘스트 추가 → 테스트 → 도감 갱신 |
| 스킬 | `/playtest` | 빌드 → Studio MCP 플레이테스트 → 스크린샷 리포트 |
| 스킬 | `/research-refresh` | 0단계 실행, 01·02 갱신 |
| 스킬 | `/release` | 체크리스트(10) → 스테이징 게시 → 사람 승인 요청 |
| 훅 | PostToolUse(Edit `*.luau`) | stylua + selene 자동 실행 |
