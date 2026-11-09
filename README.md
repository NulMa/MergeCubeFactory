# Merge Cube Factory

Roblox 머지 타이쿤 게임. **[플레이하기](https://www.roblox.com/games/137640599837742/Merge-Cube-Factory)** (2026-10-19 공개)

> 큐브를 떨어뜨리고, 같은 등급끼리 합쳐 더 비싼 큐브를 만들고, 서버에서 가장 화려한 공장을 키운다.
> 배트로 큐브를 쳐서 콤보를 내고, 남의 공장에서 큐브를 훔쳐 오고, 몇 분마다 나타나는 보스 큐브를 함께 잡는다.

## 이 저장소가 보여주는 것

이 게임은 **AI 에이전트를 디렉팅해서** 만들었다. 코드는 Claude Code가 Roblox Studio MCP와 Open Cloud API를 통해 작성했고,
사람(저장소 주인)은 기획 방향, 의사 결정, 플레이테스트, 결과 검수를 맡았다.

그래서 이 저장소의 핵심은 코드보다 **에이전트가 따르는 기준 문서**다.

| 무엇을 | 어디서 |
|---|---|
| 에이전트 작업 규칙 (금지 사항, 키 사용 규칙, 검사 통과 의무) | [`CLAUDE.md`](CLAUDE.md) |
| 시장 조사 → 플랫폼 추천 규칙 → 수익화 설계 | [`docs/01`](docs/01_MARKET_RESEARCH.md) · [`02`](docs/02_PLATFORM_RULES.md) · [`03`](docs/03_MONETIZATION.md) |
| 컨셉 후보 10종 점수화, 가중치 민감도 검정 | [`docs/12`](docs/12_CONCEPT_EXPLORATION.md) |
| 가상 플레이어 4유형 × 60일 시뮬레이션 → 설계 결함 5건 발견 후 확정 | [`docs/13`](docs/13_SIMULATION.md), [`tools/pacing_sim.py`](tools/pacing_sim.py) |
| 서버 물리 병목 실측 → 데이터 지향(ECS + 간이 물리 + buffer 복제) 전환 | [`docs/27`](docs/27_DATA_CUBES.md) |
| 다음 프로젝트로 가져갈 판단 기준 | [`docs/28`](docs/28_LESSONS.md) |
| 결정 기록 (무엇을 왜 정했고 무엇을 되돌렸나) | [`docs/DECISIONS.md`](docs/DECISIONS.md) |

## 주요 시스템

머지 · 변이(Metallic/Neon/Rainbow/Galaxy…) · 도감 · 펫(확률 표시, 유료 랜덤 없음) · 보스 레이드 · 훔치기와 배트 ·
AI 플레이어(빈 서버 채우기, `[BOT]` 표시) · 출석 · 일일 퀘스트 · 이벤트 · 리버스 · 게임패스와 개발자 상품

- **서버 권한 경제**: 잔액과 보상은 서버만 바꾼다 (`EconomyService`). 영수증 처리는 멱등.
- **성능**: 트레이 하나 서버 물리 2.55ms를 실측하고 데이터 지향 구조로 전환, 데드 레코닝으로 스냅샷 전송량 −42%.

## 구조

```
CLAUDE.md          에이전트 규칙 (모든 세션에 적용)
docs/              기준 문서. 코드와 문서가 다르면 문서를 먼저 고친다
game/
  merge.project.json   Rojo 프로젝트
  src/core/            게임 무관 공용 코어 (저장·영수증·재화 원장·네트워크)
  src/merge/           이 게임 (server / client / shared)
  tests/               검사 (game/scripts/check.ps1)
  vendor/ProfileStore  서드파티 (라이선스 동봉)
tools/             기획 시뮬레이션 스크립트
```

원본 작업 저장소에는 같은 공용 코어로 만들고 있는 후속작과 에셋·홍보 자료가 함께 있다.
이 공개본은 Merge Cube Factory에 해당하는 코드와 문서만 옮긴 것이다 (아트 에셋 제외).
