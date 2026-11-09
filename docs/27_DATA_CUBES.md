# 27. 데이터 큐브 전환 (ECS·데이터 지향, 2026-10-21)

> 사용자 (2026-10-21): "단계별로 나눠서 ecs전환작업 진행해봐".
> 목표: 서버는 큐브를 **데이터**로만 들고(Roblox 물리 파트 없음) 자체 간이 물리로 위치를 계산, 클라이언트가 로컬 파트를 만들어 보간·연출.
> 근거: docs/06 "고등급 렉" — 남은 비용은 큐브 수 자체(서버 물리 + 파트 위치 복제). 8인 후반이면 서버 물리 ~20ms.

## 0. 왜 가능한가
- 큐브는 **플레이어와 충돌하지 않는다** (`Cubes`↔`Players` 충돌 꺼짐, server/Plots). 캐릭터 물리를 흉내 낼 필요가 없다.
- 큐브에 힘을 주는 것은 서버뿐: 드로퍼 투하, 자석 깡충, 배트(`onSwing`), 트레이 밖 복귀(`enforceTray`). 전부 서버 코드다.
- 트레이는 축 정렬 상자(바닥 + 벽 4개 + 천장 가드). 큐브는 정육면체.

## 1. 구조 (끝 상태)
```
shared/TraySim.luau     순수 간이 물리 (Roblox API 없음, Lune 테스트). SoA 배열, 공간 해시, 위치 기반 동역학(PBD)
shared/CubeCodec.luau   buffer 직렬화: spawn / remove / retier / snapshot(움직이는 큐브만)
shared/CubePredict.luau 데드 레코닝 예측식·보낼 항목 고르기 (서버 CubeNet·클라 CubeView 공용, 2026-10-22)
shared/CubeStyle.luau   큐브 겉모습 (크기·색·변이 장식·속성). 서버 PartBackend·클라 CubeView 공용
server/CubeWorld.luau   플롯별 큐브 저장소 (ECS: 엔티티 id + 컴포넌트 열). 백엔드 교체 가능
                          - PartBackend: 지금처럼 Roblox Part + 물리 (Config.DATA_CUBES = false, 롤백용)
server/SimBackend.luau    - SimBackend : TraySim + CubeCodec으로 복제 (Config.DATA_CUBES = true)
server/CubeNet.luau     관심 영역 복제: 주인 매 틱, 근처(150스터드) 사람 낮은 빈도, 먼 사람 없음
client/CubeView.luau    스냅샷 → 로컬 Part (plot.Cubes 폴더 안, 클라이언트 전용) 보간·공중 회전 연출.
                          Tier·AtMax·Variant 속성을 붙여 CubeLook·CubeLod·CubeInventory·init.client 감시가 그대로 동작
```

### 1.1 엔티티와 컴포넌트 (server/CubeWorld)
| 컴포넌트 | 타입 | 지금 위치 |
|---|---|---|
| id | number (플롯 안에서 증가, 16비트로 돌려 씀) | 없음 (Cube 테이블 자체가 키) |
| tier, variant, born, nudged, revealUntil | number | `Cube` 테이블 |
| body | 백엔드 핸들 (Part 또는 TraySim 슬롯) | `cube.part` |

모든 시스템(합치기 `scanMerges`, 자석 `magnet`, 배트 `onSwing`, 트레이 정리 `enforceTray`, 훔치기 `Steal`)은 `cube.part`를 직접 만지지 않고
CubeWorld API(`position(id)`, `velocity(id)`, `setVelocity(id, v)`, `teleport(id, p)`, `size(id)`, `remove(id)`, `query(center, radius)`)만 쓴다.

### 1.2 TraySim (위치 기반 동역학)
- 상태(SoA): `px,py,pz, vx,vy,vz, half(반 변), sleep(정지 프레임 수)`. 회전 없음(충돌은 AABB). 보이는 회전은 클라이언트 연출.
- 한 스텝(dt = 1/30 고정, 서버는 Heartbeat 누적으로 0~3스텝):
  1. 깨어 있는 것만 중력·속도 적분 (예측 위치)
  2. 제약 반복 4회: 바닥·벽·천장(상자 안쪽), 큐브끼리 AABB 겹침 → 가장 얕은 축으로 반씩 밀기 (공간 해시 셀 = 최대 큐브 변)
  3. 속도 = (새 위치 − 이전 위치)/dt, 바닥·접촉 마찰(수평 감쇠), 반발 약간
  4. 속도 작고 아래 받침이 있으면 sleep += 1, 일정 이상이면 잠(적분·제약 건너뜀). 이웃이 움직이면 깨움
- 성능 목표: 플롯당 큐브 110개, 30Hz, 서버 1틱 < 0.5ms (8플롯 < 4ms). Lune 벤치 테스트로 확인.
- 터널링 방지: 한 스텝 이동 ≤ 최소 반 변 (속도 상한 + 필요 시 부분 스텝).

### 1.3 복제 (CubeCodec + CubeNet)
- 신뢰 이벤트 `CubeEvt`(RemoteEvent, buffer): spawn(id, tier, variant, pos, vel) / remove(id, reason: merge|sell|steal) / retier(id, tier, variant, atMax) / reset(전체 목록, 접속·관심 영역 진입 시).
- 비신뢰 `CubeSnap`(UnreliableRemoteEvent, buffer): 깨어 있는 큐브만 `id u16, pos 3×i16(플롯 중심 기준 1/64스터드), vel 3×i8`. 잠든 큐브는 마지막 위치 그대로.
  (2026-10-22부터 데드 레코닝 보정만 보낸다 → 아래 "최적화 (2026-10-22)")
- 빈도: 주인 15Hz, 근처 5Hz, 150스터드 밖 0 (CubeLod 거리와 같음). 큐브 110개가 모두 깨어 있어도 1패킷 ≈ 1.4KB.
- 클라이언트 CubeView: 스냅샷 2개 사이 보간(100ms 지연), 없으면 속도로 짧게 외삽.

## 2. 단계 (각 단계 끝에 check.ps1 통과, 게임은 계속 동작)
| 단계 | 내용 | 동작 변화 | 담당 모델 |
|---|---|---|---|
| 1 | CubeWorld 도입 + PartBackend. Factory·Steal을 id/API로 옮김 | 없음 (순수 리팩터) | Sonnet |
| 2 | shared/TraySim + tests/TraySim.spec (안정 쌓기, 벽, 터널링, 잠, 벤치) | 없음 (새 파일) | Opus |
| 3 | shared/CubeCodec + tests/CubeCodec.spec | 없음 (새 파일) | Haiku |
| 4 | SimBackend + CubeNet + client/CubeView, 변이 장식 클라이언트로, Steal 고르기를 id로. `Config.DATA_CUBES` 플래그 | 플래그 켜면 전환 | Opus |
| 5 | Studio 확인·측정(06 표와 비교) → 플래그 기본값 결정, 배포 | | 메인 |

**단계 1 완료 (2026-10-21)**: `server/CubeWorld.luau` + PartBackend. Factory·Steal은 큐브 id(number)만 들고 다닌다.
API: `CubeWorld.new(plot, ceilingOf, backend?)`, `spawn(tier, pos, variant?) -> id`, `remove(id)`, `release(id) -> Part?`(떼어 내기, 훔치기),
`ids()`(만든 순서, 읽기 전용), `count()`, `alive(id)`, `has(id)`, `tier/variant/born/nudged/revealUntil(id)` + `retier(id, tier, variant)`(재스타일+MAX 표시)
`setTier/setVariant/setBorn/setNudged/setRevealUntil`, `look(id, variant)`(열은 두고 겉모습만), `position/velocity/size(id)`, `setVelocity/setAngular(id, v)`,
`teleport(id, cframeOrPos)`, `query(center, radius) -> {id}`, 우회로 `partOf(id) -> Part?` (호출 지점에 `-- 단계 4: id로` 표시: Factory.revealVariant, Steal.onList/onSteal).
백엔드 인터페이스 = `CubeWorld.Backend` 타입 (create/destroy/alive/position/velocity/setVelocity/setAngular/teleport/size/restyle/markCeiling/partOf/release).

**단계 2 완료 (2026-10-21)**: `shared/TraySim.luau` + `tests/TraySim.spec.luau` (58개 통과). 좌표는 시뮬 로컬(트레이 중심 x=z=0, 바닥 윗면 y=floorY), 숫자만(Vector3 없음).
API: `TraySim.new({halfX, halfZ, floorY=0, ceilY?, gravity=196.2, friction=0.4, restitution=0.1, iterations=4, cell=6})`,
`add(id, x,y,z, half, vx?,vy?,vz?)`, `remove(id)`(이웃 깨움), `setVelocity(id, vx,vy,vz)`(깨움), `teleport(id, x,y,z)`(속도 0), `wake(id)`,
`step(dt) -> 돈 스텝 수`(1/30 누적, 최대 3, 밀린 시간 버림), `position/velocity(id) -> x,y,z`, `half(id)`, `awake(id)`, `has(id)`, `count()`, `awakeCount()`,
`eachAwake(fn(id, x,y,z, vx,vy,vz))`(복제용), `query(x,y,z,r) -> {id}`, `resize(halfX, halfZ)`(전부 깨움). 상수는 `TraySim.DT/SUB_MAX/SLEEP_*/WAKE_*/TIP_SPEED/...`.
- 알고리즘: SoA + xz 격자 넓은 단계(스텝당 1번, 여유 = 이동 예상) → 부분 스텝(이동 ≤ 최소 반 변×0.8, 최대 8) × 반복 4: 벽·바닥 고정 → 큐브 짝 AABB를
  **들어온 축**(부분 스텝 시작 때 떨어져 있던 축)으로 민다(세로면 위만 올림, 가로면 부피 역수 비율, 벽에 닿은 축은 못 밀림) → 속도 = 이동/시간, 반발 0.1(8 이상 충돌만), 쿨롱 마찰,
  받침이 올려 준 속도 상한 15(깊은 겹침 발사 방지), 받침 하나 + 무게중심 밖 + 옆 접촉 없음이면 4 st/s로 미끄러뜨림(회전 대용). 스텝 끝: 느린 짝이 아직 3% 넘게 겹치면 둘 다 깨워 둠(끼임).
  잠: 받쳐진 채 실제 이동 < 0.3이 10스텝 → 잠. 잠든 큐브도 0.01 넘게 밀리면 깨고, 깨면 위에 얹힌 잠든 큐브도 깬다.
- 측정 (Lune, 110개): 떨어지는 중 ≈ 0.25ms/스텝, 쌓인 더미 전부 깨움 ≈ 0.09ms, 전부 배트로 사방 200 st/s(부분 스텝 8) ≈ 0.55ms. 다 잠들면 0.
  떨어뜨리기 40배치: 전부 6초 안에 잠듦(중간값 3.5초, 최대 5.97초), 최악 겹침 < 3%. 자석 깡충(6스터드, 크기 2.2/3/5.6) 모두 MERGE_DISTANCE 안에서 만남.
- 한계: 회전 없음(AABB) → 실제보다 탑처럼 높게 쌓일 수 있음(110개 무작위 투하 시 최고 중심 y ≈ 24, 실제 Part는 무너져 더 낮음). 마찰은 바닥·받침만(옆면 마찰 없음).
  큐브끼리 반발 없음. 넓은 단계는 스텝 시작 때 잠든 짝을 빼므로, 스텝 중에 깬 큐브는 그 스텝 동안 잠든 이웃과 겹칠 수 있음(다음 스텝·끼임 처리로 풀림).

**단계 4 완료 (2026-10-21, Studio 확인 전)**: `Config.DATA_CUBES = true`(기본, 끄면 PartBackend 그대로). 커밋·Studio 확인은 메인 몫.
- 옮긴 것
  - `shared/CubeStyle.luau`: 예전 CubeWorld의 styleCube·styleVariant·markCeiling(크기·색·재질·변이 장식·Tier/AtMax/Variant 속성·VariantCube 태그). 서버 PartBackend·훔치기 들기 파트와 클라 CubeView가 같이 쓴다.
  - `server/SimBackend.luau`: 플롯마다 TraySim(중심 = plot.center, 바닥 y=0, 벽 = plot.width/2, 천장 = `Plots.GUARD_TOP` 48, slumpY = 벽 높이/2 = 8, 중력 = workspace.Gravity).
    body = id. restyle/markCeiling = look 데이터 + retier op(크기가 바뀌면 슬롯을 같은 위치·속도로 다시 넣음). teleport = sim 순간이동 + remove/spawn op(클라가 날아가듯 보간하지 않게).
    partOf → nil, release → 데이터에서 지우고(steal 사유) nil. 모든 플롯을 Heartbeat 하나에서 `sim:step(dt)`(폭이 바뀌면 `resize`) → `CubeNet.flush(dt)`.
  - `server/CubeWorld.luau`: Backend에 `create(plot, id, …)`(id를 먼저 정함), `destroy(body, reason)`, `close()` 추가. `remove(id, reason?)`, `close()`. PartBackend 파트에도 `CubeId` 속성.
  - Factory: 제거 사유(merge·sell·other), reveal Fx는 Part 대신 큐브 id, stop에서 `cubes:close()`. Steal: 목록 `{id, pos, tier, variant, slow}`, `Steal` 원격 인자 `number`(목록 안 id만 인정), 들기 파트는 `release() or CubeStyle.part(...)` + `CarriedCube` 태그(CubeLook이 얼굴·숫자).
  - core `Net`: `kind = "unreliable"`(UnreliableRemoteEvent, 서버 → 클라 전용, `on` 금지).
- 프로토콜 (`server/CubeNet.luau`, 좌표 = 플롯 중심 기준 = TraySim 좌표)
  - `CubeEvt` RemoteEvent `(plotIndex, gen, buffer)`: 한 프레임 op를 플롯별 한 패킷. 같은 프레임 spawn+겉모습 변경은 op 하나로 합침(spawn은 MAX 아님으로 시작, MAX면 retier 추가).
  - `CubeSnap` UnreliableRemoteEvent `(plotIndex, gen, buffer)`: 깨어 있는 큐브 + 방금 잠든 큐브(마지막 자리·속도 0, 2번 연속), 60개씩 나눔(900바이트 한도, 664B).
  - 빈도: 주인 15Hz, 플롯 중심 150스터드 안 5Hz(나갈 땐 170), 그 밖 스냅샷·op 없음. 관심 영역 0.25초마다.
  - reset: 접속(처음 보는 사람은 거리 상관없이 전 플롯), 범위에 들어올 때, 먼 플롯은 15초마다(멈춘 그림 갱신). 주인 나감 = 모두에게 빈 reset.
  - gen: 채널(플롯 주인)마다 새 번호. 클라는 gen이 바뀐 신뢰 메시지에서 엔티티를 모두 버리고, 다른 gen 스냅샷은 버린다(새 주인은 id 1부터). seq는 채널 단조 증가, 옛 seq 버림.
- 클라이언트 (`client/CubeView.luau`, init.client가 CubeLook 다음에 시작)
  - 플롯 Cubes 폴더(복제 폴더) 안에 로컬 파트: CubeStyle 겉모습 + `CubeId`, Anchored, CanCollide 끔, CanQuery 켬, CanTouch 끔, 그룹 Cubes. CFrame·속성을 정한 뒤 부모 지정.
  - 받은 시각으로 샘플(최대 6개). 지연 = 스냅샷 간격 추정 × 1.5(0.1~0.35초: 주인 100ms, 근처 300ms). 샘플 사이 에르미트(속도 차 > 30이면 직선), 뒤는 속도로 0.25초 외삽, 20스터드 넘게 튀면 바로 옮김, 오래 멈췄다 움직이면 멈춘 샘플을 한 간격 전으로 당김.
  - 회전 연출: 생길 때 무작위 yaw(0.35초 유지), 공중(|vy| > 3)이면 수평 속도/반 변 × 0.6으로 굴림(수직 낙하는 안 굴러 숫자가 위에 남음), 내려앉으면 가장 가까운 90°로(서버 AABB와 겉모습 일치).
  - 움직이는 것만 RenderStepped에서 `workspace:BulkMoveTo`. 모르는 id 스냅샷 항목 무시, spawn이 시작 위치·속도.
  - `CubeView.onLand(fn(plot, part, tier, speed))`: 보이는 시점에 빠르게(< −14) 떨어지던 샘플 다음 샘플이 > −3이면. `CubeView.part(plotIndex, id)`.
- 클라 모듈 적응: CubeLook·CubeLod·CubeInventory(흐리기·테두리)·Fx 변이 연출(VariantCube 태그)·Steal 표적 고르기는 폴더·속성만 보므로 그대로(로컬 파트에도 동작).
  init.client 착지 연출은 DATA_CUBES면 `CubeView.onLand`(로컬 Anchored 파트는 속도 0), 투하 연출(ChildAdded)은 그대로. reveal Fx는 CubeId로 매 프레임 찾음(spawn보다 Fx가 먼저 올 수 있음).
  Steal 고르기 창은 id로 받아 지금 서 있는 공장 폴더에서 `CubeId`로 파트를 찾아 외곽선.
- TraySim 추가 (테스트 4개 추가, 62개 통과): 회전이 없으면 고정된 드로퍼 자리에 외줄 탑이 천장까지 선다(같은 자리 40개 투하 → 꼭대기 43).
  `slumpY` 옵션(기본 없음 → 단계 2 동작 그대로): 밑면이 slumpY/2보다 높은 곳에서 받침보다 8 st/s 넘게 빨리 내려와 큐브 위에 착지하면 그 초과분 × 0.8로 옆으로 튕김(같이 떨어지는 쌓임은 0),
  밑면이 slumpY보다 높고 옆이 빈 채 큐브 위에만 얹혀 있으면 4 st/s로 미끄러짐(한가운데면 id마다 정해진 방향). 같은 자리 40개 → 꼭대기 14.5(벽 16 아래).
  드로퍼 8자리 순서 투하 측정: 60개/폭 40 → 꼭대기 ≈ 16.3, 124개/폭 56 → ≈ 16.7 (slump 전 44·48).
- TraySim 무너짐·배트 손봄 (테스트 78개 통과): ① 정확한 포물선 적분 — 반암시 오일러가 약한 위 속도의 꼭짓점을 30% 깎아 배트에 맞은 큐브가 거의 안 떴다(이제 vy²/2g).
  ② 무너짐 미끄럼 한도는 막혀도 흐르는 시간(SLIDE_TIME 1초, 벽 위 SLIDE_TIME_HIGH 1.5초): 구석·벽 큐브가 막힌 채 영영 밀어 잠들지 못하던 것. 벽 판정은 접촉 비트가 아니라 위치로(방향이 스텝마다 뒤집히던 것).
  벽 쪽으로 넘어가려다 벽에 끼면 벽 반대쪽 무너짐으로. 벽 위(밑면 > slumpY×1.5) 큐브가 이웃에 기대 멈추면 한도 안에서 이웃을 밀고 지나감.
  측정(slumpY 8, 천장 48): 무작위 110개 40배치 모두 6.5초 안에 잠듦(전 5개가 8초 넘게 깨어 있음). 8자리 0.2초 간격 30회: 60개/폭 40 → 29회 ≤ 17.5(최악 21.9),
  124개/폭 56 → 22회 ≤ 17.5(최악 22.0, 전 18회). 남는 것은 벽 높이(≈16)까지 찬 넓은 더미 위에 마지막 큐브 하나가 평평히 얹히는 경우(회전 없음 한계).
- 결정: 먼 플롯은 스냅샷 대신 가끔 reset(빈 트레이로 보이지 않게). 신뢰 op는 지연 없이 바로 적용(Fx.merge와 사라짐을 맞춤, 위치만 100ms 늦음). 텔레포트는 remove+spawn.
  거리 기반 순간이동 판정은 안전망만. 각속도(배트 setAngular)는 무시하고 클라 굴림으로 대신.
- 알려진 빈틈: 근처(5Hz)에서 보는 남의 트레이는 300ms 늦고 덜 부드럽다(훔치는 사람 화면). 범위 밖 플롯은 최대 15초 낡은 정지 그림.
  잠든 큐브의 마지막 위치를 담은 스냅샷 2개를 다 잃으면 다음 움직임·reset까지 조금 어긋날 수 있다. 큐브끼리 옆면 마찰·회전 없음(TraySim 한계 그대로).
  StreamingEnabled를 켜면 플롯 모델이 스트리밍으로 사라질 때 로컬 파트도 같이 사라진다(지금은 꺼짐 가정).

### 단계 5 완료 (2026-10-22, Studio 확인·측정)
- 자석 깡충이 사이에 낀 큐브에 막혀 같은 등급 짝이 영영 안 합쳐지던 문제(회전 없는 AABB라 넘지도 비키지도 못함):
  ① TraySim: 던져진 큐브는 옆 큐브를 타고 넘고, 깡충 높이는 길 위 가장 높은 큐브를 넘게(`TraySim.hopVelocity`, Factory `hopOver`).
  ② 그래도 둘 다 3번(`HOP_GIVE_UP`) 넘게 뛰고 못 만나면 멈춘 순간 **거리와 상관없이 결과로 합친다**(Factory `scanMerges`, DATA_CUBES만). 물리는 연출, 결과는 서버 데이터.
  확인: 상한 아래 큐브 40개(T21~T26), 드로퍼 없이 15초 × 3회 → 남는 짝 0 (상한 T28만 남음). 고치기 전엔 4짝이 30초 넘게 남음.
- 후반 재현(리버스 8, T18 드로퍼 8개 lv20, 1인, 20초 평균, 같은 PC):

| | 기존 Part 물리 (`DATA_CUBES=false`) | 데이터 큐브 |
|---|---|---|
| 서버 물리 (Stats.PhysicsStepTimeMs) | 2.55ms | **0.09ms** |
| 서버 Heartbeat (TraySim 포함) | 0.47ms | 0.48ms |
| 서버 전송 | 43.5kbps | 48.6kbps |
| 합치기/초 · 투하/초 | 20.9 · 13.2 | 23.0 · 14.0 |
| 서버 큐브 파트 | 56 | 0 |

  - 서버 물리 비용이 사실상 사라졌다(8인 후반 추정 ~20ms → ~1ms). 전송은 비슷(움직이는 큐브 스냅샷 ≈ 엔진 물리 복제). 대역폭이 문제되면 스냅샷 빈도·양자화부터 줄인다.
  - 롤백 확인: 플래그 false로 같은 측정, 에러 0.
- 아직 Studio에서 못 본 것(2인 필요): 훔치기 고르기·들기·되돌리기, 남의 트레이 5Hz 보간, 주인 퇴장 시 비우기. 공개 서버에서 2인 이상일 때 확인.

### 최적화 (2026-10-22)
Studio 측정 (리버스 12, T21 드로퍼 8개 lv30, 1인, 주인 클라이언트, 10~15초):

| | 최적화 전 (v55) | 후 |
|---|---|---|
| CubeSnap | 15.0/s, 8,363 B/s | 15.1/s, **4,852 B/s (−42%)** |
| 큐브 파트 새로 만들기 (안정 상태 15초) | 큐브 하나 생길 때마다 Part·Decal 2·SurfaceGui·TextLabel | **0개** (재사용 200번) |
| 재사용 파트 검사 (261개: 숫자=등급, 얼굴 2개, 크기, 흐림) | — | 틀린 것 0 |

- 측정 함정: `DescendantAdded`는 풀에서 꺼낸 파트를 폴더에 다시 넣을 때도 자식마다 불린다 → 생성 수로 쓰면 안 된다. "처음 보는 파트인가"로 센다.

설계 메모 (구현 시점):
측정(후반 T21 드로퍼 8, 트레이 ~55개, 1인, 주인 클라 10초): CubeSnap 15패킷/초 8,363B/s(≈67kbps, 패킷당 ~50항목 = 거의 모든 큐브 매번),
큐브 73%가 늘 10 st/s 넘게 움직임. 클라 인스턴스 생성 79/초(투하마다 Part + Decal 2 + SurfaceGui + TextLabel …, 합치기마다 파괴).

**1. 스냅샷 = 데드 레코닝 보정만** (`shared/CubePredict.luau` 새 파일, 서버·클라 같은 코드, `tests/CubePredict.spec.luau`)
- 예측식 `CubePredict.at`: air(지난 스텝에 받침 없음, `TraySim.eachAwake` 8번째 인자)면 중력 포물선 = TraySim 자유 낙하와 정확히 같음,
  아니면 가로 마찰 감속(TraySim 이산 마찰과 같은 식, 속력이 TIP_SPEED 4면 직선 미끄럼). 접촉은 흉내 내지 않음 → 서버가 보정. `HORIZON` 1.25초 넘으면 멈춤.
- 서버 `CubeNet`: 등급(주인·근처)마다 큐브별 "클라가 아는 상태"(보낸 양자화 값 + 시뮬 틱, `CubePredict.Known`)를 들고 `CubePredict.collect`로 고른다.
  깨어 있는 큐브: 처음 / 예측 위치 오차 > `POS_TOL`(주인 0.25, 근처 0.6) / 속도 차 > `VEL_TOL`(6, 12: 접촉·깡충·배트) / `KEEPALIVE` 1초.
  정지 상태(잠듦·막 멈춤)는 연속 2번(`FINAL_REPEAT` 1) + `REST_KEEPALIVE` 8초마다, 잠든 자리가 아는 자리와 `REST_TOL` 0.05 넘게 다르면 다시.
  spawn은 알던 상태를 지워 다음 스냅샷에 꼭 넣고(spawn op엔 틱이 없음), reset을 받은 사람이 있는 등급은 통째로 지워 깨어 있는 큐브를 다시 보낸다.
- 잃은 보정: 서버는 받았다고 보고 예측하므로, 움직이는 큐브는 keepalive(≤1초)·다음 어긋남이, 정지 자리는 연속 2번 + 8초 keepalive가 고친다.
  Lune 10% 손실 재현: 깨어 있는 큐브의 0.5스터드 넘는 오차는 최장 0.93초, 끝에 모든 정지 자리 오차 ≤ 0.05.
- 시간 기준: 서버는 시뮬 틱(`SimBackend` 고정 스텝 누적 수, 1/30초)으로 예측하고 스냅샷 헤더에 틱(u16)을 싣는다.
  클라는 `offset = min(받은 시각 − 틱×DT)`(가장 빨리 온 패킷 = 지연 최소, 늘면 패킷마다 5%씩 따라감)로 틱을 자기 시계에 옮긴다 → 샘플 시각 = 틱×DT + offset.
  서버 예측(틱 차이)과 클라 예측(시각 차이)이 같은 t를 쓰고, Heartbeat(시뮬 0/1스텝)·네트워크 흔들림이 위치 오차로 바뀌지 않는다.
  spawn·reset(신뢰, 틱 없음)은 받은 시각에 둔다. 렌더는 예전처럼 지연(스냅샷 주기 × 1.5: 주인 100ms, 근처 300ms) 뒤를 그린다.
- 클라 `CubeView`: 렌더 시각에서 지난 마지막 샘플로 예측, 다음 샘플이 와 있으면 그 직전 한 주기 동안 그 샘플로 섞음(에르미트, 속도 차 > 30이면 직선) →
  접촉 직전 주기 안에서 섞이므로 바닥을 뚫고 내려갔다 튀지 않는다. 늦게 와서 지금 그림을 바꾸는 보정은 차이를 err로 들고 τ 35ms로 줄임(100ms면 ~6%).
  20스터드 넘게 튀면 바로 옮김. 착지 연출은 앞 샘플로 예측한 들어오는 세로 속도로 판정. spawn보다 먼저 온 항목은 1초까지 들고 있다가 spawn 때 씀.
- 형식(`CubeCodec`, 테스트 갱신): 헤더 7B `seq u16 | tick u16 | hz u8 | nMove u8 | nRest u8`,
  움직임 12B `id u16 | 위치 3×12비트(1/32, ±64) | 속도 3×12비트(1/8 st/s, ±256) + air 1비트`(40비트 둘), 정지 7B `id | 위치`.
  예전 11B(속도 i8 × 2 st/s)는 오차 1 st/s라 예측이 0.25초 만에 0.25스터드 어긋났다. 이제 1초 예측 오차 ≤ 0.06.
- Lune 재현(`tests/CubePredict.spec`: 폭 40, T19~T23 55개, 드로퍼 8자리 14개/초 + 자석 깡충 14번/초 + 합치기, 10초):
  예전 방식 6,620B/s → **3,031B/s (46%)**, 항목 8,946 → 4,037. 보낸 직후 클라 = 서버(≤ 0.25), 1스터드 넘는 오차는 큐브·틱의 0.9%(접촉·깊은 겹침 밀어내기 순간, 렌더 보간이 덮음).
  남은 항목은 대부분 더미 안 밀침·착지·깡충 시작(예측할 수 없는 접촉). Studio 기대: CubeSnap ≈ 8.4KB/s → 3.5~4.5KB/s.
- 패킷 수는 그대로(보낼 것이 있으면 15Hz). 정지 keepalive 비용 ≈ 55개/8초 × 7B ≈ 50B/s.

**2. 클라 큐브 파트 풀** (`CubeView` + `CubeStyle.park/reuse`)
- 지운 큐브 파트는 부모를 떼어(nil) 풀에(최대 150, 모든 플롯 공용), 새 큐브는 풀에서 꺼내 `CubeStyle.reuse`(같은 등급·일반이면 속성·자식 그대로) 후 CubeId → 폴더에 넣음.
  폴더에 다시 들어가므로 ChildAdded(init.client 투하 연출, CubeLook)는 그대로. CubeLook은 Num이 있으면 새로 안 만들고, 처음 단 Tier·AtMax 감시가 꺼낼 때 바뀐 등급으로 고친다.
- 넣을 때 `CubeStyle.park`: 변이 장식(껍데기·용접·테두리·입자·이름표·VariantDecor)을 지우고 일반 겉모습으로(색·재질·반사 포함), VariantCube 태그·AtMax 떼기.
  그래서 풀 안 파트는 늘 일반 → 변이로 꺼내면 장식을 새 CFrame에서 처음부터 단다(껍데기 WeldConstraint가 제자리). 등급 빛(Glow·Sparkle)·얼굴·숫자는 남겨 다시 씀.
  다른 클라 모듈이 남긴 화면 상태도 되돌린다: LocalTransparencyModifier(CubeInventory 흐리기), LodOff·FocusOff로 끈 빛·입자·글자·테두리.
- 기대: 일반 큐브 투하는 인스턴스 생성 0 (풀이 비었을 때·변이·등급대가 바뀌어 Glow/Sparkle이 생길 때만) → 79/초 → 수/초.
- 파트를 오래 들고 있는 쪽은 CubeId를 다시 확인해야 한다(다른 큐브로 다시 쓰임): init.client reveal 연출 고침. Steal 표적 강조는 고를 때마다 CubeId로 찾는다
  (단, 고르기 창이 열린 사이 강조 중인 큐브가 합쳐지고 그 파트가 곧 새 큐브로 쓰이면 강조가 새 큐브로 옮겨 갈 수 있다 — 마우스를 다시 올리면 맞음).
- `Config.DATA_CUBES=false`(PartBackend)는 바뀐 것 없음: 서버 파트를 CubeLook이 그대로 꾸민다.

## 3. 위험과 대응
- **쌓임 떨림**: PBD 반복·잠 조건으로 잡고, Lune 테스트에 "110개 떨어뜨리고 5초 뒤 최대 속도 < 0.5" 기준.
- **보기에 딱딱함**(회전 없음): CubeView가 공중 속도에 비례해 굴림 회전을 연출하고 착지 때 가장 가까운 90° 회전으로 맞춘다.
- **훔치기 들기**: 들린 큐브는 데이터에서 빠지고, 머리 위 표시는 지금처럼 서버 Part 하나(사람당 최대 1개).
- **롤백**: 플래그 끄면 PartBackend(지금 동작). 저장 데이터 형식은 바뀌지 않는다(트레이는 등급·변이만 저장).
