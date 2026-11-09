# 11. Cubika에서 가져올 것 / 다시 하지 않을 것

원본: `C:\Users\NullMa\UnityProjects\Cubika\Roblox` (docs/SPEC, UPLOAD, ASSETS, PROGRESSION, SHOWCASE). 2026-10-17 경험 10771411112로 게시.

## 재사용 (복사 후 이름만 바꿈)
| 대상 | Cubika 위치 | 여기서의 용도 |
|---|---|---|
| 툴체인 고정·검사 스크립트 | `rokit.toml`, `selene.toml`, `stylua.toml`, `.luaurc`, `scripts/check.ps1` | 06 §2 그대로 |
| 합치기 판정·콤보 | `src/shared/CubeLogic.luau` | `MergeRules.luau` 기반 |
| 합치기 연출 | `src/client/Game/Fx.luau` | 3D 공장 스케일로 조정 |
| 날짜 시드 일일 퀘스트 | `src/shared/Daily.luau` | 그대로 |
| 배틀패스(경험치·무료/패스 트랙·상점) | `src/shared/Cosmetics.luau`, `docs/PROGRESSION.md` | 시즌 패스 |
| 에셋 파이프라인 | `asphalt.toml`, `tools/scripts/asphalt_to_ids.py`, `AssetIdsManual.luau` 우선순위 | 그대로 |
| Open Cloud 게시 스크립트 | `tools/scripts/publish_place.py` | 07 단계 8·9 |
| UI 클릭 SFX 합성 | `tools/scripts/make_ui_sfx.py` | 그대로 |
| 큐브 픽셀 아트·SFX | `assets/` (Nurimalol 소유 업로드) | 시리즈 연결, **같은 계정으로 게시** |

## 다시 하지 않을 것
| Cubika에서 | 문제 | 이번 결정 |
|---|---|---|
| PC 전용, 키보드 조작 | 모바일·콘솔 유입 0 | 모바일 우선 UI, 전 기기 |
| 캐릭터 없음 | 아바타 경제·R15 DevEx 가산 대상 아님 | R15 캐릭터 사용 |
| 싱글 플레이 | co-play 신호 없음 | 협동 플롯 |
| 클라이언트 시뮬 + 사후 검증 | 멀티 경제에서는 부적합 | 서버 권한 경제 |
| 수익화를 마지막에 붙임 (Showcase Pass) | 상품이 게임 루프와 약하게 연결 | 03을 GDD와 동시에 설계 |
| Frame 픽셀 폴백 렌더링 | 화면 Frame 수천 개 | 처음부터 업로드 이미지 |
| 테스트 전체 해금 플래그 | 켜진 채 게시하면 패스가 안 팔림 | 출시 체크리스트 항목화 (10) |

## 알려진 함정
- Studio MCP `upload_image`는 이미지 전용 → 오디오는 Open Cloud/Asset Manager.
- Creator Hub PNG 업로드는 Decal id → `ImageLabel`에는 Image id 필요.
- 커스텀 폰트 업로드 불가 → 내장 폰트.
- 무료 VFX 모델 백도어(08 §4).
- DataStore는 게시 후에만 동작, Studio 테스트는 "Studio API 접근 허용" 필요.
