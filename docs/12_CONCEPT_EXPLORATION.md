# 12. 컨셉 탐색 v2 — 후보 10종 (2026-10-17)

04의 후보 3개를 10개로 넓혔다. 평가 기준·가중치는 04 §1과 같다.
추가 조사 출처는 이 문서 끝. 수치는 제3자 추정이 섞여 있어 **장르 간 상대 비교**로만 쓴다.

## 1. 추가 조사 요약

| 장르 | 대표작과 최근 관측 | 수익 구조 | 메모 |
|---|---|---|---|
| 낚시 시뮬 | Fish It! 동접 27~37만(2026-03), 정점 270만 / Fisch 변형 서버 6만대 / Hooked! Q1 +9,019% [E2][E7] | 낚싯대·미끼 패스, 확정 상품 | Fisch는 공격적 과금 후 Fish It!으로 이동했다는 해석 [E2] → **과금 과잉은 장르 이탈 원인** |
| 타워 디펜스 | ASTD 동접 약 2.3만, Summer TDS 2.2~2.5만, Toilet TD 누적 62억 방문, Anime Defenders 월 $2~5M 추정 [E1][E3] | 유닛 가챠(유료 랜덤 다수), 배틀패스 | 상위작 수익이 **유료 랜덤**에 의존 → 우리 원칙과 충돌 |
| 펫·알 부화 | Pet Simulator 99 월 $4~8M, Adopt Me! 월 $5~10M 추정 [E3] | 알 가챠, 거래 | 동일 충돌. 거래 경제는 사기·운영 부담 |
| 경쟁 FPS | RIVALS 월 $8~15M 추정, 스킨·배틀패스 [E3] | 꾸미기 | "꾸미기가 왕" — 상위 수익의 주 동력 [E3]. 넷코드·밸런스 난도 높음 |
| 스포츠·물리 아레나 | Ball VS Ball, Volleyball Legends 상승세(2026-10) [E4] | 꾸미기, 능력 | 신규 상승 장르. 물리 동기화가 핵심 기술 |
| 키우기(실시간) | Grow a Garden 2가 2026 최대 브레이크아웃 [E5], 원작 대비 지속력 약함 [01] | 씨앗·시간 단축 | 클론 과잉 |
| 훔치기·방어 | Steal An Egg 2026-07 최대 동접 [01] | 시간 단축·보호 | 정책 개입·소송 리스크 [02] |

## 2. 후보와 점수 (가중 합계 100)

| ID | 컨셉 | 수요20 | RFY25 | 수익20 | 독창15 | 자동화20 | **합계** |
|---|---|---|---|---|---|---|---|
| A | 큐브 머지 팩토리 (협동 합치기 타이쿤) | 17 | 22 | 17 | 12 | 17 | **85** |
| E | 크리스탈 가든 (실시간 키우기, 자체 IP) | 18 | 22 | 16 | 8 | 17 | **81** |
| D | 큐브 하이스트 (자체 IP 훔치기·방어) | 20 | 20 | 18 | 6 | 15 | **79** |
| H | 낚시 시뮬 (자체 생태계) | 17 | 21 | 15 | 9 | 14 | **76** |
| G | 협동 타워 디펜스 (확정 유닛, 가챠 없음) | 15 | 20 | 15 | 9 | 16 | **75** |
| F | 알 부화 수집 | 17 | 19 | 14 | 6 | 16 | **72** |
| I | 물리 스포츠 아레나 | 14 | 18 | 13 | 11 | 12 | **68** |
| B | 협동 서바이벌 호러 | 15 | 21 | 14 | 8 | 8 | **66** |
| J | 애니 격투 RPG | 15 | 19 | 17 | 6 | 7 | **64** |
| C | 물리 쌓기 파티 | 9 | 13 | 9 | 12 | 15 | **58** |

채점 메모
- G·F의 수익 점수는 **유료 랜덤을 쓰지 않는다는 전제**로 깎았다(상위작 방식 그대로면 18~19).
- H는 자동화 감점: 물고기 모델 수십 종·물 연출·낚시 미니게임 감각 조정이 사람 눈에 의존.
- D의 독창성 6: 장르 자체가 2025~26 최다 복제 장르.

## 3. 가중치 민감도

`python -I tools/concept_score.py` (2026-10-17 실행 결과).

| 시나리오 | 가중치 (수요/RFY/수익/독창/자동화) | 1위 | 2위 | 3위 |
|---|---|---|---|---|
| 기준 | 20/25/20/15/20 | A 85.0 | E 81.0 | D 79.0 |
| 수익 중시 | 20/20/35/10/15 | A 85.1 | D 82.8 | E 81.7 |
| 수요 중시 | 35/20/20/10/15 | A 85.1 | D 84.2 | E 83.2 |
| 독창 경시 | 25/25/25/5/20 | A 85.5 | D 84.5 | E 84.2 |
| 자동화 경시 | 20/30/25/15/10 | A 85.2 | E 80.9 | D 80.0 |

무작위 가중치 2만 회(Dirichlet): A 1위 99.8%, 상위 3위 안에 A·E 100%, D 95%.

**한계**: 가중치 테스트는 원점수가 맞다는 전제다. A가 거의 모든 기준에서 E·D 이상이라 가중치를 바꿔도 당연히 1위가 된다.
그래서 **원점수 자체를 기준마다 ±2점 무작위로 흔든** 테스트를 따로 돌렸다.

| 원점수 ±2 노이즈 (2만 회) | 1위 빈도 |
|---|---|
| A 머지 팩토리 | 79.6% |
| E 크리스탈 가든 | 14.7% |
| D 큐브 하이스트 | 4.8% |
| H 낚시 | 0.7% |
| G 협동 TD | 0.2% |

→ 상위 3개(A·E·D)와 나머지 사이에는 간격이 분명하지만, 상위 3개 안의 순서는 **채점 판단에 따라 뒤집힐 수 있다**.
점수표만으로는 확정하지 않고 시뮬레이션으로 넘긴다.

## 4. 다음 단계
상위 3개(A, E, D)를 **진행 속도·경제 시뮬레이션**으로 비교했다 → [13_SIMULATION.md](13_SIMULATION.md).
결과: A에 E의 장점(짧은 타이머 다수)을 접목한 혼합형 **A+ 머지 팩토리 + 코어 농장** 확정. E는 예비안, D는 손실 기반 재방문의 윤리 문제로 제외.
시뮬레이션에서 보는 것: 첫 세션 이정표 시점, 28일 동안 콘텐츠가 버티는지, 매일 돌아올 이유가 몇 개인지, 과금 상품이 실제로 아껴 주는 시간.

## 출처 (이 문서 추가분)
- [E1] [RoWatcher ASTD](https://rowatcher.com/games/1720936166/upd-all-star-tower-defense), [profitable.app Summer TDS](https://profitable.app/roblox/games/summer-tower-defense-simulator), [Legacy Toilet TD](https://profitable.app/roblox/games/legacy-toilet-tower-defense)
- [E2] [RoWatcher Simulation Takeover](https://rowatcher.com/news/the-simulation-takeover-why-casual-sims-rule-roblox-in-2026), [RoWatcher Fish It!](https://rowatcher.com/games/6701277882), [profitable.app Fisch](https://profitable.app/roblox/games/fisch)
- [E3] [RoWatcher 10 Highest-Earning 2026](https://rowatcher.com/news/the-10-highest-earning-roblox-games-in-2026-and-what-they-mean-for-the-platform), [BloxRant top earning (2026-10)](https://bloxrant.com/roblox-top-earning-games)
- [E4] [RBLXSTAT trending (2026-10-10)](https://rblxstat.com/lists/trending-roblox-games)
- [E5] [games.gg Best Roblox Games 2026](https://games.gg/news/best-roblox-games-2026/), [atriarch (2026-10)](https://www.atriarch.com/best-roblox-games-to-play-in-2026/)
- [E7] [RoWatcher Top 10 March 2026](https://rowatcher.com/news/top-10-roblox-games-by-players-march-2026-data-breakdown)
