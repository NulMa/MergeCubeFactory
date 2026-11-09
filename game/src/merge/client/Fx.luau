--!strict
-- Merge 연출 — 엔진(소리 풀·파티클·흔들림·팝업·배너)은 core/client/Fx, 여기는 Merge 사건별 연출.
--   * 고스트: 합쳐진 자리에 흰 섬광 큐브 + 웃는 얼굴이 부풀었다 사라짐 (서버 물리 큐브는 건드리지 않음).
--   * 충격파: 바닥에 누운 고리 텍스처가 퍼짐.
--   * 소리: 큰 합치기일수록 낮은 쿵 + 높은 반짝임을 겹친다.
-- 모든 연출은 클라이언트 전용(서버 비용 0). 내 플롯 연출만 크게, 남의 플롯은 작게.
-- 다른 Merge 모듈은 이 모듈만 require한다 (core Fx 함수도 여기서 그대로 내보냄).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Game.Config)
local VariantDecor = require(ReplicatedStorage.Game.VariantDecor)
local AssetIds = require(ReplicatedStorage.Game.AssetIds)
local CoreFx = require(ReplicatedStorage.CoreClient.Fx)
local Hype = require(ReplicatedStorage.CoreClient.Hype)
local Loc = require(ReplicatedStorage.CoreClient.Loc)

local player = Players.LocalPlayer
local Fx = {}

-- core 엔진 그대로
Fx.sound = CoreFx.sound
Fx.burst = CoreFx.burst
Fx.shake = CoreFx.shake
Fx.fovPunch = CoreFx.fovPunch
Fx.screenFlash = CoreFx.screenFlash
Fx.popup = CoreFx.popup
Fx.purchase = CoreFx.purchase
Fx.bump = CoreFx.bump
Fx.banner = CoreFx.banner

local tween = CoreFx.tween
local lighten = CoreFx.lighten
local fxPart = CoreFx.part
local ghost = CoreFx.ghost
local ringWave = CoreFx.ring
local nearCamera = CoreFx.nearCamera
local SCALE_UP = CoreFx.SCALE_UP

------------------------------------------------------------------------
-- 소리 (core Fx에 등록)
------------------------------------------------------------------------
local SOUND_IDS: { [string]: string } = {
	Pop = AssetIds.Sounds.Pop,
	Chime = AssetIds.Sounds.Chime,
	Sparkle = AssetIds.Sounds.Sparkle,
	Whoosh = AssetIds.Sounds.Whoosh,
	Thump = AssetIds.Sounds.Thump,
	Coin = AssetIds.Sounds.Coin,
	LevelUp = AssetIds.Sounds.LevelUp,
	Merged = Config.SOUNDS.Merged,
	Land = Config.SOUNDS.Land,
	Impact = Config.SOUNDS.Impact,
	Boom = Config.SOUNDS.Boom,
	Fanfare = AssetIds.Sounds.Fanfare,
	BatPing = AssetIds.Sounds.BatPing, -- 알루미늄 배트 '팅' (tools/make_fx_assets.py bat)
	Bonk = AssetIds.Sounds.Bonk,
	-- 배트 스킨별 타격음 (2026-10-19, Config 배트 hitSound)
	HitBoing = (AssetIds.Sounds :: any).HitBoing,
	HitClang = (AssetIds.Sounds :: any).HitClang,
	HitCrunch = (AssetIds.Sounds :: any).HitCrunch,
	HitGlass = (AssetIds.Sounds :: any).HitGlass,
	HitGold = (AssetIds.Sounds :: any).HitGold,
	HitHammer = (AssetIds.Sounds :: any).HitHammer,
	HitRainbow = (AssetIds.Sounds :: any).HitRainbow,
	HitSqueak = (AssetIds.Sounds :: any).HitSqueak,
	HitSquish = (AssetIds.Sounds :: any).HitSquish,
	HitWood = (AssetIds.Sounds :: any).HitWood,
	HitZap = (AssetIds.Sounds :: any).HitZap,
}

-- 효과음 최대 길이(초). maxLen을 안 넘겨도 이 길이에서 짧게 페이드아웃한다 — 긴 소리가 남지 않게 (플레이테스트 2026-10-18).
-- Boom(1.6초)·Impact(0.8초)가 길게 울리던 원인. 레인보우 합성 때의 긴 징글(옛 NewBest)은 자르지 않고
-- 짧은 합성음 Fanfare(0.63초)로 바꿨다 — 잘리지 않게 상한을 넉넉히 둔다
local SOUND_MAX: { [string]: number } = {
	Fanfare = 1,
	Boom = 0.6,
	Impact = 0.5,
	Sparkle = 0.5,
}
local SOUND_MAX_DEFAULT = 0.6

-- 배트 타격음 묶음 (2026-10-19 "배트 효과음 더 다양하고 재밌게, 에셋 찾아서 / 진짜 닭소리 / 생선은 찰싹"):
-- 칠 때마다 묶음에서 하나를 골라 낸다. 문자열은 위 SOUND_IDS 키(직접 합성한 소리), 표는 Creator Store 소리
-- (Roblox 라이선스 ProSoundEffects 우선, 없으면 공개 무료 업로드. 출처는 creator 이름으로 적어 둠)
type BatSfx = string | { id: number, len: number, vol: number? }
local BAT_SFX: { [string]: { BatSfx } } = {
	HitSqueak = { -- 고무 닭 → 진짜 닭 울음
		{ id = 125408037908664, len = 0.6 }, -- "Cluck 1" (Zelgraz)
		{ id = 88279026957024, len = 0.8 }, -- "Chicken sfx_3" ([EL] Bloom Entertainment)
		{ id = 137857373943195, len = 1 }, -- "Chicken Sfx_2" ([EL] Bloom Entertainment)
	},
	HitSquish = { -- 생선 → 젖은 찰싹
		{ id = 100903093292054, len = 0.5, vol = 1 }, -- "FISH SLAP" (SiIIyDaniel)
		{ id = 9120647258, len = 0.4 }, -- Wet Newspaper Slap 3 (ProSoundEffects)
		{ id = 9120647607, len = 0.5 }, -- Wet Newspaper Slap 10 (ProSoundEffects)
	},
	HitWood = { "HitWood", { id = 9113288506, len = 0.5 } }, -- Baseball 1, 나무 배트로 공 치기 (ProSoundEffects)
	HitZap = {
		"HitZap",
		{ id = 9116276051, len = 0.6 }, -- Lightning Flashes Quick Electrical Bursts 11 (ProSoundEffects)
		{ id = 9116275998, len = 0.6 }, -- 같은 묶음 13
	},
	HitGlass = {
		"HitGlass",
		{ id = 9114615010, len = 0.7 }, -- Glass Smashes 7 (ProSoundEffects)
		{ id = 9114591515, len = 0.7 }, -- Glass Breaks 2 (ProSoundEffects)
	},
	HitClang = { -- 프라이팬: 울리는 '댕~'
		{ id = 9117199185, len = 0.9 }, -- Pan Hits With Knuckles Heads 2 (ProSoundEffects)
		{ id = 9119072674, len = 0.8 }, -- Shield Clang As Hit Metal Sword Hubcap 2 (ProSoundEffects)
		"HitClang",
	},
}
-- Store 소리도 Fx.sound로 낼 수 있게 키 등록 (Bat_<id>), 길이 상한은 항목의 len
for _, list in BAT_SFX do
	for _, e in list do
		if type(e) == "table" then
			local key = `Bat_{e.id}`
			SOUND_IDS[key] = `rbxassetid://{e.id}`
			SOUND_MAX[key] = e.len
		end
	end
end

-- 보스 레이드 중엔 큰 배너를 미뤘다가 집에 온 뒤 띄운다 (2026-10-20 사용자 "레이드 중 다른 알림 없음")
local function raiding(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("FactoryHud")
	return hud ~= nil and hud:GetAttribute("InRaid") == true
end

CoreFx.configure({
	sounds = SOUND_IDS,
	soundMax = SOUND_MAX,
	soundMaxDefault = SOUND_MAX_DEFAULT,
	images = AssetIds.Images :: any,
	bannerHold = raiding,
})

------------------------------------------------------------------------
-- 게임 이벤트별 연출
------------------------------------------------------------------------

-- 콤보 음계: 장조 (도레미솔라도...) → 연쇄할수록 올라감
local SCALE = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24 }
local MERGE_SOUND_MAX = 0.4

-- best = 내 최고 등급. 최고보다 한참 낮은 합치기(게임 대부분)는 조용히, 최고 근처·새 최고만 크게 (docs/18 §1·§2)
-- 남의 병합: 120스터드 안, 초당 OTHERS_PER_SEC개까지, 잔상·고리 없이 (다인 서버 프레임 보호)
local OTHERS_PER_SEC = 6
local othersCount, othersSince = 0, 0
-- 내 합치기도 초당 MINE_FULL_PER_SEC개 넘게 몰리면(후반 드로퍼 8개: 초당 ~22) 나머지는 가볍게:
-- 섬광 큐브·고리·반짝이 없이 조각 입자 반만, 소리는 간격을 둔다. 새 최고·콤보 마일스톤은 늘 크게 (2026-10-21 고등급 렉)
local MINE_FULL_PER_SEC = 8
local mineCount, mineSince = 0, 0
local LITE_GAP: { [string]: number } = { Pop = 0.05, Merged = 0.08, Chime = 0.08, Impact = 0.12 }

-- 큐브 위젯 눈으로 한 등급을 찾는 중이면(CubeInventory가 CubeFocus) 다른 등급의 연출은 줄인다
local function unfocused(tier: number): boolean
	local f = player:GetAttribute("CubeFocus")
	return typeof(f) == "number" and tier ~= f
end

function Fx.merge(at: Vector3, tier: number, combo: number, owner: Player, isBest: boolean?, best: number?)
	local mine = owner == player
	-- 찾는 등급이 아닌 합치기는 소리만 작게 (tier는 합친 결과라 찾는 등급끼리 합친 것(tier - 1)·새 최고 등급은 그대로)
	if unfocused(tier) and unfocused(tier - 1) and not isBest then
		Fx.sound("Pop", at, if mine then 0.3 else 0.12, 1.2, nil, MERGE_SOUND_MAX)
		return
	end
	if not nearCamera(at, if mine then 200 else 120) then
		return
	end
	if not mine then
		local now = os.clock()
		if now - othersSince >= 1 then
			othersCount, othersSince = 0, now
		end
		othersCount += 1
		if othersCount > OTHERS_PER_SEC then
			return
		end
	end
	local lite = false
	if mine then
		local t = os.clock()
		if t - mineSince >= 1 then
			mineCount, mineSince = 0, t
		end
		mineCount += 1
		lite = mineCount > MINE_FULL_PER_SEC and not isBest and not Hype.comboMark(combo)
	end
	local function gap(key: string): number?
		return if lite or not mine then LITE_GAP[key] else nil
	end
	local color = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
	local size = Config.cubeSize(tier)
	local power = math.clamp((tier - 1) / 11, 0, 1) -- 0..1 (12등급 이상은 최대 연출)
	local level = if isBest then 3 else Hype.progress(tier, best or tier)
	local quiet = if level == 0 then 0.6 else 1

	-- 소리: 팝(크기가 클수록 낮게) + 콤보 차임(연쇄할수록 높게) + 큰 등급 저음
	local vol = (if mine then 1 else 0.35) * quiet
	Fx.sound("Pop", at, 0.7 * vol, 1.35 - power * 0.6, gap("Pop"), MERGE_SOUND_MAX)
	if level >= 1 then
		Fx.sound("Merged", at, 0.35 * vol, 0.9 + power * 0.3, gap("Merged"), MERGE_SOUND_MAX)
	end
	if combo >= 2 then
		local step = SCALE[math.min(combo - 1, #SCALE)]
		Fx.sound("Chime", at, 0.4 * vol, 2 ^ (step / 12), gap("Chime"), MERGE_SOUND_MAX)
	end
	if tier >= 7 and level >= 1 then
		Fx.sound("Impact", at, (0.4 + power * 0.5) * vol, 1.1 - power * 0.3, gap("Impact"), MERGE_SOUND_MAX)
	end
	-- 40등급 체계에선 10등급 이상이 게임 대부분이라, 폭음·섬광·FOV는 새 최고 등급에만 (매 합치기면 피로)
	if isBest and tier >= 10 then
		Fx.sound("Boom", at, 0.6 * vol, 1, nil, MERGE_SOUND_MAX)
	end

	-- 시각
	if mine and not lite then
		ghost(at, size, color, tier >= 6 and level >= 1)
	end
	Fx.burst("Glow", at, 1, 0.5 + size * 0.25, lighten(color, 0.5))
	local chunks = ((if mine then 8 else 4) + math.min(tier, 12)) * quiet * (if lite then 0.5 else 1)
	Fx.burst("Chunk", at, math.floor(chunks), 0.35 + size * 0.12, color)
	if mine and not lite and tier >= 4 and level >= 1 then
		Fx.burst("Sparkle", at, 3 + math.min(tier, 12), 0.4 + size * 0.1, lighten(color, 0.6))
	end
	if mine and not lite then
		ringWave(at - Vector3.new(0, size / 2 - 0.1, 0), size * (2 + power * 3), color, 0.35 + power * 0.25)
	end

	if mine then
		local shakeBase = if level == 0 then 0.04 else 0.1 + power * 0.2
		Fx.shake(shakeBase + (if isBest then 0.25 else 0))
		if isBest and tier >= 8 then
			Fx.fovPunch(2 + math.min(tier - 8, 4) * 1.5)
		end
		if isBest and tier >= 10 then
			Fx.screenFlash(lighten(color, 0.5), 0.35, 0.4)
		end
		-- 콤보 글자는 마일스톤(3/5/10/25/50/100)에서만, 높을수록 크게
		local mark = Hype.comboMark(combo)
		if mark then
			Fx.popup(
				at + Vector3.new(0, size, 0),
				Loc.msg("fx.combo", { n = combo }),
				Color3.fromRGB(255, 209, 61):Lerp(Color3.fromRGB(255, 90, 160), (mark - 1) / 3),
				0.9 + mark * 0.25,
				1 + mark * 0.15
			)
			Fx.shake(0.08 * mark)
			if mark >= 2 then
				Fx.sound("Sparkle", nil, 0.3 + mark * 0.08, 1 + mark * 0.1)
				Fx.burst("Sparkle", at, 8 * mark, 0.8 + mark * 0.2, Color3.fromRGB(255, 220, 120))
			end
			if mark >= 3 then
				Fx.screenFlash(Color3.fromRGB(255, 230, 160), 0.12 * mark, 0.3)
				Fx.fovPunch(mark * 1.5)
			end
		end
		if isBest then
			Fx.newBest(at, tier)
		end
	end
end

-- 처음 도달한 등급: 팡파레 + 큰 글자 + 반짝이 폭발
function Fx.newBest(at: Vector3, tier: number)
	local color = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
	task.delay(0.12, function()
		-- 새 최고 등급도 병합 순간이라 짧게: 팡파레(Fanfare)는 마일스톤·레어 변이 전용
		Fx.sound("LevelUp", nil, 0.55, if tier >= 8 then 1.15 else 1, nil, MERGE_SOUND_MAX + 0.1)
		Fx.popup(
			at + Vector3.new(0, Config.cubeSize(tier) + 2, 0),
			Loc.msg("fx.newTier", { tier = tier, label = string.upper(Config.TIER_NAMES[tier] or "") }),
			lighten(color, 0.2),
			1.6,
			1.6
		)
		Fx.burst("Sparkle", at, 24, 1.2, lighten(color, 0.6))
		Fx.shake(0.3)
	end)
end

-- 큐브가 새로 떨어지기 시작: 작은 바람 소리 + 연기 + 드로퍼 찌그러짐
function Fx.drop(at: Vector3, dropper: BasePart?)
	Fx.sound("Whoosh", at, 0.18, 0.9 + math.random() * 0.3, 0.12)
	Fx.burst("Puff", at, 2, 0.5)
	if dropper and not dropper:GetAttribute("Squashing") then
		dropper:SetAttribute("Squashing", true)
		local base = dropper.Size
		tween(dropper, 0.06, { Size = Vector3.new(base.X * 1.25, base.Y * 0.7, base.Z * 1.25) })
		task.delay(0.06, function()
			tween(dropper, 0.25, { Size = base }, Enum.EasingStyle.Elastic)
			task.delay(0.25, function()
				dropper:SetAttribute("Squashing", nil)
			end)
		end)
	end
end

-- 바닥/큐브에 착지: 속도에 비례한 쿵 + 먼지
function Fx.land(at: Vector3, tier: number, speed: number)
	local size = Config.cubeSize(tier)
	local k = math.clamp((speed - 10) / 50, 0, 1)
	Fx.sound("Thump", at, 0.15 + k * 0.45, 1.25 - math.min(1, tier / 12) * 0.5, 0.05)
	if unfocused(tier) then
		return
	end
	Fx.burst("Puff", at - Vector3.new(0, size / 2, 0), 2 + math.floor(k * 4), 0.4 + size * 0.15)
	if tier >= 8 and k > 0.4 then
		Fx.shake(0.08 + k * 0.12)
	end
end

-- 코어 발견: 반짝 + 글자
function Fx.coreFound(at: Vector3, name: string)
	Fx.sound("Sparkle", at, 0.5, 1.2)
	Fx.burst("Sparkle", at, 14, 1, Color3.fromRGB(180, 230, 255))
	Fx.popup(
		at + Vector3.new(0, 3, 0),
		Loc.msg("fx.coreFound", { core = string.upper(name) }),
		Color3.fromRGB(150, 225, 255),
		1.1,
		1.3
	)
end

-- 부화 수령: 화면 섬광 + 팡파레 + 색종이
function Fx.hatch(at: Vector3, name: string, payoutText: string)
	local text = Loc.msg("fx.hatched", { core = name, cash = payoutText })
	Fx.sound("Sparkle", nil, 0.7, 1)
	Fx.sound("Coin", nil, 0.5, 1)
	Fx.screenFlash(Color3.fromRGB(200, 240, 255), 0.3, 0.45)
	Fx.burst("Chunk", at, 40, 1.4, Color3.fromHSV(math.random(), 0.6, 1))
	Fx.burst("Sparkle", at, 30, 1.4)
	Fx.popup(at + Vector3.new(0, 6, 0), text, Color3.fromRGB(255, 209, 61), 1.5, 1.8)
	Fx.shake(0.35)
end

-- 리버스: 큰 섬광 + 레벨업
function Fx.rebirth(at: Vector3)
	Fx.sound("LevelUp", nil, 0.7, 0.8)
	Fx.sound("Boom", nil, 0.5, 1)
	Fx.screenFlash(Color3.new(1, 1, 1), 0.8, 0.9)
	Fx.burst("Sparkle", at, 60, 2)
	Fx.shake(0.6)
	Fx.fovPunch(8)
end

-- 구매 성공 (UI): 카칭 + 버튼 튕김
-- 연속 구매일수록 음높이가 장음계로 올라감(최대 1옥타브), 1.5초 쉬면 처음부터 (docs/14 §3.3-3)

------------------------------------------------------------------------
-- 업그레이드 구매 반응: 산 대상이 직접 반응한다 (docs/14 §3.3-2)
------------------------------------------------------------------------

-- 드로퍼: 번쩍 부풀었다 돌아옴 + 반짝이 + 바뀐 수치
function Fx.dropperUpgrade(dropper: BasePart, text: Loc.Text, color: Color3)
	local at = dropper.Position
	Fx.burst("Sparkle", at, 14, 0.9, lighten(color, 0.4))
	Fx.popup(at + Vector3.new(0, 3, 0), text, lighten(color, 0.3), 1.05, 1.1)
	if dropper:GetAttribute("Squashing") then
		return
	end
	dropper:SetAttribute("Squashing", true)
	local base = dropper.Size
	local glow = fxPart({
		Size = base * 1.15,
		CFrame = dropper.CFrame,
		Color = lighten(color, 0.6),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	tween(glow, 0.4, { Size = base * 1.8, Transparency = 1 })
	task.delay(0.45, function()
		glow:Destroy()
	end)
	tween(dropper, 0.08, { Size = base * 1.35 })
	task.delay(0.08, function()
		tween(dropper, 0.35, { Size = base }, Enum.EasingStyle.Elastic)
		task.delay(0.35, function()
			dropper:SetAttribute("Squashing", nil)
		end)
	end)
end

-- 새 드로퍼 해금: 위에서 쿵 + 큰 반짝이
function Fx.dropperUnlock(dropper: BasePart)
	Fx.sound("LevelUp", dropper.Position, 0.5, 1.1)
	Fx.burst("Chunk", dropper.Position, 20, 1, Color3.fromRGB(255, 209, 61))
	ringWave(dropper.Position - Vector3.new(0, 1.5, 0), 8, Color3.fromRGB(255, 230, 140), 0.5)
	Fx.popup(dropper.Position + Vector3.new(0, 4, 0), "NEW DROPPER!", Color3.fromRGB(255, 209, 61), 1.3, 1.4)
	Fx.shake(0.2)
end

-- 공장 전체 업그레이드(광택·행운): 트레이 전체에 물결
function Fx.factoryWave(center: Vector3, radius: number, text: Loc.Text, color: Color3)
	ringWave(center, radius, color, 0.6)
	Fx.burst("Sparkle", center + Vector3.new(0, 4, 0), 20, 1.6, lighten(color, 0.5))
	Fx.popup(center + Vector3.new(0, 10, 0), text, color, 1.4, 1.2)
end

-- 배트 명중: 쿵 + 범위 고리 + (많이 맞으면) 글자·흔들림
function Fx.batHit(at: Vector3, hits: number, range: number, hitSound: string?)
	local hot = Color3.fromRGB(255, 200, 120)
	-- 배트 스킨 소리(없으면 알루미늄 '팅') + 만화풍 bonk (예전 Thump·Impact는 둔해서 교체, 2026-10-19)
	local pool = hitSound and BAT_SFX[hitSound]
	if pool then
		local e = pool[math.random(#pool)]
		if type(e) == "table" then
			Fx.sound(`Bat_{e.id}`, nil, e.vol or 0.9, 0.93 + math.random() * 0.14)
		else
			Fx.sound(e, nil, 0.8, 0.95 + math.random() * 0.1)
		end
		Fx.sound("Bonk", at, 0.2 + math.min(hits, 8) * 0.03, 1 + math.random() * 0.08)
	elseif hitSound and SOUND_IDS[hitSound] then
		Fx.sound(hitSound, nil, 0.8, 0.95 + math.random() * 0.1)
		Fx.sound("Bonk", at, 0.25 + math.min(hits, 8) * 0.03, 1 + math.random() * 0.08)
	else
		Fx.sound("BatPing", nil, 0.75, 0.95 + math.random() * 0.1)
		Fx.sound("Bonk", at, 0.45 + math.min(hits, 8) * 0.04, 1 + math.random() * 0.08)
	end
	ringWave(at - Vector3.new(0, 2.5, 0), range, hot, 0.3)
	Fx.burst("Puff", at, 3 + math.min(hits, 8), 0.8)
	Fx.burst("Chunk", at, 4 + hits, 0.7, hot)
	Fx.shake(0.08 + math.min(hits, 10) * 0.025)
	if hits >= 3 then
		Fx.popup(
			at + Vector3.new(0, 4, 0),
			Loc.msg("fx.whack", { n = hits }),
			hot,
			0.9 + math.min(hits, 10) * 0.06,
			0.9
		)
	end
end

-- 행운 합치기 (2단계 점프)
function Fx.lucky(at: Vector3, tier: number)
	local green = Color3.fromRGB(130, 255, 150)
	Fx.sound("Chime", at, 0.6, 1.5)
	Fx.sound("Sparkle", at, 0.4, 1.3)
	Fx.burst("Sparkle", at, 26, 1.3, green)
	Fx.popup(at + Vector3.new(0, Config.cubeSize(tier) + 3, 0), Loc.msg("fx.lucky", { n = 2 }), green, 1.4, 1.3)
end

------------------------------------------------------------------------
-- 변이 (docs/16 §1): 등급(희귀도)이 높을수록 크게
------------------------------------------------------------------------

local function variantColor(id: string): Color3
	local style = Config.VARIANT_STYLE[id]
	return if style then style.tag else Color3.new(1, 1, 1)
end

-- 무지개 여러 번 섬광 (가장 드문 변이)
local function rainbowFlash(times: number, alpha: number)
	for i = 0, times - 1 do
		task.delay(i * 0.12, function()
			Fx.screenFlash(Color3.fromHSV((i / times) % 1, 0.55, 1), alpha, 0.35)
		end)
	end
end

-- 공개 연출(Fx.reveal)을 거친 변이: 이어지는 Fx.variant가 최소 3단계가 되도록 표시
local revealedAt: { [string]: number } = {}

-- 변이 큐브 등장: rank 1(Metallic)~6(Divine). how = drop|roll|fusion|keep, isNew면 도감 "NEW!" + 젬
-- 크기는 Hype 단계(0~4)로: 희귀도 + 처음 봄 − 익숙해짐 + 가뭄 − 예산 (docs/18 §1). Cosmic·Divine은 4단계에 전용 섬광을 더한다
function Fx.variant(at: Vector3, tier: number, id: string, rank: number, how: string, isNew: boolean, gems: number)
	local color = variantColor(id)
	local size = Config.cubeSize(tier)
	local style = Config.VARIANT_STYLE[id]
	local label = if style then style.label else string.upper(id)
	local head = at + Vector3.new(0, size + 2, 0)
	local title = if how == "fusion" then `FUSION! {label}!` else `{label}!`
	local revealed = revealedAt[id] ~= nil and os.clock() - revealedAt[id] < 3
	revealedAt[id] = nil
	local level = Hype.discover("variant:" .. id, rank, isNew, how == "keep", revealed)

	-- 소리: 반짝 → (1+) 차임 → (3+) 팡파레 → (4) 쿵
	Fx.sound("Sparkle", at, 0.3 + level * 0.1, 1.4 - math.min(rank, 4) * 0.1)
	if level >= 1 then
		Fx.sound("Chime", at, 0.5, 1 + rank * 0.12)
	end
	if level >= 3 then
		Fx.sound("Fanfare", nil, 0.6, 1)
	end
	if level >= 4 then
		Fx.sound("Boom", nil, 0.5, 0.9)
		Fx.sound("LevelUp", nil, 0.5, 1.2)
	end
	-- 시각
	Fx.burst("Glow", at, 1, 1 + size * 0.3 + level * 0.5, lighten(color, 0.3))
	if level >= 3 then
		for i = 0, 5 do
			Fx.burst("Sparkle", at, 6 + level * 2, 0.9 + level * 0.15, Color3.fromHSV(i / 6, 0.6, 1))
		end
	else
		Fx.burst("Sparkle", at, 4 + level * 8, 0.6 + level * 0.2, lighten(color, 0.3))
	end
	if level >= 1 then
		ringWave(at - Vector3.new(0, size / 2 - 0.1, 0), size * 2 + level * 4, color, 0.5 + level * 0.1)
	end
	Fx.popup(head, title, color, 0.8 + level * 0.35, 1 + level * 0.3)
	if isNew then
		task.delay(0.35, function()
			local text = if gems > 0 then Loc.msg("fx.newClaim", { gems = gems }) else "NEW!" -- 젬은 도감에서 눌러 받는다
			Fx.popup(head + Vector3.new(0, 2.5, 0), text, Color3.fromRGB(150, 230, 255), 1.2, 1.6)
		end)
	end
	Fx.shake(0.04 + level * 0.1)
	if level == 2 then
		Fx.screenFlash(lighten(color, 0.4), 0.15, 0.3)
	elseif level == 3 then
		rainbowFlash(3, 0.25)
		Fx.fovPunch(4)
		if isNew then
			Fx.banner(`{label}!`, "Star", color, "NEW DISCOVERY")
		end
	elseif level >= 4 and rank < 5 then
		rainbowFlash(6, 0.4)
		Fx.fovPunch(9)
		Fx.banner(`{label}!`, "Star", color, if isNew then "NEW DISCOVERY" else "INCREDIBLE")
	elseif level >= 4 then
		-- Cosmic·Divine: 고유 색 섬광 → 무지개 → 큰 고리 두 겹, 더 긴 흔들림
		Fx.screenFlash(if rank >= 6 then Color3.fromRGB(255, 250, 220) else Color3.fromRGB(20, 10, 60), 0.6, 0.6)
		task.delay(0.25, function()
			rainbowFlash(if rank >= 6 then 10 else 8, 0.45)
		end)
		task.delay(0.15, function()
			ringWave(at - Vector3.new(0, size / 2 - 0.1, 0), size * 3 + rank * 6, lighten(color, 0.4), 0.9)
		end)
		Fx.burst("Sparkle", at, 20 + rank * 6, 1.2 + rank * 0.2, color)
		Fx.fovPunch(if rank >= 6 then 14 else 11)
		Fx.banner(`{label}!`, "Star", color, if isNew then "NEW DISCOVERY" else "LEGENDARY")
	end
end

-- 개인 기록 갱신: "NEW RECORD!" 배너 + 트로피 + 팡파레 (서버 Factory.record)
function Fx.record(text: Loc.Text)
	Hype.spent(3)
	Fx.sound("LevelUp", nil, 0.55, 1.05)
	Fx.sound("Coin", nil, 0.45, 1.3)
	Fx.screenFlash(Color3.fromRGB(255, 225, 140), 0.2, 0.35)
	Fx.shake(0.2)
	Fx.banner(text, "Trophy", Color3.fromRGB(255, 209, 61), "NEW RECORD!")
end

------------------------------------------------------------------------
-- 두근 연출 (docs/18 §5): 드문 변이는 바로 보여 주지 않고 예고 → 긴장 → 공개
------------------------------------------------------------------------

local function findBgm(): Sound?
	for _, s in SoundService:GetChildren() do
		if s:IsA("Sound") and s.SoundId == Config.BGM then
			return s
		end
	end
	return nil
end

-- 예고: 드롭 지점(드로퍼)이 떨리며 빛나고, 올라가는 소리. 0.9초 뒤 큐브가 떨어진다 (서버 OMEN_SECONDS)
function Fx.omen(at: Vector3, id: string, dropper: BasePart?)
	local color = variantColor(id)
	local center = if dropper then dropper.Position else at
	Fx.sound("Whoosh", center, 0.5, 0.6)
	for i = 0, 3 do
		task.delay(i * 0.2, function()
			Fx.sound("Chime", center, 0.3 + i * 0.08, 0.7 + i * 0.12)
			Fx.burst("Sparkle", center, 4 + i * 2, 0.6, lighten(color, 0.4))
		end)
	end
	local orb = fxPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		CFrame = CFrame.new(center),
		Color = lighten(color, 0.5),
		Material = Enum.Material.Neon,
		Transparency = 0.6,
	})
	tween(orb, 0.85, { Size = Vector3.one * 6, Transparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.9, function()
		tween(orb, 0.15, { Size = Vector3.one * 9, Transparency = 1 })
		task.delay(0.2, function()
			orb:Destroy()
		end)
	end)
	if dropper and not dropper:GetAttribute("Omen") then
		dropper:SetAttribute("Omen", true)
		local base = dropper.CFrame
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			if t >= 0.9 or not dropper.Parent then
				conn:Disconnect()
				dropper.CFrame = base
				dropper:SetAttribute("Omen", nil)
				return
			end
			local a = 0.15 + t * 0.4
			dropper.CFrame = base * CFrame.new(math.noise(t * 30, 1) * a, 0, math.noise(t * 30, 2) * a)
		end)
	end
	Fx.shake(0.15)
end

-- 공개: 1.2초 동안 화면이 어두워지고(가장자리부터) BGM이 작아지고, 차임이 올라가고,
-- 카메라가 천천히 당겨지고, 큐브에 빛기둥이 서며 흔들림이 커진다 → 섬광과 함께 공개 (이후 서버 "variant")
local REVEAL_SECONDS = 1.2

local revealing, bgmVolume = 0, 0

-- partOf: 공개할 큐브 파트를 찾는 함수 (매 프레임 부름, 없으면 at 자리에서)
function Fx.reveal(at: Vector3, tier: number, id: string, partOf: () -> BasePart?)
	revealedAt[id] = os.clock()
	Hype.spent(4)
	local color = variantColor(id)
	local size = Config.cubeSize(tier)
	-- 어둡게 + BGM 줄이기 (겹친 공개는 마지막 것이 끝날 때 원래대로)
	local bgm = findBgm()
	if revealing == 0 then
		bgmVolume = if bgm then bgm.Volume else 0
	end
	revealing += 1
	CoreFx.dim(0.25, 0.4)
	if bgm then
		tween(bgm, 0.4, { Volume = bgmVolume * 0.2 })
	end
	-- 올라가는 차임 6번 (점점 빠르게)
	local times = { 0, 0.3, 0.55, 0.75, 0.92, 1.05 }
	for i, t in times do
		task.delay(t, function()
			Fx.sound("Chime", nil, 0.35 + i * 0.06, 2 ^ (SCALE_UP[math.min(i + 1, #SCALE_UP)] / 12))
		end)
	end
	Fx.sound("Whoosh", nil, 0.4, 0.5)
	-- 빛기둥: 큐브를 따라가며 굵어지고 밝아짐
	local pillar = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, size * 0.6, size * 0.6),
		CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		Color = lighten(color, 0.4),
		Material = Enum.Material.Neon,
		Transparency = 0.85,
	})
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt: number)
		local t = os.clock() - t0
		local k = math.clamp(t / REVEAL_SECONDS, 0, 1)
		local part = partOf()
		local pos = if part and part.Parent then part.Position else at
		local w = size * (0.6 + k * 1.2)
		pillar.Size = Vector3.new(60, w, w)
		pillar.CFrame = CFrame.new(pos + Vector3.new(0, 28, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pillar.Transparency = 0.85 - k * 0.5
		pillar.Color = if id == "Rainbow" or id == "Galaxy" then Color3.fromHSV((t * 0.8) % 1, 0.5, 1) else pillar.Color
		CoreFx.setZoom(k * 10)
		CoreFx.holdShake(k * 0.35)
		if math.random() < dt * 20 then
			Fx.burst("Sparkle", pos, 2, 0.5 + k, lighten(color, 0.5))
		end
		if t >= REVEAL_SECONDS then
			conn:Disconnect()
			pillar:Destroy()
			CoreFx.setZoom(0)
			Fx.fovPunch(10)
			Fx.screenFlash(Color3.new(1, 1, 1), 0.85, 0.6)
			revealing -= 1
			if revealing == 0 then
				CoreFx.dim(1, 0.5)
				if bgm then
					tween(bgm, 1.5, { Volume = bgmVolume })
				end
			end
			Fx.burst("Glow", pos, 3, 3 + size * 0.5, lighten(color, 0.3))
			ringWave(pos - Vector3.new(0, size / 2 - 0.1, 0), 30, color, 0.7)
		end
	end)
end

-- 도감 마일스톤 / 꾸미기 해금: 화면 가운데 위 큰 글자
function Fx.codex(at: Vector3, text: Loc.Text, gems: number)
	Fx.sound("LevelUp", nil, 0.6, 1.1)
	Fx.sound("Coin", nil, 0.5, 1.2)
	Fx.burst("Sparkle", at, 30, 1.4, Color3.fromRGB(150, 230, 255))
	local sub = if gems > 0 then `{Loc.text(text)}  +{gems}◆` else text
	Fx.popup(at + Vector3.new(0, 8, 0), sub, Color3.fromRGB(150, 230, 255), 2, 2)
	Fx.shake(0.25)
end

-- 변이 큐브 연출 (서버 태그 VariantCube + Variant 속성). 클라이언트 전용이라 서버 비용 0
--   모든 변이: 테두리가 숨 쉬듯 깜빡임. 금속: 반사가 번쩍. 무지개·은하: 색 돌리기
local CollectionService = game:GetService("CollectionService")
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	for _, part in CollectionService:GetTagged("VariantCube") do
		if not part:IsA("BasePart") or (part.Position - camPos).Magnitude > 150 then
			continue
		end
		local id = part:GetAttribute("Variant")
		local style = if type(id) == "string" then Config.VARIANT_STYLE[id] else nil
		if not style then
			continue
		end
		local offset = (part.Position.X + part.Position.Z) * 0.02
		VariantDecor.animate(part, t) -- 선글라스 외 꾸미기 조각 돌리기 (shared/VariantDecor)
		local outline = part:FindFirstChild("VariantOutline") :: SelectionBox?
		if outline then
			outline.Transparency = 0.1 + 0.35 * (0.5 + 0.5 * math.sin(t * 4 + offset * 10))
		end
		if style.particle == "glint" then
			-- 빛이 훑고 지나가듯 2초마다 반사 번쩍
			local phase = (t * 0.5 + offset) % 1
			part.Reflectance = style.reflectance + 0.35 * math.max(0, 1 - math.abs(phase - 0.5) * 8)
		end
		if style.pulse then
			-- Cosmic·Divine: 테두리·껍데기·이름표가 두 색 사이를 맥동
			local a = 0.5 + 0.5 * math.sin(t * 3 + offset * 10)
			local c = style.outline:Lerp(style.pulse, a)
			if outline then
				outline.Color3 = c
				outline.Transparency = 0.05 + 0.2 * (1 - a)
			end
			local shell = part:FindFirstChild("VariantShell") :: BasePart?
			if shell then
				-- 유리 껍데기(Cosmic)는 어둡게 물들여 "사건의 지평선"처럼
				shell.Color = if style.shellMaterial then c:Lerp(Color3.new(), 0.6) else c
			end
			local tag = part:FindFirstChild("VariantTag")
			local text = tag and tag:FindFirstChildOfClass("TextLabel")
			if text then
				text.TextColor3 = style.tag:Lerp(Color3.new(1, 1, 1), a * 0.5)
			end
			local light = part:FindFirstChild("VariantLight") :: PointLight?
			if light then
				light.Brightness = (style.glow or 1.2) * (0.75 + 0.5 * a)
			end
		end
		if style.particle == "vortex" then
			-- 별무리 두 줄기가 큐브 둘레를 기울어진 궤도로 돎 (파티클이 남아 소용돌이 꼬리가 됨)
			-- 몸통 별 무늬도 천천히 흐름
			local r = part.Size.X * 0.85
			for _, child in part:GetChildren() do
				if child.Name == "VariantOrbit" and child:IsA("Attachment") then
					local ang = t * 2.4 + ((child:GetAttribute("Phase") :: number?) or 0)
					child.Position = Vector3.new(math.cos(ang) * r, math.sin(ang * 2) * r * 0.25, math.sin(ang) * r)
				elseif child.Name == "VariantStars" and child:IsA("Texture") then
					child.OffsetStudsU = t * 0.15
					child.OffsetStudsV = t * 0.06
				end
			end
		elseif style.particle == "halo" then
			-- 머리 위 고리가 둥실거리며 천천히 돎
			local halo = part:FindFirstChild("VariantHalo")
			local weld = halo and halo:FindFirstChildOfClass("Weld")
			if weld then
				local lift = (weld:GetAttribute("Lift") :: number?) or 2
				weld.C0 = CFrame.new(0, lift + math.sin(t * 2 + offset * 10) * 0.15, 0) * CFrame.Angles(0, t * 0.8, 0)
			end
		end
		if not style.cycle then
			continue
		end
		local hue = (t * 0.25 + offset) % 1
		local c = Color3.fromHSV(hue, 0.6, 1)
		if style.color then
			c = c:Lerp(style.color, style.blend)
		end
		part.Color = c
		if outline then
			outline.Color3 = Color3.fromHSV((hue + 0.25) % 1, 0.7, 1)
		end
		local shell = part:FindFirstChild("VariantShell") :: BasePart?
		if shell then
			shell.Color = Color3.fromHSV((hue + 0.5) % 1, 0.7, 1)
		end
		local tag = part:FindFirstChild("VariantTag")
		local text = tag and tag:FindFirstChildOfClass("TextLabel")
		if text then
			text.TextColor3 = Color3.fromHSV(hue, 0.45, 1)
		end
	end
end)

-- 마일스톤: 큰 글자 + 팡파레 + 섬광
function Fx.milestone(at: Vector3, text: Loc.Text)
	Fx.sound("Fanfare", nil, 0.6, 1)
	Fx.sound("LevelUp", nil, 0.4, 1.2)
	Fx.screenFlash(Color3.fromRGB(255, 240, 180), 0.35, 0.5)
	Fx.burst("Chunk", at, 30, 1.2, Color3.fromRGB(255, 209, 61))
	Fx.burst("Sparkle", at, 30, 1.5)
	Fx.popup(at + Vector3.new(0, 6, 0), text, Color3.fromRGB(255, 209, 61), 2.2, 2.2)
	Fx.shake(0.4)
	Fx.fovPunch(4)
end

return Fx
