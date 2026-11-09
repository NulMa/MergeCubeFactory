# 16. 변이 큐브 · 도감 · 꾸미기 · 젬

기준일 2026-10-18. 계기: 사용자 요청 "도파민이 더 필요. 크기·등급별로 메탈·레인보우·네온 같은 특별한 큐브가 확률로 나오고 돈을 더 주고, 모으면 꾸미기나 추가 재화를 준다."
수치 근거: docs/15 조사 권장값(흔한 변이는 작은 배수, 드문 변이는 큰 배수, 기대 수입 증가는 한 자릿수~십수 %).

## 1. 변이 표

| 변이 | 수입 배수 | 합치기로 생길 때 | 투하로 생길 때 | 첫 발견 젬 | 겉모습 |
|---|---|---|---|---|---|
| 일반 (Normal) | ×1 | — | — | — | 기존 등급 색 |
| Metallic | ×1.5 | 2.5% (1/40) | 0.5% | 2◆ | Metal 재질 + 은빛 섞임 + 반사, 이름표 |
| Neon | ×3 | 0.8% (1/125) | 0.16% | 5◆ | Neon 재질 + 빛(PointLight) + 반짝이 |
| Rainbow | ×8 | 0.18% (1/550) | 0.036% | 10◆ | 색이 무지개로 돎(클라이언트) + 빛 + 반짝이 |
| Galaxy | ×25 | 0.025% (1/4,000) | 0.005% | 25◆ | 보라 유리 + ForceField 껍데기 + 색 돎 + 빛 + 반짝이 |
| Cosmic | ×70 | 0.01% (1/10,000) | 0.002% | 60◆ | 거의 검은 남보라 몸통 + 면마다 흐르는 별 무늬 + 짙은 유리 껍데기("사건의 지평선") + 둘레를 도는 별무리 두 줄기 + 수평으로 퍼지는 강착 고리 + 보라↔청록 맥동 테두리 |
| Divine | ×200 | 0.002% (1/50,000) | 0.0004% | 150◆ | 흰 금빛 몸통 + 금빛 ForceField + 머리 위에 둥실거리는 금빛 고리 + 뒤에서 도는 햇살(Sunburst) + 위로 솟는 빛줄기 + 강한 금빛 빛 + 금↔흰 맥동 테두리 |

- **사다리 확장 (2026-10-18)**: "조금 하면 특별 큐브·콤보가 너무 흔해서 '좋은 거 떴다!'가 사라진다"는 피드백. 아래 4단을 조금 더 드물게(Metallic 4→2.5%, Neon 1.2→0.8%, Rainbow 0.25→0.18%, Galaxy 0.03→0.025%) 하고 위에 Cosmic·Divine을 얹어 항상 더 드문 목표가 남게 했다. 초반 첫 특별 큐브는 그대로 빠르다(합치기 한 번에 어떤 변이든 3.5%, 60번이면 88%).

- 공식·확률: `game/src/merge/shared/Economy.luau` `Economy.VARIANTS`. 겉모습: `Config.VARIANT_STYLE`. 큐브 Attribute `Variant`(일반은 없음), 태그 `VariantCube`.
- 투하 확률 = 합치기 확률의 1/5. 드로퍼는 초당 수십 개를 떨어뜨리므로 그 이상이면 흔해진다.
- 이름표(BillboardGui)는 `AlwaysOnTop=false`: 큐브 뒤로 가려지는 게 자연스럽고 Studio 화면 캡처에도 찍힌다.
- 무지개 색 돌리기는 클라이언트 `Fx.luau`의 RenderStepped에서 태그된 큐브만 돈다(서버 비용 0, 복제 트래픽 0).
- 등급 크기·색(`Config.cubeSize`, `Config.TIER_COLORS`)은 건드리지 않는다. 등급 수는 `Economy.MAX_TIER`를 따른다(다른 브랜치에서 바뀔 수 있음).

## 2. 합치기 규칙 — "약해져서 이어짐 + 같은 변이는 융합"

합치기 결과 변이 = **max(새로 굴린 변이, 이어받은 변이)**
- **이어받기**: 두 큐브 중 좋은 변이가 **한 단계 약해져서** 남는다. Divine → Cosmic → Galaxy → Rainbow → Neon → Metallic → 일반.
- **융합(FUSION)**: 같은 변이(일반 제외) 둘이 합쳐지면 **한 단계 올라간다**. Metallic+Metallic → Neon … Galaxy+Galaxy → Cosmic, Cosmic+Cosmic → Divine, Divine+Divine → Divine(맨 위).
- 그 위에 새로 굴린 결과가 더 좋으면 그것이 된다.

"더 좋은 변이를 그대로 유지" 대신 이 규칙을 고른 이유:
1. **희귀함이 무너진다.** 12등급 큐브 하나는 1등급 기준 2천 번 넘는 합치기를 거친다. 그대로 유지하면 그 중 한 번만 Galaxy가 떠도 끝까지 남아, 계산상 높은 등급은 대부분 최상위 변이가 된다. 그러면 Galaxy가 "흔한 것"이 되고 기대 수입이 ×10 이상으로 튀어 경제가 무너진다.
2. **잃는 느낌을 줄였다.** 그냥 사라지면(이어받기 없음) 귀한 큐브가 다음 합치기에서 증발한다. 한 단계씩 약해지면 다음 등급 수입(×2.4)이 대부분 메워 준다. 예: Rainbow(×8) + 일반 = 9 → 다음 등급 Neon(×3 × 2.4 = 7.2).
3. **융합은 새 잭팟**이다. 같은 변이 둘이 만나면 위로 올라가는 순간이 생긴다("FUSION! NEON!").

연출 종류(서버 → `Fx("variant", pos, tier, id, how, isNew, gems)`):
- `roll`(새로 뜸), `fusion`(융합), `drop`(투하에서 뜸): 항상 크게 알림.
- `keep`(이어받으며 약해짐): 그 (등급, 변이)가 **처음 발견**일 때만 알림.

## 3. 큰 연출
| 변이 | 소리 | 화면 |
|---|---|---|
| Metallic | 반짝 + 차임 | 글자 "METALLIC!", 반짝이, 고리 |
| Neon | + 더 높은 차임 | + 옅은 섬광 |
| Rainbow | + 팡파레(NewBest) | 무지개 섬광 3번, 무지개 반짝이, FOV 펀치 |
| Galaxy | + 쿵(Boom) + 레벨업 | 무지개 섬광 6번, 큰 흔들림, FOV 펀치 9 |
| Cosmic | (같음, 더 크게) | 짙은 남색 섬광 → 무지개 섬광 8번, 큰 고리 두 겹, FOV 펀치 11 + **서버 전체 토스트** "OO found a COSMIC tier N cube!" |
| Divine | (같음, 더 크게) | 흰 금빛 섬광 → 무지개 섬광 10번, 큰 고리 두 겹, FOV 펀치 14 + **서버 전체 토스트** |
- 서버 전체 토스트 기준: `Economy.TOAST_VARIANT`(= Cosmic) 이상. 예전엔 맨 위(Galaxy)만이었다.
- 첫 발견이면 위에 "NEW! CLAIM +N◆"가 한 번 더 뜬다(젬은 도감에서 눌러 받음, §5). 도감 마일스톤에 닿으면 "MILESTONE! CLAIM +N◆ IN COLLECTION".
- 분석 이벤트: `LogCustomEvent("VariantFound", rank, {id, how})`.

## 4. 경제 영향 (pacing)
- 수입: `Economy.trayIncomeOf(cubes, mult)` = Σ 등급 수입 × 변이 배수 × 공통 배수(테스트: `tests/Economy.spec.luau`).
- 자동 판매(트레이 넘침)는 **가장 값싼 큐브**(변이 포함)를 판다. 낮은 등급 Rainbow가 먼저 팔리지 않게. 판매가도 변이 배수 포함.
- 기대 배수: 같은 등급끼리 무작위로 짝지어진다고 보고 등급별 변이 분포를 차례로 계산한다(`Economy.variantMeanByTier`, 시뮬 `variant_mean_by_tier`와 같은 식).

| 등급 | 1 | 2 | 4 | 6 | 8 | 10 | 12 |
|---|---|---|---|---|---|---|---|
| 평균 변이 배수 | 1.012 | 1.063 | 1.100 | 1.110 | 1.112 | 1.113 | 1.113 |

- 사다리 확장 뒤 값(확장 전 맨 끝 1.134). 수입은 높은 등급 큐브가 대부분이므로 **실질 +11% 수입**. COST_SCALE 재보정은 docs/13 §9.1.
- (확장 전 기록) **실질 +13% 수입**. docs/15의 +6.9%는 이어받기 없이 합치기 한 번만 본 값이고, 이어받기·융합이 붙어 약 두 배가 된다.
- `tools/pacing_sim.py` MergeGarden은 이 기대 배수(마지막 등급 값)를 공통 배수에 곱한다. `--no-variants`로 끄면 예전 기준.
- 시뮬 결과·보정 메모: §8.
- 개인차: 평균은 +13%지만 운 좋은 플레이어는 상위 큐브 하나가 Rainbow/Galaxy가 되어 순간 수입이 몇 배 뛴다. 이 "튀는 순간"이 도파민 장치다. 그 큐브가 다음 합치기에서 한 단계 약해지므로 오래 가지 않는다.

## 5. 도감 (CODEX)
- 칸 = 등급 × 일반 아닌 변이 = `Economy.MAX_TIER × 6`(지금 40 × 6 = **240칸**). CODEX 탭의 변이 탭은 6개라 두 줄(한 줄 3개)로 놓는다. Cosmic·Divine 칸은 테두리가 두 색 사이로 맥동한다. 저장: `data.variants["7:Rainbow"] = true`. 기존 `data.codex["7"]`(등급 도달)는 그대로 둔다.
- 첫 발견마다 변이별 젬(위 표). 발견 수 마일스톤마다 추가 젬:

| 발견 수 | 1 | 3 | 5 | 10 | 15 | 20 | 30 | 40 | 60 | 80 | 120 | 160 | 200 | 전부(240) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 젬 | 10 | 10 | 15 | 25 | 30 | 40 | 60 | 80 | 100 | 120 | 150 | 200 | 250 | 400 |

- 앞 8단은 그대로, 240칸에 맞춰 뒤를 늘렸다(마일스톤 합 1,490◆). 마지막 칸들은 Divine이라 사실상 장기 목표.

- **눌러서 받기 (2026-10-19)**: 젬은 자동 지급하지 않는다. 발견하면 `data.codexUnclaimed["7:Rainbow"] = 젬`에 쌓이고, 도감에서 그 칸(금색 테두리 "CLAIM +N◆")을 누르면 받는다(`ClaimCodex` remote). 마일스톤도 막대가 금색 "TAP TO CLAIM"으로 바뀌고 하나씩 눌러 받는다. HUD COLLECTION 버튼에 받을 개수 배지, 패널을 열면 첫 보상 칸이 있는 변이 탭·페이지로 이동. 연속으로 받으면 동전 소리가 한 음씩 올라간다(`Fx.purchase`). 훔쳐 온 큐브(docs/22)도 같은 경로. 기존 저장은 이미 자동으로 받았으므로 그대로.
- 마일스톤 개수가 전체 칸보다 크면 "전부"로 줄여 쓴다(`Economy.milestoneCount`) — MAX_TIER가 바뀌어도 동작. 받은 수는 `data.codexMilestone`.
- 무료로 모을 수 있는 젬 합계(12등급): 첫 발견 12 × (2+5+10+25) = 504 + 마일스톤 420 = **924◆**.
- 패널: HUD 왼쪽 위 현금 밑 `◆ N  COLLECTION X/Y` 버튼(게임패드 L1). CODEX 탭 = 변이별 줄 × 등급 칸(발견 칸은 등급 색 + 변이 색, 아니면 "?") + 다음 마일스톤 막대.

## 6. 꾸미기 (STYLE 탭)
칸 7개(bat·pet·aura·trail·tray·dropper·island; 2026-10-19에 bat·aura, 이어서 pet·island 추가), 칸마다 하나 장착. 해금 = 도감 발견 수(무료) 또는 젬 구매(확정). 저장 `data.cosmetics = { owned, equipped }`.

| 칸 | 이름 | 해금 | 효과 |
|---|---|---|---|
| tray | Classic Tray | 기본 | 남색 바닥 |
| tray | Marble Tray | 도감 3 | 흰 대리석 바닥 |
| tray | Ice Rink | 60◆ | 얼음 바닥 |
| tray | Neon Grid | 도감 10 | 빛나는 남색 바닥 |
| tray | Gold Vault | 200◆ | 금박 바닥 |
| dropper | Steel Dropper | 기본 | Metal |
| dropper | Diamond Plate | 40◆ | DiamondPlate |
| dropper | Neon Dropper | 도감 5 | Neon(등급 색으로 빛남) |
| dropper | Crystal Dropper | 도감 20 | Glass |
| trail | No Trail | 기본 | — |
| trail | Sparkle Trail | 도감 1 | 흰·하늘 꼬리 |
| trail | Gold Trail | 80◆ | 금색 꼬리 |
| trail | Rainbow Trail | 도감 30 | 무지개 꼬리 |
| bat | Aluminum Bat | 기본 | 은색 금속 + 빨간 띠 |
| bat | Classic Wood | 도감 3 | 나무 + 검은 띠 |
| bat | Neon Bat | 도감 25 | 분홍 네온 + 청록 띠 |
| bat | Golden Bat | 120◆ | 금박 |
| bat | Crystal Bat | 도감 50 | 유리 |
| bat | Rainbow Bat | 도감 100 | 마디마다 다른 색 |
| tray | Garden Lawn / Wooden Deck / Castle Floor | 도감 6 / 14 / 45 | 잔디·나무 판자·자갈 바닥 |
| tray | Sunny Beach / Lava Floor | 50◆ / 150◆ | 모래·용암 바닥 |
| dropper | Wooden Crate / Brick Chimney | 도감 8 / 30 | 나무 판자·벽돌 재질 (색은 드로퍼 등급 색 유지) |
| dropper | Ice Block / Lava Dropper | 60◆ / 120◆ | 얼음·용암 재질 |
| island | Grass Island | 기본 | 잔디 섬 |
| island | Desert / Snow / Stone / Crystal | 도감 4 / 16 / 38 / 95 | 모래·눈·슬레이트·유리 섬 바닥 |
| island | Candy / Volcano | 80◆ / 160◆ | 분홍 사탕·현무암 섬 바닥 |
| trail | Heart / Snowflake Trail | 도감 22 / 75 | 하트·눈송이 무늬가 줄지어 찍힘 |
| trail | Music Trail | 70◆ | 음표 무늬 |
| bat | Fish Slap / Baguette / Candy Cane / Builder Hammer | 도감 8 / 18 / 35 / 70 | 메시 배트 (생선·바게트·사탕지팡이·망치) |
| bat | Frying Pan / Rubber Chicken | 90◆ / 180◆ | 메시 배트 |
| pet | No Pet | 기본 | — |
| pet | Cube Buddy / Rubber Duck / Chick / Frog / Ghost Cat | 도감 2 / 10 / 20 / 40 / 60 | 오른쪽 어깨 옆에서 따라다님 |
| pet | Jellyfish / Mini UFO | 90◆ / 160◆ | 〃 |

- **오라 단계식 (2026-10-19, 사용자 "전부 인게임 재화 해금 + 이전 단계 해금해야 다음 단계 / 장착·해제 / 상위 오라일수록 넉백 저항 / 단계별로 점점 강해 보이게")**:

  | 단계 | 오라 | 젬 | 넉백 저항 | 보이는 것 |
  |---|---|---|---|---|
  | 1 | Bubble | 20 | 5% | 거품 입자 |
  | 2 | Heart | 30 | 10% | 하트 |
  | 3 | Blossom | 45 | 15% | 꽃잎(떨어짐) |
  | 4 | Ember | 60 | 20% | 불씨 반짝이 + **몸 빛남(PointLight)** |
  | 5 | Snowfall | 80 | 25% | 눈송이 |
  | 6 | Frost | 100 | 30% | 얼음 반짝이 |
  | 7 | Music | 125 | 35% | 음표 + **발밑 고리 퍼짐** |
  | 8 | Star | 150 | 40% | 노랑·보라 반짝이 |
  | 9 | Storm | 180 | 45% | 번개 |
  | 10 | Flame | 220 | 50% | 불꽃 + **위로 솟는 빛기둥** |
  | 11 | Galaxy | 260 | 55% | 보라·청록 (Collector 패스로도 받음) |
  | 12 | Divine | 300 | 60% | 무지개 |
  - 단계가 오를수록 입자 수(+1.2~1.6/단계)·크기(+6%/단계)·빛 밝기·고리·기둥 세기가 커진다.
  - 젬으로만 산다. 앞 단계를 **모두** 가져야 다음 단계를 살 수 있다(`Collection.buy` → `missingTier`). 합계 1,575◆(장기 목표).
  - 넉백 저항은 **지금 낀** 오라 단계로(`Economy.auraResist`, 단계당 5%). `Steal.batHit`이 맞은 사람에게 주는 속도에 (1 - 저항)을 곱한다. 들고 있던 큐브를 떨어뜨리는 건 그대로.
  - 장착/해제: 낀 것을 다시 누르면 그 칸 기본값(오라는 No Aura)으로 벗는다 — 모든 칸 공통. 버튼 `UNEQUIP`.
  - 예전 도감 수로 열렸던 오라(하트 12·불씨 15·거품 28·눈 55·꽃잎 85·불꽃 100·디바인 120)는 도감 수가 됐으면 소유로 옮겨 준다(`migrate`, 한 번).
- **에셋 다양화 (2026-10-19, 사용자 "치장요소가 색깔놀이인 게 너무 많음")**:
  - 배트·펫 메시는 Creator Store 무료·스크립트 없는 모델에서 메시 id만 가져와 `SpecialMesh`로 붙인다(런타임에 MeshPart.MeshId는 못 바꿈). 출처는 `Config.COSMETICS[*].mesh.source`에 모델 id·만든 사람으로 남겼다. 다른 게임 IP(펫 시뮬레이터 X·마인크래프트·스폰지밥·산리오 등)를 베낀 모델은 뺐다.
  - 오라·꼬리 무늬 텍스처는 자작(`tools/make_particles.py` → `images/P*.png`), 불꽃은 Roblox 기본 `rbxasset://textures/particles/fire_main.dds`.
  - 펫: 캐릭터 안 `CosmeticPet` 파트 + `AlignPosition/AlignOrientation`로 HumanoidRootPart의 `PetAnchor`를 따라감(네트워크 주인 = 플레이어). 메시 앞이 -Z가 아니면 `mesh.yaw`로 돌림(오리 -90).
  - 메시 배트: 원기둥 조각을 숨기고 `SkinMesh` 하나를 손잡이에 용접. 판정은 그대로 서버 범위.
  - Studio 확인: `StudioDebug:Invoke("cosmetic", player, id)` = 강제 해금 + 장착.

- 구현: 바닥 `TrayFloor` 색·재질, 드로퍼 재질(색은 드로퍼 등급 색 유지), HumanoidRootPart 아래 `Cosmetic` 속성 Attachment에 Trail/ParticleEmitter. 서버가 만들어 모두에게 보인다(자랑). 플롯을 떠나면 기본값으로 되돌림.
- 배트 스킨: 서버가 가방·손·StarterGear의 Bat 도구 몸통(Taper1~3·BarrelBody)·띠(Band)·휘두르기 궤적 색을 바꾼다(`Collection.applyBat`). 오라는 꼬리와 따로 장착(같은 Attachment 방식). 예전 저장에서 꼬리 칸에 있던 오라는 오라 칸으로 옮긴다(`migrate`).
- 젬 가격 합계 750◆(배트·오라 추가 뒤) < 무료 젬 924◆: 무료 플레이어도 모두 살 수 있다(시간이 걸릴 뿐).
- Remote: `Equip(id)`, `BuyCosmetic(id)`. 서버가 소유·해금·잔액을 확인한다.

## 7. 젬과 수익화 규칙
- 젬 용도: **꾸미기 구매만**(확정 효과). 나중에 늘린다면 시간 단축(부화 즉시 완료)처럼 확정 효과만.
- 젬은 나중에 Robux(젬 팩·구독)로 간접 구매될 수 있으므로 **젬으로 사는 모든 것은 확정**이어야 한다. 랜덤 상자·변이 확률 증가는 젬으로도 Robux로도 팔지 않는다(DECISIONS 2026-10-18, 유료 랜덤 금지).
- 젬 상품: Gem Pouch 40 / Pack 120 / Chest 700 (docs/03 §2). STYLE 탭 버튼은 Gem Pack(120)을 띄운다.
- 상점 전용 꾸미기(`Cosmetic.shop`): Starter Trail(스타터 팩), Galaxy Aura(Collector 패스). 젬·도감으로는 못 연다.
- 변이 확률은 무료 플레이로만 얻는다. "Lucky Boost"류 유료 확률 상품은 만들지 않는다(docs/03 표의 Lucky Boost는 이 기능에 적용하지 않음).

## 8. 시뮬레이션 결과
`python -I tools/pacing_sim.py --only MergeGarden` (변이 기대 배수 ×1.134 적용, 2026-10-18):

| 항목 | 변이 없음 (기존) | 변이 있음 |
|---|---|---|
| 보정값 k (regular 35일 엔드게임) | 3.71e4 (`Economy.COST_SCALE`, docs/13 §7) | **4.23e4** (+14%) |
| 엔드게임 일 (casual / regular / engaged / hardcore) | — | >60 / 35 / 22 / 15 |
| 첫 세션 (첫 보상 / 첫 구매 / 첫 타이머 / 첫 부화) | — | 1초 / 3초 / 12초 / 2.2분 |
| 접속 이유/일 (regular) | — | 6.68 |

- 해석: 수입이 13% 늘어난 만큼 k도 14% 올려야 같은 35일이 된다. 지금 COST_SCALE(3.71e4)를 그대로 두면 엔드게임이 하루 남짓 당겨지는 정도라 출시 전 문제는 아니다.
- **보정 보류**: COST_SCALE은 바꾸지 않았다. MAX_TIER를 바꾸는 브랜치(tiers)와 합친 뒤 시뮬을 다시 돌려 한 번에 보정한다(`--no-variants`로 기존 기준과 비교 가능).
- 시뮬은 트레이를 등급별 개수로만 다루므로 변이를 큐브마다 추적하지 않고 기대 배수를 곱한다. 운 좋은 큐브가 만드는 순간적인 수입 급등은 시뮬에 나오지 않는다.

## 9. 테스트·디버그
- `tests/Economy.spec.luau`: 굴리기·이어받기·융합·수입·기대 배수 범위(1 < 평균 < 2)·저장 형식 호환·도감 마일스톤·꾸미기 해금.
- 저장 호환: `data.tray` 항목은 예전처럼 숫자(일반) 또는 `{ t = 등급, v = "Rainbow" }`. 모르는 변이 id는 일반으로 읽는다. 새 키는 ProfileStore `Reconcile`이 채운다.
- Studio 전용 `ServerScriptService.StudioDebug:Invoke("luck", player, 배율)` — 변이 확률 배율(예 200). `"gems"`로 젬 지급. 게시 서버에는 훅이 없다.

## 10. 낮은 등급 보정과 연출 차등 (2026-10-19)
- **문제** (사용자 지적): 리버스 뒤 드로퍼가 높은 등급에서 시작하면 낮은 등급 큐브는 손 DROP으로만 나와서, 낮은 등급의 특수 큐브(도감 칸)를 채울 기회가 오히려 줄어든다.
- **보정**: `Economy.lowTierLuck(tier, dropperMin) = min(4, 1 + 0.5 × (dropperMin − tier))`. 지금 드로퍼 최저 등급보다 낮은 큐브의 변이 확률을 한 단계마다 +50%, 최대 4배. 서버 `luckFor(st, tier)`가 투하·합치기 굴림 모두에 곱한다.
- **연출 차등**: 보정 때문에 특수 큐브가 자주 뜰 수 있어서
  - 이미 도감에 있는 변이: 전조(오멘)·공개 연출 없이 짧은 반짝임만. Rainbow 이상도 기본 강도 −1 (`client/Hype.variant`, known)
  - 처음 보는 변이: 기본 강도를 한 단계 올리고 "NEW DISCOVERY" 배너. 서버 `suspense()`는 처음 보는 Rainbow 이상에만 전조를 건다.
