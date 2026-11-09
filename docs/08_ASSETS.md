# 08. 에셋 소싱

## 1. 우선순위
1. **직접 생성** — 큐브 캐릭터·UI 아이콘·변이 텍스처(Python/Pillow, Cubika `make_showcase_art.py` 방식), Studio MCP 생성(`generate_mesh`, `generate_material`, `generate_procedural_model`). 소유권 문제 없음, 독창성 확보.
2. **Roblox 라이선스 파트너 음원** — APMOfficial, ProSoundEffects, DistrokidOfficial 등 Creator Store 공식 계정 오디오. 권한 설정 불필요(Cubika에서 확인).
3. **CC0 외부 에셋** — Kenney, Quaternius, Poly Haven [S30]. 각 팩 페이지에서 라이선스 재확인 후 FBX/GLB → Studio 가져오기 → Open Cloud 업로드(우리 소유).
   - **Polyfork** [S32] — 무료 로우폴리 3천여 개, 테마 키트가 팔레트·스케일 공유. **로우폴리로 톤 맞출 게임은 1순위 소스.** 사용법·검증 항목 → [39_POLYFORK.md](39_POLYFORK.md).
4. **Creator Store 무료 모델** — 스크립트 없는 메시만, 아래 보안 규칙 통과 시.

## 2. 1차 검색 결과 (2026-10-17, Creator Store 공개 API, 인증 크리에이터만)

검색 스크립트: `tools/asset_search.mjs`. 원자료: `research/assets-2026-10-17.md`. **삽입 전 Studio에서 미리보기·스크립트 0개 재확인.**

### 음악 (BGM 후보, APMOfficial)
| id | 제목 | 길이 | 용도 |
|---|---|---|---|
| 1839406050 | Happy Game | 68s | 메인 공장 BGM 1순위 |
| 1843404009 | Happy Song | 168s | 대체 |
| 1837324424 | Stepping Up | 213s | 리버스 직후/이벤트 |
| 9046863253 | Poolside | 165s | 차분한 바이옴 |
| 9046863579 | City Lights | 120s | 밤 테마 |
| 1837351012 | Cheat Code (RETRO GAMING) | 116s | Cubika 메뉴 BGM — 시리즈 연결감 |

### 효과음
| id | 제목 | 출처 | 용도 |
|---|---|---|---|
| 9113728049 / 9113728042 | Cash Register 2 / 1 | ProSoundEffects | 판매·수금 |
| 9125805579 | Rising Whoosh Build Up | ProSoundEffects | 리버스, 부화 직전 |
| 9119717523 | Switch Click Toggle Button 2 | ProSoundEffects | UI 토글 |
| 9125446564 | Command Room Tone Hum | ProSoundEffects | 공장 앰비언스(낮은 볼륨) |
| 6787582810 | Coin Pickup Sound Effect | Reditect | 코인 획득(라이선스·품질 확인 필요) |
| — | Cubika Drop/Merged/Land/Move/UI | 자체(Cubika 업로드, Nurimalol 소유) | 합치기 핵심 SFX — **같은 계정으로 게시 시 그대로 사용** |

### 파티클 텍스처 (Decal → image id 변환 필요)
| decal id | 이름 | 작가 |
|---|---|---|
| 13448020314 | Pixel sparkle [Flipbook] | kirbyzaz |
| 12001282356 | Pixel sparkle (Yellow) | kirbyzaz |
| 11817698244 | Pixel shockwave | kirbyzaz |
| 8733226138 | Pixel smoke | kirbyzaz |
(Cubika `docs/ASSETS.md`에 image id로 변환된 6종 목록 있음 — 그대로 재사용)

### 3D 모델 후보 (스크립트 0, 무료)
| id | 이름 | 작가 | 삼각형 | 메모 |
|---|---|---|---|---|
| 518882500 | Tycoon Conveyor | VSTZD | 48 | 매우 가벼움, 컨베이어 장식 |
| 15061208969 | Conveyor Belt Pack | TheMiximum | 27,480 | 무거움 — 일부만 |
| 12549617200 | Low Poly Tree | Remadex Development | 661 | 초원 바이옴 |
| 130260542676735 / 16098456067 | Low Poly Rock | KoBoIce / Jajkopko_XD | 122 / 80 | 바위 |
| 334336000 | Sci-Fi Crate | Torush1 | 384 | 우주 바이옴 |
| 260319753 | Treasure Chest | Zomebody | 1,034 | **Roblox 추천(Endorsed)**, 보상 상자 |
| 5057773836 | Pedestal | DriBowser | 84 | 부화대/진열대 받침 |
| 244551935 | Floating Island | ChronoReaver | 1,104 | 플롯 섬 베이스 참고 |

### 유료 팩 (예산 생기면 검토, 스크립트 0)
| id | 이름 | 메모 |
|---|---|---|
| 83394538772634 | Low Poly Fantasy Magic Crystal x60 (Lukami_th) | 변이 큐브 장식 |
| 130824523247131 | Low Poly Industrial Pack Vol.2 Factory Machine x60 (Lukami_th) | 공장 기계 일괄 |

### 직접 만들 것 (검색으로 대체 불가)
- 큐브 캐릭터 12등급 × 변이 6종 외형 → 프로시저럴(파트 + 표정 데칼) 또는 `generate_mesh` 후 수작업 선별.
- UI 아이콘 전부, 게임 아이콘, 썸네일 3장 (실제 플레이 화면 기반 — 02 §2).

## 3. 라이선스 기록 규칙
- `research/assets-*.md`와 이 문서의 표에 **id, 이름, 작가, 출처 URL, 라이선스, 확인일**을 남긴다.
- 외부 CC0 에셋은 다운로드 원본 zip을 저장소 밖 `Dev/AssetPack/`에 두고 경로만 기록.
- 유료 에셋 구매는 사람 승인(07 §3).

## 4. 보안 규칙 (필수)
- 공식 문서: Creator Store 에셋은 백도어 스크립트 위험, 샌드박스·Capabilities 제한·스크립트 검토 권장 [S23].
- Cubika 실제 사례: "Hit VFX" 무료 모델 4종(70826051241308, 122503587298265, 85112359513087, 70724491525166)에 같은 숨은 스크립트 → 코드 붙여넣기 유도 오버레이.
- 규칙
  1. `hasScripts = true`인 모델은 삽입 금지. 필요한 경우 메시/텍스처 id만 추출.
  2. 삽입 후 `search_game_tree`로 Script/LocalScript/ModuleScript 0개 확인, `require(숫자)` 문자열 grep.
  3. 인증 크리에이터 배지도 보증 아님 → 같은 검사 적용.
