# RobloxGameFactory — 에이전트 규칙

## 기준
- 문서가 단일 기준이다: `docs/01~11`, `docs/DECISIONS.md`. 코드와 문서가 다르면 문서를 먼저 고치고(근거 포함) 코드를 맞춘다.
- 수치·정책 주장에는 `docs/SOURCES.md` 번호를 단다. 확인 못 한 것은 "미확인"으로 적는다. 추측을 사실처럼 쓰지 않는다.
- 플랫폼 정책 문서는 Creator Hub 원문(`https://create.roblox.com/docs/llms.txt`, 각 페이지 `.md`)을 우선한다.

## 금지
- 히트작 제목·썸네일·구조 복제, 밈 IP 사용 (docs/02 §2).
- 클라이언트가 잔액·보상을 결정하는 코드. 모든 증감은 `EconomyService` 경유 (docs/06).
- 유료 랜덤 상품, 오프라인 수익 무제한, 끝없는 피드 보상 (docs/02 §4).
- 스크립트가 든 서드파티 모델 삽입 (docs/08 §4).
- API 키·쿠키 커밋, 운영 유니버스에 승인 없는 게시·DataStore 쓰기 (docs/07 §4).

## 작업 방식
- Phase 0(현재)은 문서만. `game/`은 사용자가 `DECISIONS.md` Q1~Q3을 정한 뒤 생성한다.
- 외부 툴 버전은 공개 2주 이상 지난 안정판으로 고정(rokit.toml).
- 매 변경 후 `check.ps1` 통과(Phase 1부터). 실패를 숨기지 않는다.
- 에셋을 쓰면 `docs/08`과 `research/assets-*.md`에 id·작가·라이선스·확인일 기록.
- 리서치 갱신은 기존 표를 덮어쓰지 말고 `research/`에 날짜 스냅샷을 남긴다.

## Open Cloud API 키 사용 규칙 (2026-10-18)
- 키 위치: `.secrets/roblox_api_key` (git 무시, `.githooks/pre-commit`이 비밀값 커밋 차단 — 새로 clone하면 `git config core.hooksPath .githooks`). 환경변수 `ROBLOX_API_KEY`가 있으면 그쪽 우선.
- 키는 계정의 모든 체험에 권한이 있다(IP 제한 없음). **호출 대상은 테스트 유니버스 `10771520503` / 플레이스 `137640599837742`만.** Cubika(10771411112) 등 다른 유니버스는 읽기 호출도 하지 않는다.
- 키 값을 출력·로그·파일·커밋에 남기지 않는다. 요청 헤더에만 환경변수로 넣는다.
- 게임 패스·상품 생성, DataStore 삭제는 실행 전에 사용자에게 목록을 보여 주고 승인받는다.
