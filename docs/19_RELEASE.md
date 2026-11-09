# 19. 출시 준비 체크리스트

기준일 2026-10-18. 운영 게시와 공개 전환은 **사람이 한다** (CLAUDE.md). **2026-10-19: 게임 공개 완료** (`https://www.roblox.com/games/137640599837742/Merge-Cube-Factory`). 이 문서는 그 전에 끝낼 일과 결정할 일을 모은다.

## A. 사용자 결정이 필요한 것

| # | 결정 | 권장 | 이유 |
|---|---|---|---|
| A1 ✅ | 출시 유니버스 | **지금 테스트 유니버스(10771520503)를 그대로 공개 전환** (승인 2026-10-18) | 개발자 상품 12개와 패스 3개는 유니버스에 묶여 있다. 새 유니버스를 만들면 15개를 전부 다시 만들고 ID를 바꿔야 한다. 테스트 구매 기록도 같은 곳에 남는다 |
| A2 ✅ | 테스트 데이터 정리 (반영 완료: `MergeCubeFactory_Live1`, 랭킹 `MCF_Rank_*_Live1`) | **`Config.DATA_STORE` 이름을 출시용(`MergeCubeFactory_Live1`)으로 바꾼다** | DataStore 삭제 없이 모두 새로 시작한다(삭제는 승인 필요 작업이라 피한다). 예전 키는 그대로 남아 되돌릴 수도 있다 |
| A5 ✅ | Shuffle Pro 패스 정리 | Off Sale + "[RETIRED]" 이름 변경, 코드 삭제 | Roblox는 패스 삭제를 지원하지 않는다(API 404). 판매 중지가 할 수 있는 최대치 |
| A3 | 구매 처리 확인 | **Studio 테스트 구매(무료)** + API 접근 켜기 | 아래 "A3 방법" 참고. 실제 구매는 선택 |
| A4 | 공개 범위 | 처음 며칠은 공개 + 광고 없이 지표 관찰 | 첫 세션 이탈·구매 전환을 보고 수치를 고친 뒤 광고 |

### A3 방법: 돈 안 쓰고 영수증 처리 확인 (2026-10-18)

- 개발자용 코드로 상품을 주는 방식은 확인이 안 된다. 확인하려는 건 Roblox가 보내는 영수증(`ProcessReceipt`)을 받아 지급하고, 저장하고, 중복 지급하지 않는 흐름이다. 코드 지급은 이 흐름을 거치지 않아서, 이미 끝낸 Studio `grant` 확인과 같다.
- Studio의 구매 창은 **테스트 구매**라 Robux가 빠지지 않는다. 그래도 `ProcessReceipt`는 실제와 똑같이 불린다. 지금까지 확인이 안 된 이유는 Studio에서 저장(DataStore)이 꺼져 있었기 때문이다.
- 순서
  1. Studio에서 File → Open from Roblox로 테스트 플레이스(137640599837742)를 연다.
  2. Game Settings → Security → **Enable Studio Access to API Services**를 켠다.
  3. Play → 상점에서 Cash Bag 구매(테스트 창) → 돈이 들어오는지 확인 → 나갔다 다시 Play → 돈이 남아 있고 두 번 지급되지 않는지 확인한다.
- Studio에서는 저장소 이름 뒤에 `_Studio`가 붙는다(`Config.STUDIO_STORE_SUFFIX`). 그래서 테스트 데이터가 실서비스 저장소와 랭킹에 섞이지 않는다.
- 실제 구매도 해 보고 싶다면: 본인 게임에서 15 R$를 쓰면 판매 수익 70%(약 10 R$)가 보류 기간 뒤 돌아온다. 실제 손해는 약 5 R$다.

## B. 코드·게임 (Claude가 하고 결과 보고)

- [x] 희귀도 사다리(Cosmic/Divine) 병합, 시뮬레이션 재보정 (regular 엔드게임 75일)
- [x] 연출 피로 대책(docs/18) Studio 확인: 공개, 예고, 기록 배너, 조용한 합치기
- [x] `check.ps1` 전부 통과
- [x] 트레이 확장 강화를 pacing_sim에 반영 (docs/13 §9.2: regular 78일)
- [x] Studio 디버그 훅(StudioDebug, EventsDebug)이 `IsStudio()`일 때만 생기는지 확인
- [ ] 상점 15개 지급 확인 (Studio `grant`): 오류 0
- [ ] 휴대폰 해상도(Studio 기기 에뮬레이터 iPhone SE·태블릿)에서 HUD와 패널이 잘리지 않는지 확인
- [ ] 게임패드로 DROP, 업그레이드, 코어, 도감, 상점을 열 수 있는지 확인
- [ ] 테스트 유니버스 게시 후 실서버에서 30분 플레이 (오류 로그 0)
- [x] A2 반영: `DATA_STORE` 이름 변경

## C. 스토어 페이지 (docs/STORE_LISTING.md)

- [ ] 이름: Merge Cube Factory
- [ ] 설명: 갱신한 원문 붙여 넣기 (994자, 배트·광장 반영)
- [ ] 장르: Simulation / 하위 장르 Incremental Simulator(있으면)
- [x] 아이콘 512×512 (`game/assets/store/icon.png`)
- [x] 썸네일 1920×1080 5장 (`game/assets/store/thumb_*.png`). 광장 썸네일(5번)의 게시판 이름·수치는 촬영용 가짜 데이터다
- [ ] 지원 기기: Phone, Tablet, Computer, Console (B 게임패드 확인 뒤)
- [ ] 비공개 서버: 끄기 (초기에는 공개 서버로 사람을 모은다)

## D. 성숙도 설문 (Experience Questionnaire)

목표는 **Minimal 또는 Mild**이다(DECISIONS 2026-10-17). 지금 게임 기준 답:

| 항목 | 답 | 근거 |
|---|---|---|
| 폭력 / 피 | 없음 | 큐브 합치기뿐. "BOOM" 섞기는 만화식 폭발 연출이고 피해 대상이 없다 |
| 공포 / 거친 유머 / 비속어 | 없음 | |
| 로맨스 / 술·약물 | 없음 | |
| 도박 | 없음 | |
| **유료 랜덤 아이템** | **아니요** | 상점 상품은 결과가 정해져 있다. 젬(유료로도 삼)은 꾸미기 고정 상품에만 쓴다. 코어·황금 큐브 보상은 무료 플레이로만 얻는다 |
| 사용자 간 거래 | 없음 | |
| 텍스트 채팅 | Roblox 기본 채팅 | 별도 채팅 기능 없음 |

## E. 출시 당일 순서 (사람)

1. B 전부 체크, 마지막 커밋에서 `node tools/publish.mjs`로 테스트 유니버스 게시
2. Creator Hub에서 설명, 아이콘, 썸네일, 장르, 기기 입력
3. 성숙도 설문 확인 (D)
4. Experience 공개 설정을 Public으로 변경
5. 1시간, 24시간 뒤 Creator Hub Analytics 확인: 오류, 세션 길이, 구매 전환
