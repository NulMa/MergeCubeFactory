# 17. 이벤트: 황금 큐브 · 머지 피버 · 서버 알림

docs/15 §4의 R1(황금 큐브)·R4(머지 피버)·R5(서버 알림)를 구현한 내용이다. 수치는 모두 `game/src/merge/shared/EventsConfig.luau`에 있고, 순수 공식은 `game/tests/Events.spec.luau`에서 검사한다.

## 1. 구조

| 파일 | 역할 |
|---|---|
| `shared/EventsConfig.luau` | 수치, 보상표, 순수 공식(보상 뽑기·등급·감쇠·배수·알림 기준·속도 제한). require 없음(Lune 테스트용) |
| `server/Events.luau` | 플레이어별 이벤트 상태, 황금 큐브 생성·애니메이션·수령 검증, 피버 게이지, 알림, 상품 훅, Studio 디버그 |
| `client/EventsUi.luau` | 피버 바, 버프 타이머 칩, 황금 큐브 버튼(게임패드 L1 / 키보드 G), 배너, 시스템 채팅, 연출 |

원격은 `EventsConfig.REMOTES`(ClaimGolden·EventFx·Announce)를 `Net.serve`로 한 번 더 등록해 같은 `ReplicatedStorage.Remotes` 폴더에 추가한다 → `Remotes.luau`는 건드리지 않았다.

기존 파일 수정(병합용 훅, 전부 한 줄):
- `server/Factory.luau`: `require(Events)`, `mult()`에 `* Events.mult(st)`, `scanMerges`에 `Events.onMerge(st, lower.tier, isBest)`, 투하 간격 `* Events.dropScale(st)`, 스냅샷 `events = Events.snapshot(st)`, `Factory.init`에 `Events.init({ states, spawnCube, trayPoint })`
- `client/init.client.luau`: `require(EventsUi).init(gui)`

## 2. 황금 큐브 (R1)

### 2.1 규칙
- 플레이어마다 접속 **90초** 뒤 첫 등장, 이후 사라지거나 잡힌 시점부터 **4~10분**(균등 랜덤) 뒤 다시 등장.
- 트레이 위 하늘에서 천천히 떨어지며 회전한다(**12초**). 남은 3초는 깜빡인다. 놓치면 사라진다.
- 잡는 방법: 큐브를 직접 클릭·탭(ClickDetector, 거리 400), 또는 화면 아래 가운데 **GOLDEN CUBE!** 버튼, 게임패드 **L1**, 키보드 **G**.
- 서버 검증: 주인만, 현재 id와 같을 때만, 만료 + 0.75초 안에만 인정. 한 번 잡으면 같은 id는 다시 안 된다.
- 다른 플레이어의 플롯에서도 보이지만(자랑·co-play), 주인만 잡을 수 있다.

### 2.2 보상표 (무료 랜덤, 합계 100%)
| 확률 | 이름 | 효과 |
|---|---|---|
| 45% | CASH BURST | 즉시 현금 = 현재 초당 수입 × **150초** (최소 $50) |
| 35% | FRENZY | 모든 수입 **×5, 30초** (이미 켜져 있으면 시간이 더해짐) |
| 12% | DROP STORM | 모든 드로퍼 투하 간격 **×1/3, 20초** (= 큐브 3배) |
| 6% | TIER RAIN | 큐브 **4개**: 등급 = min(최고 기록 − 1, 드로퍼 최고 등급 + 2), 1 ~ MAX−1 |
| 2% | JACKPOT | 큐브 1개: 등급 = 최고 기록 + 1 (상한 `Economy.MAX_TIER`) → 최고 기록 갱신 + 서버 알림 |

- 등급은 `Economy.MAX_TIER`를 인자로 받으므로 등급 확장(30~40등급) 후에도 그대로 동작한다.
- TIER RAIN에 드로퍼 기준 상한을 둔 이유: 최고 기록은 리버스 후에도 남아서, 기록 기준만 쓰면 리버스 직후 고등급 큐브가 쏟아져 리버스 속도가 무너진다.

### 2.3 수치를 연구 초안에서 바꾼 이유
docs/15 초안(현금 600초, FRENZY 45초)을 그대로 쓰면 1회 기대값이 약 335초치 → 7분마다 = **총수입 +80% 이상**이다. 같은 문서의 목표(+15~25%)와 맞지 않아 현금 150초, FRENZY 30초로 줄였다.

기대값(테스트에서 계산, DROP STORM 20초치·RAIN 큐브 1개 15초치·JACKPOT 120초치 근사):
- 1회 기대값 ≈ **118초치 수입**
- 주기 = 평균 7분 + 등장 6초 ≈ 426초
- 총수입 증가: 다 잡으면 **+27.7%**, 70% 잡으면 **+19.4%** (목표 +15~25% 안)

## 3. 머지 피버 (R4)

- 합치기 1회 = 게이지 **+1**. **30** 도달 → **FEVER 12초: 수입 ×3**. 피버 중에는 게이지가 쌓이지 않고, 끝나면 0부터.
- 감쇠/초 = **1 + 드로퍼 투하/초 × 1** (더블 드롭·DROP STORM 포함).
  - 이유: 투하가 많아지면 방치 상태에서도 초당 합치기가 늘어 피버가 계속 켜진다(후반 8드로퍼면 초당 20회 이상). 방치 합치기를 감쇠로 상쇄해서 **직접 투하·SHUFFLE 연쇄로만** 피버가 나게 했다.
  - 테스트: 방치(초당 투하 3)만으로는 30초 뒤에도 목표 미달, 직접 투하(0.4초 쿨다운 = 2.5회/초)를 더하면 약 20초에 도달.
- 연출: 바가 줄어드는 타이머로 바뀌고 그라데이션 회전, 화면 가장자리 주황 틴트, 트레이 위 불꽃, BGM 속도 ×1.12, 시작 시 섬광·충격파·"FEVER! INCOME x3".
- 배수 겹침: FRENZY × FEVER = 15지만 **상한 ×10** (`MULT_CAP`).
- 예상 효과: 계속 두드리는 동안 피버가 약 37% 시간 → 그 구간 +75%. 실제 플레이에서 직접 투하 비중을 20%로 보면 총수입 **+5~10%** (docs/15 추정과 같음). 실측 필요.

## 4. 서버 알림 (R5)

- 대상: (1) 처음으로 **등급 ≥ round(MAX_TIER × 0.8)** 도달 (MAX 12 → 10, 36 → 29, 최소 6), (2) 황금 큐브 JACKPOT.
- 표시: 서버 전체 위쪽 배너 4초 + 시스템 채팅 한 줄.
  - TextChatService면 `RBXSystem:DisplaySystemMessage`, 구형 채팅(rojo 빌드 기본값이 LegacyChatService)이면 `SetCore("ChatMakeSystemMessage")`.
- 속도 제한: 서버 전체 **60초에 3건**, 같은 플레이어 **20초에 1건**.
- 전 서버 알림(MessagingService)은 아직 만들지 않았다(극희귀 변이가 생기면).

## 5. 상태·타이머

모든 버프는 서버가 시각으로 들고 있고(`workspace:GetServerTimeNow()`), State 스냅샷 `events` 필드로 매초 내려간다:
`{ gauge, goal, fever?, frenzy?, storm?, golden? = { id, left }, mult, frenzyProduct? }`. 클라는 받은 뒤 흐른 시간을 빼서 매 프레임 "FRENZY x5 0:32" 칩을 갱신한다.
FRENZY 끝 시각은 저장 데이터(`data.frenzyUntil`)에 있어 재접속해도 남은 시간이 유지된다(유료 FRENZY 대비). Reconcile이 필요 없도록 없으면 0으로 읽는다.

## 6. 수익화 (확정 효과만)

유료 랜덤 금지 원칙(DECISIONS 2026-10-18): 등장 빈도·보상 확률을 바꾸거나, 무작위 보상을 더 받게 하는 상품은 만들지 않는다.

| 제안 | 종류 | 가격 | 상태 |
|---|---|---|---|
| **Frenzy ×5 (2분 / 5분)** | 개발자 상품 | 19 / 49 R$ | 판매 중. `shared/Shop.luau` (docs/03 §2) |
| Frenzy ×5 (30분) | 개발자 상품 | 199 R$ | 제안. 같은 훅에 시간만 다르게 |
| Fever Now (즉시 피버 12초 ×3) | 개발자 상품 | 15 R$ | 제안. 효과가 작아 우선순위 낮음 |
| 피버 테마·황금 큐브 스킨 | 꾸미기 | ◆ 또는 R$ | 제안 |
| ~~Golden Magnet (자동 수령)~~ | 게임패스 | — | **보류**: 놓칠 무작위 보상을 돈으로 더 받게 하므로 간접 유료 랜덤으로 볼 여지가 있다 |

FRENZY 상품을 구매 버튼으로 노출하는 UI는 아직 없다(`snapshot.events.frenzyProduct`로 id만 내려감). 상품을 만들면 HUD 칩 옆 버튼을 추가한다.

## 7. 측정 (AnalyticsService.LogCustomEvent)
`GoldenCubeSpawn` / `GoldenCubeCaught` / `GoldenCubeMissed` (잡는 비율 목표 ≥ 60%), `FeverStart`. 잡는 비율이 70%에서 크게 벗어나면 §2.3 기대값을 다시 계산한다.

## 8. Studio 테스트 훅
Studio에서만 `ServerScriptService.EventsDebug:Invoke(cmd, player, arg)`:
`"golden"` [보상 id] 즉시 등장(보상 고정 가능) · `"claim"` 현재 큐브 수령 · `"fever"` 게이지 가득 → 피버 · `"announce"` 텍스트 → 배너 · `"state"` 스냅샷.

## 9. 남은 일
- `tools/pacing_sim.py`에 황금 큐브(+약 20%)·피버(+5~10%) 기대값을 넣어 k 재보정 (docs/15 §4 합산 주의).
- 피버 실측: 직접 투하 비중, 피버 빈도.
- FRENZY 상품 생성 후 구매 버튼.
