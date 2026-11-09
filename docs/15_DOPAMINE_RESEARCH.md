# 15. 도파민 설계 조사 — 변이·이벤트·변동 보상

기준일 2026-10-18. 계기: 사용자 피드백 "게임에 도파민이 부족하다. 확률로 나오는 특수 큐브(메탈릭·무지개·네온…)가 더 벌고, 모으면 꾸미기나 추가 재화를 주면 좋겠다. 다른 게임을 조사해 아이디어를 더 달라."

> 진행 중인 작업과 겹치지 않게 나눴다.
> - **특수 큐브 변이**(합치기 시 확률, 수입 배수, 도감 수집 → 꾸미기·젬): 다른 에이전트가 구현 중. 이 문서는 §2에 **튜닝용 수치 근거**만 남긴다.
> - **등급 수 확장**: 다른 에이전트가 구현 중.
> - 이 문서의 추천(§4)은 이 둘 **밖의** 장치다.

수치 표기는 05와 같다: `$` = 현금, `◆` = 젬. 팬 위키 수치는 비공식이고 업데이트로 자주 바뀌므로 **구조와 크기 감**만 참고한다.

---

## 1. 왜 "도파민이 부족한가" — 진단

| 원인 | 지금 우리 게임 | 조사에서 본 해법 |
|---|---|---|
| 보상이 **예측 가능** | 같은 등급 2개 → 항상 등급+1, 수입은 공식대로. 놀랄 일이 LUCKY(2단계 점프)뿐 | 변동 비율 보상(다음 보상이 언제 올지 모름)이 가장 오래 행동을 유지한다 [P1][P2] |
| **기다릴 이벤트**가 없음 | 코어 타이머 외에 "곧 무슨 일이 생긴다"가 없음 | Grow a Garden 날씨, Cookie Clicker 황금 쿠키 — 몇 분마다 잠깐 열리는 기회 [G1][C1] |
| **남이 보는 자랑**이 없음 | 순위표 숫자뿐 | 희귀 획득 시 서버 알림, 눈에 띄는 외형(무지개·빛) — 자랑이 다시 목표가 됨 |
| **손으로 잡는 순간**이 적음 | 드로퍼가 자동, 플레이어는 SHUFFLE·DROP 정도 | 화면에 잠깐 뜨는 것을 **탭해서 잡는** 행동(쿠키, 드론) [C1][E1] |
| **완성 목표**가 약함 | 도감 72칸이 있으나 결과가 확률뿐 | 확정 합성(일반 10 → 금 1)으로 "언젠가는 반드시" 경로 [PS2] |

---

## 2. 게임별 조사 결과

### 2.1 변이(특수 버전) — 튜닝 근거

| 게임 | 장치 | 확률 | 배수 | 왜 먹히나 | 출처 |
|---|---|---|---|---|---|
| Grow a Garden | 자라는 작물이 저절로 Gold/Rainbow | Gold 1%, Rainbow 0.1% | Gold ×20, Rainbow ×50 | 매 작물이 작은 복권. 금·무지개는 동시 불가(배타) | [G1][G2] |
| Grow a Garden | 날씨 변이 Wet·Shocked·Celestial 등 40종+ | 날씨 중에만 확률 | ×2 ~ ×150, 여러 개 겹침(최대 ×201,050 보고) | 겹치기(스택)가 "더 높이" 욕심을 만듦 | [G3] |
| Steal a Brainrot | 생성 시 Gold/Diamond/Rainbow | Gold 약 10%, Rainbow 약 1% (Diamond는 출처마다 5~20%) | Gold ×1.25, Diamond ×1.5, Rainbow ×10 | **흔한 변이는 배수가 작고, 드문 변이만 크다** — 자주 터지되 경제는 안 깨짐 | [B1][B2] |
| Pet Simulator 99 | Golden·Rainbow·Shiny 펫 | 공식 확률 비공개. Magic Eggs 패스가 금·무지개 각 10% | 무지개 ≈ 금보다 20%, 일반보다 50% 강함 | **확정 합성**: 일반 10 → 금 1, 금 10 → 무지개 1 (무지개 1마리 = 원본 100) | [PS1][PS2] |
| Merge a Nuke | 핵에 변이(공통~Admiral 16종) | 리버스 3부터 생성 시 확률, 합칠 때 **상속** 확률. Legendary는 10%로 "Stabilized"(부작용 제거) | 공통 +25~40% 현금 ~ Apex ×2.5 | 리버스로 변이 단계가 열림(3 → 5 → 10) = 리버스의 이유 | [N1][N2] |
| Bee Swarm Simulator | Gifted(빛나는 벌) | 선호 간식 1/8,000~1/25,000, 로열젤리 0.4% | 능력치 보너스 + 전용 효과 | 극저확률 + 겉모양(별 표시)으로 자랑 | [BS1][BS2] |

**튜닝 시사점 (변이 담당 에이전트용)**
1. 우리 등급 간격은 ×2.4(05 §4.1). 변이 ×2는 "등급 0.8칸" 가치, ×8은 "등급 2.4칸". **변이 배수가 ×3을 넘는 것은 1% 미만**이어야 등급 성장이 주인공으로 남는다.
2. 추천 시작값(합치기 1회당, 무료 확률): Metallic 4% ×1.5 / Neon 1.2% ×3 / Rainbow 0.25% ×8 / (최상위 1종) 0.03% ×25.
   기대 수입 증가 = Σ p×(m−1) = 0.02 + 0.024 + 0.0175 + 0.0072 ≈ **+6.9%** — 업그레이드 1~2단계 수준이라 페이싱(13)을 흔들지 않는다. 체감은 "40개 트레이에서 몇 분마다 1개 반짝".
3. Steal a Brainrot처럼 **흔한 것 작게, 드문 것 크게**. Grow a Garden처럼 금·무지개 **배타**(한 큐브에 하나만).
4. 상속: Merge a Nuke처럼 변이 큐브를 합치면 결과가 변이를 **이어받을 확률**(예: 같은 변이끼리 100%, 한쪽만 50%) — 변이 큐브를 아끼고 키우는 이유가 생긴다.
5. PS99식 **확정 합성** 경로가 있으면 운이 나빠도 도감이 언젠가 찬다(§4 R7).

### 2.2 시간제 이벤트·날씨

| 게임 | 장치 | 수치 | 왜 먹히나 | 출처 |
|---|---|---|---|---|
| Cookie Clicker | 황금 쿠키: 5~15분마다 화면에 13초 등장, 클릭 시 무작위 효과 | Lucky ~40% (은행 15% 또는 CpS 15분치 중 작은 값), Frenzy ~40% (생산 ×7, 77초), Building Special ~8%, Click Frenzy ~3% (클릭 ×777, 13초), Chain·Storm 각 ~0.7% | 방치형에 **"지금 화면을 봐야 하는 이유"**. 흔한 결과(Lucky·Frenzy)가 80%라 실망이 적고, 드문 결과가 이야깃거리 | [C1][C2] |
| Grow a Garden | 날씨(비·뇌우·유성우…)가 서버에 돌고, 날씨마다 고유 변이 | Night는 2분마다 최대 6그루. 유성우 Celestial ×120 | "곧 비가 온다" → 접속 유지. 날씨별 변이 = 수집 목표 | [G3] |
| Grow a Garden | 관리자 이벤트(Admin Abuse): 개발자가 공개 서버에 들어와 희귀 날씨 남발 | Steal a Brainrot과 겹친 주말 Roblox 동접 약 4,729만, GaG 단독 약 2,230만 기록 | **약속된 시간**에 모두 모임. 사설 서버에는 적용 안 됨 → 공개 서버로 사람이 몰림 | [G4][G5] |
| Merge a Nuke | Lava Merge 이벤트(합치면 Magma +50% 현금), 화산 이벤트, 패치일 15분 이벤트, 매주 금요일 정오(ET) 업데이트 | Magma +50% | 정기 일정 = 습관 | [N1][N3] |

### 2.3 손으로 잡는 보너스

| 게임 | 장치 | 수치 | 출처 |
|---|---|---|---|
| Egg, Inc. | 화면을 지나가는 드론을 탭 → 현금 또는 황금알 | 일반 드론 황금알 3/6/12, 엘리트 12/48. 황금알 기본 확률 약 30%(커뮤니티) | [E1][E2] |
| Cookie Clicker | 황금 쿠키(위) | 13초 안에 클릭 | [C1] |

### 2.4 큰 한 방·영구 성장

| 게임 | 장치 | 수치 | 출처 |
|---|---|---|---|
| AdVenture Capitalist | 사업체 25·50·100개마다 수익 배수(×2·×3), 환생 화폐 Angel 1개당 +2% | 100 Angel = +200%(×3) | [A1][A2] |
| Merge Dragons | 3개 대신 **5개를 합치면 2개** 생성 | 같은 결과에 필요한 재료 약 33% 절약 | [M1][M2] |

### 2.5 심리 근거
- 변동 비율 강화(언제 보상이 올지 모름)는 고정 보상보다 소거 저항이 크다(Skinner). 아깝게 놓친 결과(near-miss)도 보상 회로를 자극한다(Clark et al., *Neuron* 2009 인용) [P1][P2].
- 이 효과는 유료와 결합하면 도박 구조가 된다. 그래서 우리는 **무료 플레이에만 변동 보상**을 두고, 돈은 **확정 결과**에만 받는다(§3).

---

## 3. Roblox 정책 제약 (유료 랜덤)

| 규칙 | 내용 | 출처 |
|---|---|---|
| 범위 | Robux 또는 **Robux로 산 게임 재화**로 얻는 무작위 결과. 직접·간접 모두. 캡슐(뽑기·알 부화), 강화, 조합, **확률 변경 아이템(행운 부스트, 천장(pity), 드롭 증가, 확률 업)** 포함 | [R1] |
| 확률 공개 | 모든 결과와 실제 확률을 %로, 합계 정확히 100%. 너무 많으면 "Info/Details" 같은 **글자가 있는** 버튼의 팝업("(i)" 아이콘만은 불충분). 확률 변경 아이템은 효과 수치를 보여주고, 켜져 있는 동안 바뀐 확률을 실시간 갱신 | [R1] |
| PolicyService | `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted`가 true인 사용자는 유료 랜덤 생성기와 상호작용 불가. 대안: 무료 획득 경로 제공 / 정해진 순서로 공개 / 특정 결과를 기대값 가격으로 직접 판매 / 숨기기 / 구매 차단 메시지 / 해당 구역에서 이동 | [R1][R2] |
| 거래 | `IsPaidItemTradingAllowed`가 false면 유료 랜덤 결과를 거래하게 하면 안 됨 | [R1] |
| 무료 랜덤 | Robux·유료 재화가 끼지 않은 무작위 보상(게임에서 주운 열쇠로 상자 열기 등)은 **확률 공개 의무 없음** | [R1] |
| 배경 | 2026-06 한국 게임법에 맞춰 규정이 개정되어 전 세계에 적용됐다는 보도(2차 출처) | [R3] |

### 3.1 우리 문서와 충돌하는 지점 (확인 필요)
1. **03 §상품표의 "Lucky Boost 15분 — 변이 확률 2배 (확정 효과, 랜덤 상품 아님)"**: Roblox 정의상 **행운 부스트는 유료 랜덤 아이템(확률 변경)** 이다 [R1]. "효과가 확정"이어도 결과가 무작위이므로 해당한다. DECISIONS(2026-10-18 "유료 랜덤: 아니요" 설문 제출)와 모순 → **출시 버전에서 제거**를 권한다. 05 §4.4도 같은 결론.
2. **Instant Hatch**: 부화 결과(변이)가 부화 **완료 시점에** 굴려지면 "Robux로 무작위 결과를 앞당겨 받는" 모양이 된다. 안전한 설계: **코어가 생길 때 결과를 미리 굴려 저장**하고(서버), 부화 카드에 결과를 보이거나 최소한 "결과는 이미 정해짐"으로 둔다. 그러면 Instant Hatch는 확정 결과의 **시간만** 산다(R1의 "정해진 순서로 공개" 처리와 같은 성격).
3. **젬**: Factory Plus가 매일 젬을 주고 젬이 Robux로 간접 획득되면, **젬으로 무작위 보상을 사는 기능은 전부 유료 랜덤**이 된다. 원칙: 젬 상점은 확정 상품만(꾸미기, SHUFFLE 충전, 시간 단축).
4. **천장(pity)을 돈으로 사거나 당기는 것 금지.** 무료 천장(§4 R2의 "200번째 보장")은 괜찮다.

---

## 4. 추천 — 우선순위 (변이·등급 확장 제외)

평가: 도파민 효과(변동 보상·수집·자랑) × 구현 비용 × 수익 연결. 노력 S = 하루 이내, M = 2~4일, L = 1주+.
수치는 `Config`로 뺄 초안이다. "N초치 수입" = 그 순간 초당 수입 × N.

### R1. 황금 큐브 (Golden Cube) — 노력 S~M ★★★
Cookie Clicker 황금 쿠키의 우리 판. **방치 중에도 화면을 볼 이유.**
- **등장**: 접속 중 플레이어마다 4~10분 간격(균등 랜덤)으로 하늘에서 반짝이는 황금 큐브가 트레이 위로 천천히 떨어진다. **12초** 안에 탭(또는 걸어서 닿기)하면 터진다. 놓치면 사라짐. 첫 등장은 접속 90초 후(튜토리얼 직후).
- **효과 (무료 랜덤)**:
  | 확률 | 이름 | 효과 |
  |---|---|---|
  | 45% | CASH BURST | 즉시 현금 = 600초치 수입(현재 보유 현금 25% 상한) |
  | 35% | FRENZY | 모든 수입 ×5, 45초 |
  | 12% | DROP STORM | 모든 드로퍼 투하 간격 ×0.33, 20초 (= 큐브 3배) |
  | 6% | TIER RAIN | 현재 드로퍼 최고 등급+1 큐브 4개를 트레이에 떨어뜨림 |
  | 2% | JACKPOT | 드로퍼 최고 등급+3 큐브 1개 (거대 연출, 서버 알림 R5) |
- 기대값 대략 "4~10분마다 약 3~4분치 수입" → 총수입 **+15~25%**. 리버스 시간이 그만큼 당겨지므로 `pacing_sim.py`에 넣어 k를 재보정.
- **수익 연결 (확정만)**: 게임패스 "Golden Magnet"(119 R$) = 황금 큐브를 **자동으로 잡음**(빈도·확률 불변, 놓침만 방지 — 편의). 개발자 상품 "Frenzy ×5 (5분)" 49 R$ = **확정** 효과 직접 판매(무작위 아님).
- **주의**: 빈도·좋은 결과 확률을 올리는 유료 상품은 만들지 않는다(확률 변경 = 유료 랜덤 [R1]).

### R2. 선물 큐브 (Gift Cube) + 무료 천장 — 노력 S ★★★
드로퍼가 가끔 리본 달린 상자 큐브를 떨어뜨린다. 손으로 잡거나 아무 큐브와 닿으면 열린다.
- **확률**: 투하 1회당 0.6%(약 167회에 1개). **200회 동안 안 나오면 다음 투하에 확정**(무료 천장 — 불운 체감 제거).
- **내용 (무료 랜덤)**: 40% 현금 300초치 / 25% SHUFFLE +1 / 20% ◆ 5~15 / 10% 부화 가속 −10분(진행 중 코어 1개) / 5% 특수 변이 큐브 1개(현재 드로퍼 등급, 변이 시스템과 연결).
- 열 때 상자가 흔들리다 터짐(0.6초) → 결과 아이콘이 튀어나옴. 기대감 연출이 핵심.
- **수익 연결**: 직접 판매 없음(선물 상자를 Robux로 팔면 유료 랜덤). 간접: SHUFFLE·젬 소비처 확대 → 확정 상품 수요.

### R3. 공장 날씨 (Factory Weather) — 노력 M ★★★
Grow a Garden 날씨의 우리 판. **서버 전체가 같은 순간을 공유** → co-play·약속 신호.
- **주기**: 12분마다 3분짜리 날씨 1개. 날짜·시간 시드로 **모든 서버 동일**(Cubika `Daily.luau` 방식) → "다음 날씨: 메테오 샤워 4분 뒤" 예고 표시.
- **날씨 표 (무료 효과)**:
  | 가중치 | 날씨 | 효과 | 고유 변이(변이 시스템과 연결) |
  |---|---|---|---|
  | 30 | Overclock (번개) | 드로퍼 속도 ×2 | Shocked ×3 (번개가 무작위 큐브 1개/20초에 내리침) |
  | 25 | Gold Rush (금빛 안개) | 변이 확률 ×3 | — |
  | 20 | Combo Fever | 콤보 상한 ×3 → ×6 | — |
  | 15 | Meteor Shower | 30초마다 운석이 각 플롯에 1개 낙하 = 최고 드로퍼 등급+2 큐브 | Celestial ×10 (운석 큐브 5% 확률) |
  | 10 | Aurora | 부화 속도 ×3 | Aurora ×6 (날씨 중 부화한 코어 10%) |
- 날씨 고유 변이는 **날씨 때만** 나오므로 도감에 "날씨 줄"이 생긴다(재방문 이유).
- **주말 관리자 이벤트**: 토요일 1회, 30분 동안 희귀 날씨(Meteor·Aurora)만 연속. 공개 서버에만 적용(사설 서버 제외 — GaG 방식 [G4]).
- **수익 연결**: 날씨 자체는 판매하지 않는다(Gold Rush는 확률 변경이라 판매 금지). 사설 서버에서만 "Overclock 날씨 즉시 호출" 개발자 상품 25 R$ — 확정 효과라 허용. 집객은 사설 서버 판매로.

### R4. 머지 피버 게이지 — 노력 S ★★
지금 콤보(1초 안 연속, ×3 상한)를 **눈에 보이는 게이지**로 확장. 순수 실력·결정적 보상.
- 합치기 1회 = 게이지 +1(등급 7+는 +2), 5초 동안 합치기가 없으면 초당 −2. **게이지 30 도달 → FEVER 12초**: 수입 ×3, 합치기마다 작은 현금 폭죽(5초치), 배경음 템포업.
- 콤보 숫자는 화면 가운데에 크게, 10·20·30 콤보마다 음높이 상승 + "GREAT / AMAZING / FEVER!" 문구.
- SHUFFLE이 같은 등급을 한꺼번에 붙이므로 **SHUFFLE → 연쇄 합치기 → 피버**가 자연스러운 한 방이 된다(SHUFFLE 가치 상승 → 유료 "Shuffle x3" 수요).
- **수익 연결**: SHUFFLE 상품 수요 증가(간접). 게이지 자체 판매 없음.

### R5. 서버 알림·첫 발견 — 노력 S ★★
"남이 보는" 순간. Pet Simulator·Bee Swarm류의 자랑 문화.
- **서버 배너+채팅**: 누군가 등급 10+ 첫 도달, Rainbow 이상 변이, JACKPOT(R1), Cosmic 코어 부화 시 → 화면 위 배너 4초 "NullMa got a RAINBOW Tier 11!" + 시스템 채팅.
- **전 서버 알림**(MessagingService): 0.03% 최상위 변이·등급 12 Rainbow처럼 극희귀만. 분당 상한(예: 서버당 1분 3건)으로 도배 방지.
- **개인 첫 발견**: 처음 보는 등급·변이는 도감 실루엣이 벗겨지는 1.5초 연출 + "NEW!" + ◆ 소량.
- 플레이어 머리 위에 최고 기록 칭호(예: "Rainbow Hunter") 선택 표시.
- **수익 연결**: 칭호·이름 색은 도감/시즌 패스 보상(확정). 자랑 욕구 → 시즌 패스 구매.

### R6. 부화 연출 강화 + 부화 품질 — 노력 S~M ★★
부화를 **결과 확인 이벤트**로. 지금은 타이머 끝 → 결과.
- **결과는 코어 생성 시 서버에서 미리 결정**(§3.1 #2 — Instant Hatch 정책 안전).
- 부화 품질(무료 랜덤, 코어 생성 시 결정): Normal 82% / Great 15%(영구 보너스 ×2) / Perfect 3%(영구 보너스 ×5 + 금빛 코어 외형).
  - 부화 카드에 품질은 **처음부터 공개**(금빛 테두리)해서 "Perfect 코어가 8시간 남았다" = 재방문 이유. 변이 결과는 감춰두되 이미 결정되어 있다.
- 부화 연출: 알이 3번 흔들림(흔들림 강도가 결과 희귀도를 암시) → 섬광 → 결과. 여러 개를 동시에 열면 차례로(빠르게).
- **수익 연결**: Instant Hatch(기존, 확정 결과의 시간 단축). Perfect 코어 카드가 보이면 구매 동기 상승.

### R7. 변이 합성로 (Fusion Furnace) — 노력 M ★★
PS99 "일반 10 → 금 1"의 우리 판. **운이 나빠도 완성할 수 있는 확정 경로** = 수집 완료감.
- 같은 등급·같은 변이 큐브 **5개 → 다음 변이 1개, 같은 등급**(Normal → Metallic → Neon → Rainbow …). 결과 100% 확정.
- 트레이 옆 기계에 큐브를 들어 넣는다(물리 손맛). 합성 중 10초 동안 기계가 진동·발광.
- 한 단계 위로 갈수록 5배 → Rainbow 1개 = 일반 125개 상당. 변이 확률보다 비싸게 설정해 "운이 좋으면 빠르고, 안 좋아도 언젠가".
- **수익 연결**: "Furnace Speed" 게임패스(합성 대기 10초 → 0) — 확정 편의. 꾸미기 "합성로 스킨".

### R8. 행운 타일 (Hot Spot) — 노력 S ★
트레이 위 무작위 위치에 빛나는 원판이 생기고 45초마다 이동한다.
- 원판 위에서 일어난 합치기: **즉시 현금 30초치** + 변이 확률 ×2(무료).
- SHUFFLE·손으로 들기를 **어디에 놓을지** 고민하게 만든다(작은 판단 = 주목).
- **수익 연결**: 없음(참여도용). 판매 금지(확률 변경 포함).

### R9. 일일 연속 출석 + 무료 행운 바퀴 — 노력 S ★
- 7일 연속 출석 보상 증가: 1일 ◆5 … 7일 ◆50 + 꾸미기 상자(확정 꾸미기 중 고르기). 하루 놓치면 1일로가 아니라 **2단계 후퇴**(박탈감 완화).
- 하루 1회 무료 바퀴(현금·SHUFFLE·◆·부화 가속). **유료 추가 회전·젬 회전은 만들지 않는다**(간접 유료 랜덤 [R1]).
- **수익 연결**: Factory Plus 구독에 "출석 보상 ×2"(확정).

### R10. 마일스톤 수입 배수 확대 — 노력 S ★
AdVenture Capitalist식 "큰 한 방"을 등급 쪽에도.
- 등급별 **누적 합치기 횟수** 25·100·500회마다 그 등급 수입 ×2(영구, 리버스 시 초기화). 패널에 "T6 merges 87/100 → INCOME x2" 막대.
- 14 §3.2(POLISH·SPEED 마일스톤)와 같은 연출 재사용.
- **수익 연결**: 간접(성장 속도 → 시간 단축 상품 수요).

### R11. 플롯 전시대 (Showcase) — 노력 M ★
"보이는 지위". 내 최고 큐브 3개를 플롯 입구 받침대에 전시(실물 크기·변이 외형 그대로). 다른 플레이어가 보고 "Like"(하루 1회) → 주인에게 ◆1, 주간 Like 순위.
- **수익 연결**: 전시대 스킨·조명(확정 꾸미기, ◆ 또는 R$).

### R12. Mega Merge (여러 개 동시 합치기) — 노력 M ★
Merge Dragons 5개 합치기 보너스의 물리판. 같은 등급 **4개 이상이 0.5초 안에 한 덩어리로 합쳐지면** "MEGA!" 연출과 함께 등급+1 큐브 1개를 **추가로** 준다(재료 약 1/3 절약 효과, [M1]). SHUFFLE 직후 자주 일어나 SHUFFLE 체감이 커진다.
- 물리 판정이 까다로워(동시 접촉 그룹 탐지) 우선순위 낮음.

### 우선순위 요약

| 순위 | 이름 | 노력 | 도파민 축 | 수익 연결(확정만) |
|---|---|---|---|---|
| 1 | R1 황금 큐브 | S~M | 변동 보상·주목 | Golden Magnet 패스, Frenzy 확정 상품 |
| 2 | R2 선물 큐브+무료 천장 | S | 변동 보상 | SHUFFLE·젬 소비 확대 |
| 3 | R3 공장 날씨 | M | 기대·co-play·수집 | 사설 서버, 사설 서버 Overclock 호출 |
| 4 | R4 머지 피버 | S | 실력·연쇄 | SHUFFLE 상품 수요 |
| 5 | R5 서버 알림·첫 발견 | S | 자랑·지위 | 칭호(패스 보상) |
| 6 | R6 부화 연출+품질 | S~M | 기대·재방문 | Instant Hatch(정책 안전화) |
| 7 | R7 변이 합성로 | M | 수집 완료 | Furnace Speed 패스 |
| 8 | R8 행운 타일 | S | 주목 | — |
| 9 | R9 출석+무료 바퀴 | S | 습관 | Factory Plus ×2 |
| 10 | R10 등급 마일스톤 | S | 큰 한 방 | 간접 |
| 11 | R11 전시대 | M | 지위 | 전시 꾸미기 |
| 12 | R12 Mega Merge | M | 손맛 | 간접 |

**합산 경제 영향 주의**: R1(+15~25%) + 변이(+7%) + R4 피버(+5~10%) + R3 날씨(+5~10%)를 모두 켜면 총수입이 약 1.4~1.5배. `tools/pacing_sim.py`에 이벤트 기대값을 넣어 비용 배율 k를 다시 맞춰야 리버스 1회 45~60분 목표(05 §4.5)가 유지된다.

---

## 5. 측정
- `LogCustomEvent`: `GoldenCubeSpawn`/`GoldenCubeCaught`(잡은 비율 목표 ≥60%), `GiftOpened`, `WeatherStart`, `FeverStart`, `FuseUsed`.
- 비교 지표: 세션 길이, D1, 세션당 화면 상호작용 수(탭·들기), Golden Magnet 구매율.
- 날씨 예고가 재접속을 만드는지: 예고 표시 후 날씨 시작 시점의 동접 변화.

---

## 출처
- [G1] Pocket Tactics, "Grow a Garden mutations" — https://www.pockettactics.com/grow-a-garden-mutations
- [G2] Sportskeeda, "All mutations in Grow a Garden" — https://www.sportskeeda.com/roblox-news/all-mutations-grow-garden
- [G3] Pocket Tactics (같은 문서, 날씨·변이 표, 최대 ×201,050) — https://www.pockettactics.com/grow-a-garden-mutations
- [G4] AllThingsHow, "Admin abuse in Grow a Garden 2: what it is" — https://allthings.how/admin-abuse-in-grow-a-garden-2-what-it-is-and-whether-it-has-happened/
- [G5] Lenovo Gaming, "Roblox Just Shattered the All-Time Record for Concurrent Players" — https://gaming.lenovo.com/roblox/post/roblox-just-shattered-the-all-time-record-for-concurrent-players-8s7u0nswtSVrLpi
- [B1] rblxguide, "Steal a Brainrot Mutations" — https://rblxguide.com/games/steal-a-brainrot/mutations
- [B2] Deltia's Gaming, "Complete Mutations Guide for Steal a Brainrot" — https://deltiasgaming.com/?p=299967
- [PS1] Pet Simulator Wiki, "Gamepasses (Pet Simulator 99)" — https://pet-simulator.fandom.com/wiki/Gamepasses_(Pet_Simulator_99)
- [PS2] Twinfinite, "Rainbow pets in Pet Simulator 99" — https://twinfinite.net/guides/rainbow-pets-pet-simulator-99/
- [N1] AllThingsHow, "Merge a Nuke mutations: all effects and the best ones to use" — https://allthings.how/merge-a-nuke-mutations-all-effects-and-the-best-ones-to-use/
- [N2] Bloxodes, "Merge a Nuke mutations guide" — https://bloxodes.com/articles/merge-a-nuke-mutations-guide
- [N3] AllThingsHow, "Merge a Nuke update schedule" — https://allthings.how/merge-a-nuke-update-schedule/
- [BS1] Bee Swarm Simulator Wiki, "Royal Jelly" — https://bee-swarm-simulator.fandom.com/wiki/Royal_Jelly
- [BS2] Bee Swarm Simulator Wiki, "Mutation" — https://bee-swarm-simulator.fandom.com/wiki/Mutation
- [C1] Cookie Clicker Wiki (wiki.gg), "Golden Cookie" — https://cookieclicker.wiki.gg/wiki/Golden_Cookie
- [C2] Cookie Clicker Wiki (wiki.gg), "Wrath Cookie" — https://cookieclicker.wiki.gg/wiki/Wrath_Cookie
- [E1] Android Central, "Egg, Inc.: tips and tricks" — https://www.androidcentral.com/tips-and-tricks-egg-inc
- [E2] r/EggsInc, "Beak doesn't actually guarantee GE" (2024-12) — https://redlib.ssps.io/r/EggsInc/comments/1hc0tma/beak_doesnt_actually_guarantee_ge
- [A1] Steam Community, AdVenture Capitalist 토론(Angel 2%) — https://steamcommunity.com/app/346900/discussions/0/364039785169128886
- [A2] AdVenture Capitalist Wiki, "Businesses" — https://adventure-capitalist.fandom.com/wiki/Businesses
- [M1] Merge Dragons 공식, "Tips and Tricks" — https://www.mergedragons.com/tips-and-tricks
- [M2] BlueStacks, "Merge Dragons tips and tricks" — https://www.bluestacks.com/blog/game-guides/merge-dragons/md-tips-and-tricks-en.html
- [P1] PSU, "The slot machine psyche: how variable ratio reinforcement drives modern gaming engagement" — https://www.psu.com/news/the-slot-machine-psyche-how-variable-ratio-reinforcement-drives-modern-gaming-engagement/
- [P2] Gfinity, "Why in-game gambling mechanics hook us even when there is no money on the line" — https://www.gfinityesports.com/article/why-in-game-gambling-mechanics-hook-us-even-when-there-is-no-money-on-the-line
- [R1] Roblox Creator Hub, "Paid random items policy guidelines" — https://create.roblox.com/docs/production/monetization/paid-random-items
- [R2] Roblox Creator Hub, "PolicyService" — https://create.roblox.com/docs/reference/engine/classes/PolicyService
- [R3] TechTimes, "Korea's loot box rules push Roblox to disclose item odds worldwide" (2026-06-26) — https://www.techtimes.com/articles/319148/20260626/koreas-loot-box-rules-push-roblox-disclose-item-odds-worldwide.htm
- 팬 위키·가이드(G·B·PS·N·BS·C·E·A)는 비공식이며 업데이트마다 값이 바뀐다. 구조와 크기 감만 차용하고, 수치는 우리 시뮬레이션으로 확정한다.
