# 31. 번역(로컬라이제이션)과 홍보 채널 자동화 (2026-10-25 조사)

> 사용자 (2026-10-25): "지금 게임에 로컬라이제이션이 있는지 모르겠네. 로블록스 커뮤니티 페이지나 기타 홍보수단도 있으면(자동화) 좋을 것 같고".
> 공식 문서 기준 (출처 아래). Open Cloud 일부는 베타라 바뀔 수 있다 — 쓰기 전에 참조 페이지를 다시 확인.

## 1. 번역: 지금 상태
- 코드에 번역 처리가 **없다** (`LocalizationService`·`LocalizationTable`·`GetTranslator` 0건). 화면 글자는 전부 영어 원문.
- 화면 글자 종류 (client): 고정 문자열 `Text = "..."` 약 178곳, 숫자·이름이 들어간 문자열 `Text = \`...{x}...\`` 약 91곳, 배너 13곳, 서버 알림(Toast) 8곳 + 상점·패스 이름.
- GuiObject의 `AutoLocalize`는 기본 true라, 아래 자동 번역을 켜면 **고정 문자열은 코드 수정 없이** 번역된다.

## 2. 번역 방법 (Roblox 공식)
| 방법 | 무엇 | 비용·제한 | 우리에게 |
|---|---|---|---|
| 자동 번역 (Automatic Text Capture + Automatic Translation) | 플레이 중 화면에 나온 글자를 모아 현지화 표에 넣고 기계 번역. Creator Hub → 게임 → Localization → Settings에서 "Capture text from experience UI while users play" + "Use Translated Content" | 처음 할당량 + 월 할당량(글자 수 × 언어 수). 18개 언어 (한국어 포함). 안 쓰는 문자열은 기본으로 자동 정리 | **1단계: 사용자가 켜기만 하면 됨** (계정 권한 필요, 웹) |
| 번역 키 + 매개변수 (`Translator:FormatByKey`) | "DROPPER {1} SPEED Lv{2}" 같은 문장을 키 하나로, 숫자는 매개변수 | 코드 수정 | 2단계: 숫자가 들어간 91곳. 자동 캡처는 값마다 다른 문자열로 모아서 할당량을 낭비하고 번역이 늦다 |
| 실시간 번역 API (`TranslateText`, Open Cloud, 개발 초기) | 서버 스크립트에서 동적 글자 번역 | 게임 분당 600 + 1.5 × 동접 요청, RCC 인증만(Studio에선 팀 테스트) | 채팅·이름처럼 미리 모를 글자에만. 지금은 필요 없음 |
| 스토어 이름·설명 번역 | Creator Hub Localization → 게임 정보 번역 | 웹 | 사용자가 STORE_LISTING 영어 설명을 기계 번역해 넣기 (주요: 스페인어·포르투갈어·인도네시아어·한국어) |

- 잡히지 않는 것: 기본 리더보드·채팅, 플레이어 소유 아이템 이름, **글자가 박힌 이미지**(아이콘에 글자 넣지 말 것), 플랫폼에서 가져오는 배지·패스 이름/설명.
- 숫자만 있는 라벨(현금 `$1.06Qa` 등)은 `AutoLocalize = false`로 캡처 낭비를 막는다.

### 추천 순서
1. (사용자, 5분) 자동 번역 두 개 켜기 + 스토어 설명 번역.
2. (에이전트) 숫자·이름이 들어간 문자열을 `Loc.format(key, ...)` 한 모듈로 모으고 `LocalizationTable`(CSV 생성 스크립트)로 키 등록 — 영어 원문은 키 표에서 그대로, 다른 언어는 자동 번역이 채움. 숫자 전용 라벨 AutoLocalize 끄기.
3. 플레이어 언어별 지표(Creator Analytics) 보고 상위 언어만 사람이 다듬기.
- 다음 게임은 처음부터 2번 방식으로 문자열을 쓴다 (docs/30 §1.1 번역·홍보 묶음).

### 2번 구현 (2026-10-25)
| 무엇 | 어디 |
|---|---|
| 키 표: 숫자·이름이 바뀌는 문장 128개 (`{이름}` 매개변수) + 매개변수로 넣는 고정 이름 16개(SOURCES) | `shared/Strings.luau` |
| 클라 번역: `Loc.set(라벨, 키, 매개변수)` (AutoLocalize 끔 → FormatByKey, 표에 없으면 영어 원문), `Loc.raw`(숫자뿐), `Loc.plain`(고정 문장, ATC), `Loc.apply`(글자 또는 Msg), `Loc.source`(원문 기준 번역) | `client/Loc.luau` |
| `Ui.make` 속성 `Loc = Loc.msg(키, 매개변수)` | `client/Ui.luau` |
| 서버 알림·보상 글자는 `Strings.msg(키, 매개변수)` 표로 보냄 (Toast·Announce·Fx record/codex/gift·Daily 보상 반환) | server/Factory·Steal·Daily·Boxes·Events |
| 토스트·배너·팝업은 글자/Msg 둘 다 받음. 영어 원문에 숫자가 있으면 캡처 안 함 (`Loc.capturable`) | client/init·Fx |
| 숫자뿐 라벨(현금·지갑·등급 숫자·랭킹 이름/값·큐브 면 숫자) AutoLocalize 끔 | 여러 곳 |
| 검사: 코드의 키가 표에 있음 / 표의 키가 쓰임 / 원문 중복 없음 | `tests/Strings.spec.luau` |
| 클라우드 표용 CSV: `lune run tools/loc_csv.luau` → `build/loc_keys.csv` (Key,Context,Example,Source) | `tools/loc_csv.luau` |

- Studio 확인: FormatByKey는 **숫자 매개변수에 소수점을 붙인다** (3 → "3.00") → Loc이 매개변수를 모두 글자로 바꿔 넘긴다. 표에 없는 키는 오류 → 영어 원문으로.
- 2차 (같은 날, 사용자 "남은 영어 부분도 번역 키로"): 강화 효과 줄·목표 바 힌트·콤보/새 등급/행운 팝업·골든 큐브 보상·오프라인 안내 알림·도둑 고르기 줄도 키로 (키 170개).
- 이름 매개변수: `Strings.NAME_ARGS`(variant·pet·rarity·egg·boss·core·title·label·what·desc)는 Loc이 원문 기준(`Translator:Translate`)으로 번역해 넣는다. 플레이어 이름은 `{name}`이라 번역 안 함.
  CSV에는 키 줄 + 이름 줄(변이·등급·코어·펫·희귀도·알·보스·보스 설명·강화 이름, 대문자판 포함) 183개가 들어간다.
- Studio: `GetTranslatorForPlayerAsync`는 게시 안 된 파일에서 실패 → `GetTranslatorForPlayer`(게임 안 LocalizationTable만)로 대체. 임시 한국어 표로 확인: "훔치기 x1", "트레이 4/50", "메탈릭 0/40", "광택 Lv0/20", "수입 x1.00 → 수입 x1.10".
- 영어로 두는 것: 숫자·기호뿐인 라벨, 플레이어 이름, Format.duration 단위("1m 47s"), 고정 문장은 자동 캡처 몫.
- API 업로드: `node tools/loc_upload.mjs`(미리 보기) → `--write`(새 줄만 추가, 지우지 않음). 2026-10-25 시도: 지금 키는 `legacy-universe:manage` 권한이 없어 403 "Scope not authorized" → 사용자가 키에 권한 추가 후 다시.
- **완료 (2026-10-26, Chrome으로 Creator Hub)**: 테이블 관리 → CSV 업로드로 353줄 전부 추가 (수정·삭제 0). 설정: 자동 텍스트 캡처 켜기, 번역 콘텐츠 사용 켜기, '오래된 항목 제거'는 끔 (ATC가 못 보는 키 줄이 지워질 수 있어서). 언어: 소스 언어가 한국어로 잘못 돼 있어 영어로 바꿈. 지원 언어 16개(독·러·베·스·아랍·이·인니·일·중간·중번·태·터키·포·폴·프·한) 추가, 각각 자동 번역(체험 문자열 및 상품, 체험 정보) 켜기.
  - CSV 업로드는 한 번에 약 50줄만 들어가고 'upstream request timeout'이 뜬다. 오류가 나도 50줄은 들어가 있으니 새로 고침 후 같은 파일을 다시 올리면 남은 줄만 추가된다 (확인 창의 '추가된 항목' 수로 진행 확인, 0이면 끝).

## 3. 홍보 채널: 자동화 가능 여부
| 채널 | 자동화 | 방법·조건 | 판단 |
|---|---|---|---|
| **TikTok** | 반자동 (지금) | API 수신함 업로드 → 앱에서 게시 (미심사 앱은 직접 게시 불가) | 계속, docs/28 §4 |
| **게임 알림 (Experience Notifications)** | **자동 가능** | 게임 안에서 알림 수신 동의(`ExperienceNotificationService:PromptOptIn`) → Open Cloud `POST /cloud/v2/users/{id}/notifications` (또는 엔진 API). 알림 문구는 Creator Dashboard에서 미리 만들어야 함(API 없음). 13세 이상·동의한 사람만, **게임 방문 100회 이상**, 광고성 일괄 문구 말고 개인에게 맞춘 행동 유도 | **재방문에 가장 직접적.** 예: "내 공장이 털렸다 / 코어 부화 완료 / 보호 끝남". 방문 100회 넘으면 바로 |
| **커뮤니티(그룹) 공지 (Shout)** | 자동 가능 | Open Cloud `PATCH /legacy-groups/v1/groups/{groupId}/status`, scope `legacy-group:manage`, 255자 | 커뮤니티가 있어야 함(만들기는 사용자, Robux 비용 확인). 업데이트마다 공지 1줄 자동 |
| 커뮤니티 포럼 글 | 읽기만 | Open Cloud는 포럼 카테고리·글·댓글 **조회만**(베타) | 쓰기 자동화 불가 → 사람이 |
| 이벤트 (Events & Updates) | 수동 | Creator Hub에서 만들기, 동시 10개, 플레이어가 "Notify Me"하면 시작 때 알림. 업데이트 알림도 같은 메뉴 | 격주 주말 이벤트를 여기 올림 (사용자). 게임은 join context로 이벤트 입장을 알 수 있음 |
| 게임 안 친구 초대 | 있음 | `SocialService:PromptGameInvite` (+20% 함께 보너스) | 유지 |
| YouTube Shorts | 자동 가능하나 제약 | YouTube Data API `videos.insert`(OAuth). **심사 안 받은 API 프로젝트로 올린 영상은 비공개로 묶인다** → 심사 신청하거나 앱/웹에서 게시 | TikTok과 같은 원본 재사용, 업로드는 Studio에서 사람이 하거나 심사 후 자동 |
| X(트위터) | 확인 필요 | API 무료/유료 등급과 게시 한도가 자주 바뀜 | 키가 준비되면 등급 확인 후 |
| Roblox 광고(Ads Manager) | 수동·유료 | 자연 유입이 생긴 뒤 소액 (docs/30 §4) | 나중 |

- 공통 규칙: 외부 게시는 사용자 승인 후 (지금 운영 규칙). 자동화는 "초안을 만들고 승인되면 보낸다"까지.
- 커뮤니티를 만들면 게임 소유를 커뮤니티로 옮길지(여러 게임 관리·공동 작업에 유리) 함께 정한다 — 소유 이전은 되돌리기 번거로우니 사용자 결정.

## 4. 할 일
| 누가 | 무엇 |
|---|---|
| 사용자 | ~~자동 번역 켜기~~ (2026-10-26 완료, §2) / 커뮤니티 만들지 결정 / 방문 100회 넘으면 알림 문구 3개 만들기 (Creator Dashboard) / 이벤트 메뉴에 주말 이벤트 등록 |
| 에이전트 | ~~`Loc` 모듈 + 키 표~~ (완료, 키 170개) / 알림 동의 버튼·조건(첫 리버스 뒤) + 서버 트리거(털림·부화·보호 끝) / 커뮤니티 공지 스크립트 `tools/community.mjs` (승인 후 게시) |

## 출처
- Automatic translation: https://create.roblox.com/docs/production/localization/automatic-translations
- Auto-translate dynamic content: https://create.roblox.com/docs/production/localization/auto-translate-dynamic-content
- Experience notifications (Open Cloud): https://create.roblox.com/docs/cloud/guides/experience-notifications , https://create.roblox.com/docs/production/promotion/experience-notifications
- Groups API (shout PATCH, forum read-only): https://create.roblox.com/docs/cloud/reference/features/groups.md , https://create.roblox.com/docs/cloud/reference/GroupShout
- Experience events: https://create.roblox.com/docs/production/promotion/experience-events
- Roblox Communities 발표: https://devforum.roblox.com/t/introducing-roblox-communities/3268307
