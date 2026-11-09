--!strict
-- 머지 팩토리 Remote 계약 (core/shared/Net 형식)
-- 클라 → 서버는 "의도"만 보낸다. 결과(잔액·큐브)는 전부 서버가 정한다.

return {
	-- 클라 → 서버
	Drop = { kind = "event", args = { "number" } }, -- 트레이 폭 기준 -1..1 위치에 1등급 큐브 투하
	Buy = { kind = "function", args = { "string", "number" } }, -- ("speed"|"tier", 드로퍼 번호) / ("slot", 0) / ("all", 0) 일괄 강화
	Upgrade = { kind = "function", args = { "string" } }, -- Economy.UPGRADES id (polish|lucky|hatch|tray)
	Rebirth = { kind = "function", args = {} },
	Swing = { kind = "function", args = {} }, -- 배트 휘두르기 → 맞은 내 큐브 수 (서버가 범위·쿨다운 판정)
	BatUpgrade = { kind = "function", args = { "string" } }, -- 배트 강화 range|power|speed (젬)
	StealList = { kind = "function", args = {} }, -- 남의 트레이 안에서 훔칠 수 있는 근처 큐브 목록 (최대 STEAL_LIST개)
	Steal = { kind = "function", args = { "number" } }, -- 목록에서 고른 큐브 id를 훔쳐 듦 → 성공 여부, 실패 이유
	StarterOffered = { kind = "function", args = {} }, -- 스타터 팩 제안 창을 띄웠다고 기록 (하루 1번, 최대 3번)
	RateAsked = { kind = "function", args = {} }, -- 좋아요·즐겨찾기 부탁 창을 봤다고 기록 (보상 없음)
	GetLeaderboard = { kind = "function", args = {} }, -- 랭킹 캐시 { boards = {{id,title,entries}}, live } -- 섞기 1회 사용 (무료 먼저, 그다음 유료)
	ClaimCore = { kind = "function", args = { "number" } }, -- 부화기 번호
	ClaimOffline = { kind = "function", args = {} },
	Equip = { kind = "function", args = { "string" } }, -- 꾸미기 장착 (해금된 것만, docs/16)
	BuyCosmetic = { kind = "function", args = { "string" } }, -- 젬으로 꾸미기 구매 (확정)
	ClaimCodex = { kind = "function", args = { "string" } }, -- 도감 보상 받기: 칸 키("7:Rainbow") 또는 "milestone" → 받은 젬
	ClaimGift = { kind = "function", args = { "string" } }, -- 접속 선물 "small"|"big" → (보상 id, 글자) (docs/23)
	ClaimQuest = { kind = "function", args = { "number" } }, -- 일일 퀘스트 1..3, 0 = 완주 보너스 → 글자
	ClaimLogin = { kind = "function", args = {} }, -- 7일 출석 오늘 칸 받기 → 글자
	PetHatch = { kind = "function", args = { "string", "number" } }, -- (알 id, 개수 1|3) → 결과 {{u,id,star,new}} 또는 (nil, 이유) (docs/24)
	PetAction = { kind = "function", args = { "string", "number" } }, -- ("equip"|"fuse"|"release"|"best", 펫 uid)
	-- 서버 → 클라
	State = { kind = "event" }, -- 1초마다 내 상태 요약
	Merged = { kind = "event" }, -- (position: Vector3, tier: number, combo: number, owner: Player, isBest: boolean)
	Fx = { kind = "event" }, -- ("core", pos, name) | ("hatch", pos, name, payout) | ("rebirth", pos) | ("lucky", pos, tier) | ("milestone", text, target) | ("shuffle", pos) | ("variant", pos, tier, variantId, how, isNew, gems) | ("reveal", pos, tier, variantId, cubeId) | ("codex", text, gems)
	Toast = { kind = "event" }, -- (text: string)
	-- 데이터 큐브 복제 (docs/27 단계 4, Config.DATA_CUBES). 위치는 플롯 중심(트레이 바닥 윗면 가운데) 기준
	CubeEvt = { kind = "event" }, -- (plotIndex, gen, buffer: CubeCodec.encodeEvents) spawn/remove/retier/reset, 프레임마다 플롯별로 묶음
	CubeSnap = { kind = "unreliable" }, -- (plotIndex, gen, buffer: CubeCodec.encodeSnapshot) 데드 레코닝 보정(예측과 어긋난 큐브만). 주인 15Hz, 150스터드 안 5Hz
}
