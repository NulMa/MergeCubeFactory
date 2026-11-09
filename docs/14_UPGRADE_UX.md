# 14. 업그레이드 v2 — 배치·다양화·성장 체감

기준일 2026-10-18. 계기: 사용자 피드백 "구매 버튼이 한군데 몰려 가독성이 떨어지고 올리는 맛이 안 남. 버튼만 누르는 느낌이 아니라 성장 체감이 오게."

## 1. 조사 요약

| 출처 | 내용 | 우리 적용 |
|---|---|---|
| 타이쿤 제작 가이드 [U1][U2] | 업그레이드 버튼은 **그것이 바꾸는 대상 바로 옆**에. 흩어지거나 한곳에 몰리면 혼란. 잠긴 구역은 처음부터 보여 기대감을 만든다 | 드로퍼마다 머리 위 카드. 다음 잠긴 드로퍼 자리도 카드로 보임 |
| 머지 장르 상위작 (Merge a Nuke, Merge a Black Hole) [U3][U4] | 업그레이드를 성격이 다른 몇 가지로 나눔: 생성 등급 / 생성 속도 / 최대 개수, 리버스는 영구 배수 | 드로퍼(속도·등급) + 공장(가치·행운·탭 파워) + 코어(부화대·부화 속도)로 나눔 |
| 방치형 마일스톤 [U5][U6] | 일정 레벨(25, 50, 100…)마다 생산 ×2 같은 **큰 한 방**. 균등하게 올리기보다 마일스톤을 노리게 됨 | 드로퍼 속도 5·10·15레벨마다 "더블 드롭", 광택 10·20레벨마다 수입 ×2 |
| 게임 주스 일반론 [U7][U8] | 행동 직후 즉시, 과장된 반응(숫자 튕김, 크기·색 변화, 소리). 입력→결과 지연 최소화 | 구매 즉시 대상 오브젝트가 반응 + 이전→이후 수치 표시 + 연속 구매 시 음높이 상승 |

## 2. 문제 진단 (v1)
1. **한 목록에 모든 버튼**: 드로퍼 8개 × 2줄 + 슬롯 + 부화대 + 리버스 → 최대 19줄이 같은 모양. 무엇이 무엇을 바꾸는지 공간적 연결이 없음.
2. **효과가 숫자 한 개**: "Dropper 3 speed (1.2s)" — 사고 나서 무엇이 좋아졌는지 화면에서 안 보임.
3. **업그레이드 종류가 사실상 2개**(속도·등급) + 슬롯: 선택의 재미 없음, 가장 싼 것만 누르게 됨.
4. **목표 없음**: 다음에 뭐가 크게 좋아지는지(마일스톤) 표시가 없음.

## 3. v2 설계

### 3.1 배치 — "대상 옆에 버튼"
- **드로퍼 카드 (월드)**: 각 드로퍼 위에 작은 카드. `SPEED 1.2s → 1.0s  $X` / `TIER 3 → 4  $Y` 두 버튼 + 다음 마일스톤까지 막대.
  - 살 수 있으면 카드 테두리가 빛남. 아직 없는 드로퍼 자리는 **다음 1개만** "NEW DROPPER $X" 카드로 보임(기대감).
  - 화면 탭으로 바로 구매(휴대폰·PC), 게임패드는 패널로.
- **패널 (화면)**: 탭 3개 — FACTORY / CORES / REBIRTH. 각 항목은 카드: 아이콘·이름·Lv·"지금 → 다음" 효과·마일스톤 막대·가격 버튼.
- **UPGRADES 버튼 배지**: 지금 살 수 있는 업그레이드 수(빨간 점 숫자).

### 3.2 다양화 — 성격이 다른 업그레이드

| 구분 | 업그레이드 | 효과 | 상한 | 마일스톤 | 눈에 보이는 변화 |
|---|---|---|---|---|---|
| 드로퍼 | SPEED | 투하 간격 ×0.88/Lv | 15 | 5·10·15Lv: **더블 드롭** 확률 +15% (두 개 떨어짐) | 드로퍼가 빨리 들썩임, 더블 드롭 시 큐브 2개 |
| 드로퍼 | TIER | 떨어뜨리는 큐브 등급 +1 | 리버스에 따라 6~20 (13 §8) | — | 드로퍼 색·크기가 등급 색으로 커짐 |
| 공장 | POLISH 광택 | 모든 큐브 수입 +10%/Lv | 20 | 10·20Lv: **수입 ×2** | 수입 숫자 튕김, 마일스톤마다 큐브 재질이 반짝 |
| 공장 | LUCKY 행운 | 합치기가 2단계 뛸 확률 +2%/Lv | 10 | — | 금빛 "LUCKY!" 연출 |
| 공장 | TAP 탭 파워 | DROP 버튼 큐브 등급 +1/Lv | 5 | — | DROP 버튼에 등급 표시, 큰 큐브가 떨어짐 |
| 코어 | INCUBATOR | 부화대 +1 | 12 | — | 부화 목록 칸 증가 |
| 코어 | HATCH 부화 속도 | 부화 시간 −5%/Lv | 10 | — | 남은 시간 즉시 단축 |
| — | REBIRTH | 영구 수입 ×1.5, 드로퍼 최대 등급 +1, 합치기 상한 +2 (12→40) | 14 (13 §8) | — | 섬광 + 레벨업 |

- 리버스 시 초기화: 드로퍼·POLISH·LUCKY·TAP. 유지: 부화대·HATCH·코어 보너스(05 §4.5 "영구").
- 초기화되는 업그레이드(속도·등급·슬롯·POLISH·LUCKY·TAP)는 리버스 횟수 r에 대해 비용 ×3^r (13 §8). 부화대·HATCH는 그대로.
- 공식은 `game/src/merge/shared/Economy.luau`, 시뮬레이션 `tools/pacing_sim.py` MergeGarden과 같다. 비용 배율 k는 v2 기준으로 다시 보정(13 §7).
- 유료 랜덤 없음 유지: LUCKY는 무료 플레이 확률이고 Robux로 사는 상품이 아니다(DECISIONS).

### 3.3 체감 — 구매 순간
1. 버튼 튕김 + 이전→이후 숫자가 굴러 올라감.
2. **대상 반응**: 드로퍼 구매면 그 드로퍼가 번쩍·부풀고 반짝이, 공장 구매면 트레이 전체에 물결.
3. 연속 구매 시 효과음 음높이 상승(최대 1옥타브), 1.5초 쉬면 초기화.
4. **길게 누르면 연속 구매**(0.35초 후 시작, 점점 빨라짐) — 같은 버튼 반복 탭 피로 제거.
5. 마일스톤 도달: 팡파레 + "DOUBLE DROP!" / "INCOME x2!" 큰 글자.

### 3.4 구현 메모 (2026-10-18 플레이테스트 반영)
- **카메라·드로퍼 높이**: 드로퍼가 바닥 위 34스터드에 있으면 기본 카메라에서 드로퍼와 카드가 화면 위로 잘린다. 그래서 드로퍼를 20스터드(벽 바로 위)로 낮췄다. 내 공장 40스터드 안에 있으면 `Humanoid.CameraOffset`으로 카메라 초점을 트레이 쪽으로 옮기고, 멀어지면 캐릭터로 돌아온다.
- **알약 → 카드**: 드로퍼 8개에 상세 카드를 모두 띄우면 트레이와 HUD를 가린다. 평소에는 작은 알약(`T3·1.2s ▲`)만 띄우고, 누르면 그 드로퍼 카드만 펼친다. 8초 동안 안 만지면 다시 접힌다. 다음 잠긴 자리는 `+$300` 알약으로 보인다.
- 현금 HUD를 가운데 위에서 왼쪽 위로 옮겼다(뒷줄 카드를 가림).
- 패널 탭은 DROPPERS / FACTORY / CORES / REBIRTH이고, 탭마다 살 수 있는 개수 점을 단다. 게임패드 사용자는 패널만으로 모든 구매가 가능하다.
- 서버 Remote `Upgrade(id)`를 추가했다. 마일스톤과 행운 합치기는 `Fx("milestone", text, target)`, `Fx("lucky", pos, tier)`로 알린다.
- 코드: `client/Upgrades.luau`(UI), `client/Ui.luau`(공용 헬퍼·길게 누르기), `client/Fx.luau`(구매 반응), `server/Factory.luau`(`onUpgrade`).
- Studio 전용 `ServerScriptService.StudioDebug:Invoke("cash", player, n)`은 테스트용 현금 지급 훅이다. 게시 서버에서는 만들지 않는다.

## 5. 섞기 (SHUFFLE) — 2026-10-18 추가, **2026-10-19 삭제**

> **삭제(2026-10-19, 사용자 요청 "셔플 기능은 이제 의미 없으니 삭제")**: 배트가 같은 역할(막힌 큐브 흩기)을 하게 되어 버튼·Remote·서버 처리를 지웠다. 개발자 상품 "Shuffle x3"(3719259642)은 판매 중지(`node tools/products.mjs offsale`). 이미 처리 중인 영수증을 위해 `server/Shop.luau`의 지급 함수만 남겼다(지급해도 쓸 곳은 없음). STEAL 버튼이 섞기 자리(DROP 바로 위)로 내려왔다. 아래는 기록용.
- **문제**: 큰 큐브가 같은 등급 큐브 사이를 막으면 자석(점프)으로도 못 만나 합치기가 멈춘다(사용자 플레이 피드백).
- **효과 (2026-10-18 개정)**: 큐브 덩어리 중심(큰 큐브일수록 무게)에서 국소 폭발. 가까운 큐브일수록 세게 바깥·위로 튕긴다(수평 34, 위 52, 반경 26, 무작위 ±20%). 위 속도는 벽 높이 −3을 넘지 않게 묶어 트레이 밖으로 떨어지지 않게 한다(밖으로 떨어지면 큐브가 사라짐). 연출은 쿵 소리 + 충격파 고리 두 겹 + 불꽃·연기 + 화면 흔들림. `Factory.explodeTray`.
  - 처음 구현(등급순 줄 세우기)은 이웃한 같은 등급만 한 번 합쳐지고 다시 막혔다(사용자 피드백). 폭발은 큰 큐브가 막던 배치 자체를 흩는다.
  - Studio 측정: 최고 6.7스터드 상승, 평균 11스터드 이동, 3회 연속 사용에도 트레이 밖 0개.
  - 흩어지는 위치는 무작위지만 보상이 아니라 배치를 바꾸는 도구라서 유료 랜덤 보상 금지 규칙과는 무관하다(사는 것은 '섞기 3회'로 확정).
- **무료 충전**: 30분마다 1회, 최대 3회까지 쌓인다(접속하지 않아도 쌓임). 처음엔 1회를 준다. 상한일 때는 시계가 멈춰 있다가, 쓰는 순간부터 다음 30분이 시작된다. 공식은 `Economy.shuffleRegen`, 테스트는 `tests/Economy.spec.luau`.
- **유료 충전**: 개발자 상품 "Shuffle x3"(`shared/Shop.luau` key `shuffle`). Shuffle Pro 패스는 무료 충전을 15분·최대 6으로 바꾼다. 무료 횟수를 먼저 쓰고 유료 횟수를 나중에 쓴다. 유료 횟수는 상한이 없고 저장된다. 상품 id가 0이면 구매 버튼을 숨기고 남은 시간만 안내한다.
- **UI**: DROP 버튼 위의 `SHUFFLE xN / +1 in 12m 30s` 버튼. 0회이고 상품이 있으면 `GET +3`을 누를 때 구매 창이 뜬다.
- **측정**: `AnalyticsService:LogCustomEvent("ShuffleUsed")`.

## 4. 측정
- 분석 이벤트 `LogEconomyEvent` sku에 업그레이드 id가 이미 들어감 → 어떤 업그레이드를 먼저 사는지 분포 확인.
- 플레이테스트 지표: 첫 5분 구매 종류 수(목표 ≥3), 첫 마일스톤 도달 시간(목표 ≤10분).

## 출처
- [U1] creation.dev, "How to make a tycoon game" — https://www.creation.dev/blog/how-to-make-a-tycoon-game
- [U2] obby.fun, "How to make a tycoon game in Roblox" (2026-04-22) — https://www.obby.fun/blog/how-to-make-tycoon-game-roblox
- [U3] Sportskeeda, "Merge a Nuke: A beginner's guide" — https://www.sportskeeda.com/roblox-news/merge-nuke-a-beginner-s-guide
- [U4] Merge a Black Hole Getting Started Guide (2026) — https://mergeblackhole.wiki/guides/
- [U5] TV Tropes, Simple Mult Idle (2x every 25 levels) — https://www.tvtropes.org/pmwiki/pmwiki.php/VideoGame/SimpleMultIdle
- [U6] LevelWinner, The Ultimate Prepper guide (milestones 25/50/100) — https://www.levelwinner.com/?p=12731
- [U7] Game Developer, "Squeezing more juice out of your game design" — https://www.gamedeveloper.com/design/squeezing-more-juice-out-of-your-game-design-
- [U8] bugnet.io, "Game feel: why juice matters" — https://bugnet.io/blog/game-feel-why-juice-matters-and-how-to-add-it
- 팬 위키 출처(U3·U4)는 비공식이라 수치는 참고만, 구조(업그레이드 종류 분리)만 차용.
