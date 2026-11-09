# 26. 홍보·마케팅 점검과 할 일 (2026-10-21)

> 사용자 요청 (2026-10-21): "개선 다하고나면, 홍보나 마케팅 관점에서의 개선점이나 시행할 항목들도 조사해서, 너가 할 수 있는 선에서부터 시작해".
> 대상은 테스트 유니버스 10771520503 (플레이스 137640599837742). 외부 게시·상품 생성은 사용자 승인 후.

## 1. 지금 상태 (2026-10-21, 공개 API로 확인)
| 항목 | 상태 | 문제 |
|---|---|---|
| 방문 | 12, 좋아요 2 / 싫어요 0 | 추천 신호를 쌓을 표본이 아직 없다 |
| 장르 | All | 검색·추천 분류에 불리 |
| 썸네일 | 1장 공개 | 5장 만들어 둠(`game/assets/store/thumb_i_*.png`), 미업로드 |
| **서버 크기** | **50** | **플롯은 8개 → 9번째 사람부터 "This server is full"로 튕김.** Open Cloud로 고치려 했으나 키에 `universe.place:write` 권한이 없어 403 |
| 연령 등급 | API에서 AGE_RATING_UNSPECIFIED | DECISIONS엔 2026-10-18 설문 제출. 등급이 없으면 개발자에게만 보일 수 있다 |
| 스토어 설명 | 2026-10-18 기준 | 보스 레이드·펫·훔치기·출석 선물이 없었다 → 이번에 고침 (STORE_LISTING) |
| 친구 초대 | HUD "INVITE FRIENDS +20% TOGETHER" 버튼 (client/LoginUi, `SocialService:PromptGameInvite`) | 이미 있음 |
| TikTok | 7편 게시·예약 (10/19~10/24, marketing/shorts_schedule.md) | 계속 |

## 2. Roblox 추천이 보는 것 (공식 문서)
Recommended For You 순위 신호, 대략 중요한 순 [discovery]:
1. **플레이 전환율**: 썸네일·이름을 보고 실제로 들어오는 비율 → 썸네일이 직접 좌우.
2. **첫 플레이 이탈**: 60초 안, 61~180초 안에 나가는 비율 → 첫 1분 경험(튜토리얼·첫 합치기).
3. **다시 온 날**: D1, D2~7, D8~28 → 출석 선물·방치 수입·알림.
4. **플레이 시간**: 하루 60분까지만 센다.
5. **의도한 함께 놀기**: 친구 참가·초대·비공개 서버로 함께 논 날 → 초대 보너스·레이드.
6. 자격 있는 세션, 결제한 날·Robux.

그 밖에 [discovery, discovery-faq]:
- 홈 노출에는 **직접 만든 썸네일**이 필요. 썸네일 개인화(여러 장 중 사람마다 잘 맞는 것)는 바꾼 뒤 **최소 7일** 두고 본다.
- **콘텐츠 업데이트**는 탐색 노출을 잠깐 늘린다 → 업데이트를 모아 한 번에 크게, 이벤트와 같이.
- 경품·무료 Robux 문구, 내용과 다른 메타데이터는 순위가 깎인다 (STORE_LISTING 규칙과 같음).
- 체험 이벤트(썸네일 최대 5장, 알림 신청), 체험 알림(Open Cloud + 게임 안 동의 창), 그룹, 의미 검색(설명 문장이 검색에 쓰임).
- 광고(Ads Manager): 플레이당 비용 경매, 1 Ad Credit = 285 R$. Roblox는 플레이당 $0.01 미만이라 하나 외부 후기는 $0.20~1.00 [ads]. **리텐션이 받쳐 줄 때만** 소액 시험.
- 등급 없는 체험은 노출이 제한될 수 있다 → 성숙도 설문 필수 [content-maturity].

## 3. 우선순위 할 일

### 내가 한 것 (2026-10-21)
- [x] 스토어 설명 갱신: 보스 레이드·펫·훔치기·출석 선물·리버스 (docs/STORE_LISTING.md, 1000자 안)
- [x] 이 문서: 조사 결과와 할 일 정리
- [x] 게임 안 함께 놀기 장치 점검: HUD 초대 버튼(+20%~+50% 함께 보너스)과 레이드(여럿이 같이 잡음)가 이미 있다. 추가 버튼은 넣지 않음
- [x] 앞선 개선(v51~v54)이 2번 신호를 겨냥: 늦은 렉 줄임(이탈), 리버스 조건(상한 큐브 1~2개쯤에 리버스), 큰 투하

### 사용자가 할 것 (Creator Hub, 계정 권한 필요)
| 순서 | 할 일 | 이유 |
|---|---|---|
| 1 | **Places → 설정 → 서버 크기 8** (또는 API 키에 `universe.place:write` 추가하면 내가 바꿈) | 9번째 사람 튕김. 첫 플레이 이탈에 바로 잡힌다 |
| 2 | 썸네일 5장 업로드 (`game/assets/store/thumb_i_*.png`), 개인화 켜고 7일 이상 유지 | 플레이 전환율 |
| 3 | 스토어 설명 붙여 넣기 (docs/STORE_LISTING.md) + 장르 지정 (Simulation/Tycoon 계열) | 의미 검색·분류 |
| 4 | 성숙도 설문 결과·연령 등급 표시 확인 | 등급 없으면 노출 제한 |
| 5 | Roblox 그룹 만들기 | 그 뒤 게임 안 "그룹 가입 보너스"를 넣을 수 있다(내가 구현) |
| 6 | 체험 알림 문구 등록 + 키에 알림 권한 | 다시 온 날(D1~D28) — 방치 수입 가득·레이드 시작 알림. 문구 등록되면 내가 동의 창·발송 구현 |
| 7 | 다음 큰 업데이트 때 체험 이벤트 페이지 | 업데이트 노출 + 알림 신청 |
| 8 | Creator Analytics에서 D1·D7, 60초 이탈 확인 → 숫자 알려 주면 다음 개선 고름 | |
| 9 | (리텐션 확인 뒤) Ads Manager 소액 시험 | 플레이당 비용 확인 |

**2026-10-26 Chrome으로 처리 (이 PC Chrome, 사용자 상시 위임)**
- [x] 1 서버 크기 50 → **8** (플레이스 → 액세스 → 최대 방문자 수, 새로고침해 확인)
- [x] 2 썸네일 5장 활성 + 개인화 켜짐 (이미 되어 있었음. 10/19~26 노출 0이라 성과는 아직 없음)
- [x] 3 영어 원문 설명을 STORE_LISTING 최신본으로 (develop API `PATCH /v2/places/{id}`, 985자). 장르는 이미 **퍼즐 / 매치 머지 퍼즐**, 11/13까지 변경 잠김
  - 함정: 대시보드가 한국어면 "게임 세부 정보"에 **한국어 기계 번역**이 보인다(이름 "큐브 공장 병합"). 거기서 저장하면 원문이 덮일 수 있어 API로 원문만 바꿈
  - 16개 언어 번역 이름을 모두 **"Merge Cube Factory"**로 고정 (로컬라이제이션 → 번역 → 정보 → 이름). 자동 번역이 "큐브 공장 병합", "Würfel-Fabrik zusammenführen"처럼 명령문으로 바꿔 TikTok 캡션의 검색어와 달랐다
  - 번역 설명은 아직 옛 설명 기준. 자동 번역이 새 원문으로 다시 돌지 며칠 뒤 확인
- [x] 4 콘텐츠 수위 라벨 **최소**, 설명자·나이 제한 없음, 설문 완료
- [ ] 5 그룹(커뮤니티) 만들기: **100 Robux 필요, 잔액 0** → 사용자 결정 대기
- [x] 레이드·펫 썸네일 2장 (`thumb_6_raid.png`, `thumb_7_pets.png`, make_store_art.py `cap_raid`·`cap_pets`)
  - 체험 상세 페이지: 7장 모두 승인·표시
  - 홈 페이지: **한 번에 5장까지만 활성**. 노출이 모두 0이라 "CLIMB THE RANKS"와 어두운 리버스 장면을 끄고 배트·수집·합치기·펫·레이드 5장으로 새 테스트 시작 (10/26). 7일 이상 그대로 둔다
  - 캡처 방법: 레이드는 `Remotes.RaidJoin:InvokeServer(true)`로 참가해야 전장으로 옮겨진다(디버그 start만으로는 안 감). 카메라는 `BindToRenderStep`(Last+10)으로 게임 카메라를 덮어씀. 팝업(7-DAY LOGIN, STARTER PACK)을 먼저 숨긴다
  - 업로드 방법: 숨은 `file-uploader-input`에 file_upload. 먼저 `HTMLInputElement.prototype.click`을 file input에 한해 no-op으로 바꾸고 "섬네일 업로드" 버튼을 JS 클릭

### 다음에 내가 할 수 있는 것
- 레이드·펫 쇼츠 (`shorts/raid.mp4` 10.7s, `shorts/pets_hatch.mp4` 10.4s) 하루 1편 수신함으로. 캡션은 marketing/shorts_schedule.md.
- 그룹이 생기면 그룹 보너스, 알림 권한이 생기면 체험 알림.

## 출처
- [discovery] https://create.roblox.com/docs/discovery
- [discovery-faq] https://create.roblox.com/docs/discovery-faq
- [content-maturity] https://create.roblox.com/docs/production/promotion/content-maturity
- [ads] https://devforum.roblox.com/t/sponsored-experiences-moving-to-ads-manager/2661756
- 썸네일 개인화 기사: https://www.techbloat.com/roblox-will-let-game-devs-personalize-thumbnails-to-attract-more-players.html
- TikTok 홍보 사례: https://www.bloxclips.com/articles/how-to-promote-a-roblox-game-on-tiktok
