# 24. 펫 (알 뽑기 · 융합 · 수입 보너스)

2026-10-19 사용자 요청: "펫 뽑기 (재화는 큐브로 얻는 것), 좋은 펫일수록 수입 %, 같은 펫 3마리 → 같은 모델에 오라 + 더 큰 %, 종류 다양하게".

## 1. 재화: 조각 ◇ (Shards)
- 합치기마다 `Pets.shardsForMerge(tier) = 1 + (tier − 1) // 5` (띠마다 +1). 판매·구매 불가, **Robux로 얻는 길 없음** → 유료 랜덤 아님 (docs/DECISIONS 2026-10-18).
- 리버스해도 유지. 저장: `data.shards`.

## 2. 알 6종 (`shared/Pets.EGGS`)
| 알 | 값 ◇ | 펫 |
|---|---|---|
| starter | 50 | cube, chick, duck, piggy, frog, snowman |
| farm | 250 | chicken, sheep, pup, bunny, turtle, jelly |
| forest | 1,200 | deer, wolf, hoppy, panda, grizzly, ghostcat |
| safari | 6,000 | zebra, hyena, ostrich, hippo, lion, elephant |
| ocean | 30,000 | penguin, polar, slime, shark, croc, ufo |
| mythic | 150,000 | giraffe, tiger, rhino, goldcube, basilisk, rainbowcube |

- 알 안 비중 40 / 30 / 15 / 10 / 4.5 / 0.5 (mythic 알은 40 / 30 / 20 / 6 / 3.5 / 0.5). 등급은 순서대로 common → mythic. UI에 펫마다 확률 %를 그대로 보여 준다.
- 한 번에 1 또는 3개. 빈 장착 칸이 있으면 자동 장착.

## 3. 보너스
- **보너스 = 알 기본값 × 희귀도 배율 × 별 배율** (`Pets.bonus`, 2026-10-19 "높은 티어 펫일수록 %가 올라야"). 예전(희귀도만: common 2% … mythic 75%)은 시작 알 Epic과 사파리 알 Epic이 같은 15%였다.
- 알 기본값 (`EGGS.base`): starter 1.5% · farm 2.1% · forest 2.9% · safari 3.9% · ocean 5% · mythic 6.5%.
- 희귀도 배율 (`RARITIES.mult`): common 1 · uncommon 1.5 · rare 2.2 · epic 3.2 · legendary 5 · mythic 9.

| 알 \ 희귀도 (★1) | common | uncommon | rare | epic | legendary | mythic |
|---|---|---|---|---|---|---|
| starter | 1.5% | 2.25% | 3.3% | 4.8% | 7.5% | 13.5% |
| farm | 2.1% | 3.15% | 4.62% | 6.72% | 10.5% | 18.9% |
| forest | 2.9% | 4.35% | 6.38% | 9.28% | 14.5% | 26.1% |
| safari | 3.9% | 5.85% | 8.58% | 12.48% | 19.5% | 35.1% |
| ocean | 5% | 7.5% | 11% | 16% | 25% | 45% |
| mythic | 6.5% | 9.75% | 14.3% | 20.8% | 32.5% | 58.5% |

- 별 배수 `STAR_MULT = {1, 2.5, 6}` (최고: 신화 알 Mythic ★3 = 351%). 장착 3칸 합이 수입 배수에 `× (1 + 합)`으로 곱해진다 (`server/Factory.mult`).
- UI (2026-10-19): 펫 칸마다 위에 별, 아래에 별까지 곱한 보너스 %를 보여 준다. 도감 칸에도 % 표시 (`client/PetsUi`, `client/Collection`).

## 4. 융합 · 놓아주기 · 보관
- 같은 펫·같은 별 3마리 → 별 +1 (최대 ★3). 장착 안 된 것부터 쓴다. ★2 금빛 반짝임 + 빛, ★3 무지개 반짝임 + 고리 + 크기 1.25배.
- 보관 60칸, 놓아주기 환불 = 알 값 10% × 3^(별−1).
- 저장: `data.pets = { list = {{u, id, star}}, equipped = {u…}, nextUid, seen = {[id] = 최고 별}, hatched, migrated }`. 예전 꾸미기 펫(pet_cube 등)은 ★1 펫으로 옮긴다.

## 5. 리버스 러시 (같은 날 추가, "환생 뒤 초반은 빠르게")
- 리버스 직후 수입 ×3 (`RUSH_MULT`), 이번 판 최고 등급이 지난 판 상한 − 2에 닿으면 끝 + 알림.
- 드로퍼는 `startTier(r) = clamp(1 + r, 1, min(8, 상한))` 등급부터 시작.

## 6. 그리기 (클라이언트)
- 서버는 플레이어 속성 `Pets = "id:star,…"`만 둔다. `client/PetFollow`가 모든 플레이어의 펫을 로컬로 만들어 스프링으로 따라가게 한다 (깡총·기울기·대기 중 둥실, ufo·jelly·ghostcat은 날기). 220스터드 밖은 숨김.
- 모양: `client/PetLook` — 모델 조각표(`shared/PetModels`, 생성 파일) 또는 메시 또는 큐브. 앵커 조각을 `BulkMoveTo`로 옮긴다 (클라이언트 앵커 루트에 WeldConstraint가 따라오지 않았다).

## 7. 자산 출처 (스크립트 없는 Creator Store 무료 모델, 조각 단위로 옮김)
- 7902208283 Animal Pack (MRNOOB_504)
- 97050466582003 Stud-Themed Animal Pack LITE (DropKit)
- 18873463683 pet pack (Ralidin123)
- 77983237466020 Animals/Pets (Dandan042899)
- 펫별 대응은 `tools/make_pet_models.py`의 PICK. 유명 게임 펫을 베낀 모델은 쓰지 않았다. 메시에 데칼 얼굴이 깨지는 모델(레몬·생강·코코아 고양이)은 빼고 ostrich·hippo·hoppy로 바꿨다.

## 8. 테스트·디버그
- `lune run tests/Pets.spec.luau` (비중 합, 굴림 경계, 보너스(알 × 희귀도 × 별), 조각, 러시, 낮은 등급 보정).
- Studio: `StudioDebug:Invoke("pet", player, "tiger:2")`, `StudioDebug:Invoke("shards", player, 1e6)`.
