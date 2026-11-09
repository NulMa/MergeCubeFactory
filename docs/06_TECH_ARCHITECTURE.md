# 06. 기술 아키텍처

## 1. 원칙
1. **서버 권한 경제**: 현금·젬·인벤토리·합치기 판정은 서버에서만. 클라이언트는 입력과 연출.
   (Cubika는 클라이언트 시뮬 + 사후 검증이었다 — 싱글 퍼즐이라 가능했던 방식. 멀티 경제에서는 쓰지 않는다.)
2. **파일 시스템이 원본**: Rojo로 전체 프로젝트(코드 + 데이터 + UI 빌더)를 저장소에 둔다.
   Studio 내장 Script Sync는 코드만 동기화하므로 보조용 [S26].
3. **순수 로직은 Roblox API 없이**: `shared/`의 경제 공식·카탈로그·검증은 Lune으로 테스트(Cubika 방식).
4. **데이터 주도**: 큐브 등급·변이·드로퍼·상품·퀘스트는 전부 `shared/Catalog/*.luau` 데이터. 에이전트는 데이터 추가로 콘텐츠를 늘린다.

## 2. 툴체인 (Cubika `rokit.toml` 계승, 2026-10-16 고정 버전)

| 도구 | 버전 | 용도 |
|---|---|---|
| rojo | 7.7.0 | 빌드·동기화 |
| lune | 0.10.5 | 순수 로직 테스트, 빌드 스크립트 |
| selene | 0.31.0 | 린트 |
| stylua | 2.5.2 | 포맷 |
| luau-lsp | 1.69.0 | 타입 검사 |
| asphalt | 2.0.2 | 에셋 업로드 → id 코드 생성 |
| (추가 후보) wally | 최신 안정판 - 2주 | 패키지 (ProfileStore 등) — Phase 1에서 버전 확정 |

검사 스크립트: Cubika `scripts/check.ps1` 그대로 이식 — sourcemap → luau-lsp → selene → stylua → lune 테스트 → rojo build.

## 3. 프로젝트 구조

### 3.0 실제 구조 (2026-10-17, Phase 1)
시제품을 여러 개 만들 수 있게 **공용 코어 + 게임별 폴더**로 나눴다. 아래 3.1은 MVP 목표 구조이며, 서비스가 커지면 `src/merge/server/`를 그 형태로 쪼갠다.

```
game/
  merge.project.json        게임(플레이스)마다 <name>.project.json 하나. 반드시 game/ 루트에 둔다:
                            하위 폴더에 두면 sourcemap 상대경로가 어긋나고, --absolute는 \\?\ 경로라 luau-lsp가 못 읽는다
  src/core/shared/          ReplicatedStorage.Core   Signal, Format, Net(인자 검증 + 초당 20회 제한)
  src/core/server/          ServerScriptService.CoreServer   Data(ProfileStore), Ledger(재화 단일 진입점), Receipts(멱등)
  src/merge/shared/         ReplicatedStorage.Game   Economy(순수 공식), Config, Remotes
  src/merge/server/         ServerScriptService.GameServer   Plots, Factory, init.server
  src/merge/client/         StarterPlayerScripts.GameClient
  vendor/ProfileStore/      고정 커밋 + LICENSE (lint/format 제외)
  tests/*.spec.luau         Lune
  scripts/check.ps1         *.project.json마다 sourcemap → luau-lsp → build, 이어서 selene·stylua·lune
```

### 3.1 MVP 목표 구조

```
game/
  default.project.json
  rokit.toml  selene.toml  stylua.toml  .luaurc  wally.toml
  src/
    shared/                     ReplicatedStorage.Shared
      Config.luau               모든 튜닝 상수 (05의 수치)
      Catalog/                  Cubes, Mutations, Droppers, Products, Quests, Biomes (순수 데이터)
      Economy.luau              수입·비용·오프라인·리버스 공식 (순수)
      MergeRules.luau           합치기 판정 규칙 (Cubika CubeLogic 계승, 순수)
      Daily.luau                날짜 시드 퀘스트 (Cubika 재사용)
      Net.luau                  Remote 이름·인자 계약 (한 곳에서 정의)
    server/                     ServerScriptService.Server
      init.server.luau          서비스 부트스트랩
      Services/
        DataService.luau        세션 잠금 저장 (ProfileStore), 스키마 버전·마이그레이션
        PlotService.luau        플롯 배정, 트레이 물리, 드로퍼 틱
        MergeService.luau       접촉 감지 → MergeRules → 결과 적용
        EconomyService.luau     잔액 변경 단일 진입점 (모든 증감은 여기 경유 + 로그)
        HatchService.luau       부화 타이머 (os.time 기반, 오프라인 진행)
        ShopService.luau        업그레이드·젬 상점
        MonetizationService.luau ProcessReceipt(멱등), 패스 확인, PolicyService 게이트
        QuestService.luau       일일·주간 퀘스트
        TeamService.luau        협동 방문, 팀워크 보너스
        AnalyticsService.luau   경제/퍼널/진행 이벤트 (09)
    client/                     StarterPlayerScripts.Client
      init.client.luau
      Controllers/              Input, Camera, Fx(Cubika Fx 이식), Audio, Tutorial
      UI/                       화면별 모듈 + Theme
  tests/                        *.spec.luau (Lune)
  assets/                       업로드 원본 (asphalt 입력)
```

## 4. 데이터 스키마 (DataService, 버전 필드 필수)

```lua
Profile = {
  v = 1,                      -- 스키마 버전, 마이그레이션 함수 테이블로 승격
  cash = 0, gems = 0,
  rebirths = 0, biome = 1,
  droppers = { {tier=1, speedLv=0}, ... },
  tray = { {tier=3, mut=nil}, ... },      -- 접속 종료 시 스냅샷(위치는 저장 안 함)
  incubators = { {core="rare", startedAt=os.time()} },
  codex = { ["5:gold"] = true },
  quests = { day=..., progress={...}, done={...} },
  pass = { xp=0, claimedFree=0, claimedPaid=0 },
  receipts = { [purchaseId]=true },      -- 최근 N개, ProcessReceipt 멱등
  lastSeen = os.time(),
}
```
- 저장: ProfileStore 세션 잠금(동시 서버 덮어쓰기 방지). 라이선스·최신 버전은 Phase 1 시작 시 확인.
- 구매 처리: `receipts`에 먼저 기록 후 보상 지급, 저장 성공 시에만 `PurchaseGranted` 반환.

## 5. 성능 예산
| 항목 | 상한 | 대응 |
|---|---|---|
| 플롯당 물리 큐브 | 40 (튜닝) | 초과 시 최저 등급 자동 판매 |
| 서버당 플롯 | 8 | 총 물리 파트 ~320 |
| 정지 큐브 | 1초 이상 정지하면 수면 상태 유지(Roblox 물리 슬립) | 별도 앵커링은 측정 후 결정 |
| Remote 빈도 | 클라 → 서버 입력 10회/초 상한 | 서버 레이트 리밋 |
| UI | ImageLabel 기반, Frame 픽셀 렌더링 금지 | Cubika 교훈(11) |
- Phase 1 첫 작업: 8플롯 × 40큐브 서버 물리 스트레스 테스트(Studio MCP 플레이테스트 + 마이크로프로파일러). 실패 시 대안 = 서버는 격자 기반 판정, 물리는 클라이언트 연출.

## 6. 보안
- 모든 Remote 인자 타입·범위 검사(`Net.luau`에 스키마). 클라이언트가 보내는 것은 "의도"(예: `DropAt(slot, x)`)만.
- 서드파티 모델 스크립트 금지(08 §4).
- `HttpService` 꺼둠(외부 API 필요 시 Open Cloud는 게임 밖에서).
- 관리자 명령은 서버 화이트리스트 + Studio 전용.

## 다인 서버 최적화 (2026-10-19, 사용자 요청 "다인 멀티 시 프레임 드랍 미리 대비")
8인 서버 기준 큐브 최대 ~900개(플롯당 60~100 + 넘침 10), 펫 최대 24마리.

| 부하 | 대책 | 위치 |
|---|---|---|
| 모든 병합을 모든 클라이언트에 보냄(이벤트·연출 8배) | 주인 + 170스터드 안 사람에게만 | server/Factory `fireMerged` |
| 남의 병합 연출 | 120스터드 안, 초당 6개까지, 잔상·고리·반짝이 없이 | client/Fx `Fx.merge` |
| 먼 공장 큐브의 빛·입자·등급 숫자·변이 이름표·테두리 | 카메라에서 플롯 중심 150스터드 밖이면 끔(0.5초마다, `LodOff` 속성으로 원래 꺼진 것은 안 켬) | client/CubeLod |
| 변이 큐브 깜빡임·색 돌리기(매 프레임) | 카메라 150스터드 밖 건너뜀 | client/Fx |
| 펫 따라다니기(매 프레임 BulkMoveTo) | 남의 펫 70스터드 밖은 3프레임에 한 번, 160 밖은 숨김 | client/PetFollow |

- 서버 병합 검사는 플롯당 0.1초마다 등급별 묶음 안에서만 짝을 찾아(큐브 ~110개) 가볍다. 멈춘 큐브는 물리 슬립.
- 실제 8인 부하는 아직 재지 않았다. 공개 후 Developer Console(F9)의 클라이언트 FPS·네트워크 수신량, 서버 Heartbeat를 확인할 것.

## 고등급 렉 (2026-10-21, 사용자 "최고 티어 25쯤 오니 렉")
원인: 큐브 크기가 아니라 **초당 큐브 수**. 후반(드로퍼 8개, 간격 0.4초 하한 + 2배 투하 최대 75%)엔 큐브 생성 초당 ~24, 합치기 ~22.
Studio 재현(StudioDebug `rebirths 12`, `droppers "21:30"`, 1인, 고사양 PC):

| | 초반 | 후반 (전) | 후반 (후) |
|---|---|---|---|
| 클라이언트 인스턴스 생성/초 | ~20 | ~350 (소리 70·연출 파트 64·큐브 꾸밈 ~120) | ~133 (큐브 꾸밈만) |
| 서버 인스턴스 생성/초 | — | ~120 | 33 |
| 서버 전송 (1인) | 37kbps | 57kbps | 47kbps |
| 서버 물리 | 0.5ms | 3.4ms | 2.6ms |
| 최악 프레임 | 20ms | 25~32ms | 23ms |

| 대책 | 위치 |
|---|---|
| 효과음: Sound+Attachment를 매번 만들고 지우던 것을 목소리 칸 24개 풀로 (모자라면 가장 오래된 소리를 끊음) | client/Fx `Fx.sound` |
| 합치기 섬광 큐브·충격파 고리: 풀에서 꺼내 쓰고 숨겨 돌려놓음 | client/Fx `ghost`·`ringWave` |
| 내 합치기가 초당 8개를 넘으면 나머지는 가볍게(섬광·고리·반짝이 없음, 조각 입자 반, 소리 간격). 새 최고·콤보 마일스톤은 그대로 | client/Fx `Fx.merge` |
| 큐브 얼굴 Decal 2·등급 숫자 SurfaceGui를 서버가 만들어 복제하던 것을 클라이언트가 `Tier`·`AtMax` 속성을 보고 붙임 | client/CubeLook, server/Factory `spawnCube`·`markCeiling` |

- 2026-10-22: 큐브를 서버 데이터 + 자체 간이 물리(TraySim)로 바꿈 → 서버 물리 2.55ms → 0.09ms (docs/27 단계 5).
- (이전) 남은 것: 큐브 수 자체(물리·위치 복제). 8인 모두 후반이면 서버 물리 ~20ms로 60Hz를 넘길 수 있다. → 2배 투하를 "한 등급 위 큐브 1개"로 바꿈 (사용자 승인, docs/13 §9.9): 큐브 생성·합치기 최대 ~40% 감소.

## 메뉴 열 때 방치 수입 안내 (2026-10-19)
`GuiService.MenuOpened` → 시스템 알림(SendNotification) "Your factory keeps working!" + 지금 수입 기준 최대 방치 수입(10% × 4시간). 3분에 한 번. Roblox 메뉴는 게임 UI보다 위라 시스템 알림을 쓴다 (client/LeaveNote).
