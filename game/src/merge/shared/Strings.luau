--!strict
-- 번역 키 표 (docs/31 §2): 숫자·이름이 바뀌는 문장의 영어 원문. 매개변수는 {이름}.
-- 클라이언트 client/Loc가 Translator:FormatByKey(키)로 번역하고, 표에 없으면 여기 원문을 쓴다.
-- 서버는 글자 대신 Strings.msg(키, 매개변수)를 보낸다 (알림·보상 글자).
-- 클라우드 현지화 표에 올리기: game 디렉터리에서 `lune run tools/loc_csv.luau` → build/loc_keys.csv (Creator Hub 업로드)
-- 고정 문장은 여기 넣지 않는다 (자동 캡처가 잡음). SOURCES는 Loc.source로 매개변수 안에 넣는 이름·설명.

local Strings = {}

export type Msg = { key: string, args: { [string]: any }? }

Strings.KEYS = {
	-- 오른쪽 위 반짝 특가 (client/BoostButton)
	["boost.frenzyLeft"] = "FRENZY {time}",
	["boost.newDeals"] = "NEW DEALS IN {time}",
	["boost.moreLeft"] = "+{mins} MIN · {left}/{max} LEFT",
	["boost.offer"] = "x{mult} FOR {mins} MIN",
	["boost.priceLeft"] = "R$ {price} · {left}/{max} LEFT",

	-- 도감 (client/Collection)
	["codex.tab"] = "{variant} {n}/{max}",
	["codex.page"] = "TIER {first}-{last}   ({page}/{pages})",
	["codex.toClaim"] = "◆ {n} TO CLAIM",
	["codex.tapClaim"] = "TAP: +{gems}◆",
	["codex.petsFound"] = "PETS FOUND {n} / {total}",
	["codex.found"] = "FOUND {n} / {total}   ◆ {gems}",
	["codex.milestoneReady"] = "TAP TO CLAIM +{gems}◆  ({n} found)",
	["codex.milestoneNext"] = "Next: {n} found → +{gems}◆",
	["codex.locked"] = "LOCKED {n}/{need}",
	["codex.needGems"] = "Need {need}◆ (you have {have})",
	["codex.milestoneFx"] = "MILESTONE! CLAIM +{gems}◆ IN COLLECTION",

	-- 큐브 목록 (client/CubeInventory)
	["inv.widget"] = "MY CUBES {n}/{cap}",
	["inv.panel"] = "CUBE INVENTORY  {n}/{cap}",

	-- 일일 선물·퀘스트 (client/DailyUi, server/Daily)
	["daily.questDone"] = "Quest done! {text}",
	["daily.resetIn"] = "new gifts & quests in {time}",
	["daily.title"] = "DAILY GIFTS   played today {time}",
	["daily.openSmall"] = "OPEN x{n}",
	["daily.bigReady"] = "OPEN!\n{mins} min",
	["daily.bigWait"] = "{mins} min\n{time}",
	["daily.claimQuest"] = "CLAIM +{gems}◆",
	["daily.hudNext"] = "DAILY  next gift {time}",
	["daily.hudQuests"] = "DAILY QUESTS {n}/{total}",
	["daily.allDone"] = "ALL DONE! +{gems}◆",
	["daily.questReward"] = "+{gems}◆  +${cash}",
	["reward.cash"] = "+${cash}",
	["reward.steal"] = "+{n} STEAL",
	["reward.gems"] = "+{n}◆",

	-- 7일 출석 (server/Daily)
	["login.cash"] = "DAY {day}: +${cash}",
	["login.shards"] = "DAY {day}: +{n} SHARDS",
	["login.gems"] = "DAY {day}: +{n}◆",
	["login.steals"] = "DAY {day}: +{n} STEALS",
	["login.day7"] = "DAY 7: +{n} BOSS COINS +{gems}◆",

	-- 광장 선물 상자 (server/Boxes)
	["gift.box"] = "GIFT! +${cash}  +{shards} SHARDS",

	-- 이벤트 (client/EventsUi, server/Events)
	["events.feverOn"] = "FEVER x{mult} + 2x DROPS  {time}",
	["events.feverGauge"] = "FEVER {n}/{goal}",
	["events.frenzy"] = "FRENZY x{mult} {time}",
	["events.storm"] = "STORM x3 {time}",
	["events.golden"] = "GOLDEN CUBE! {hint} {n}",
	["announce.tier"] = "{name} reached TIER {tier}!",
	["announce.jackpot"] = "{name} hit the GOLDEN JACKPOT! TIER {tier}",

	-- 목표 바 (client/GoalBar)
	["goal.makeTier"] = "NEXT GOAL: MAKE T{tier}",
	["goal.tierBar"] = "T{tier} / T{max} this rebirth",
	["goal.perk"] = "x{mult} income",
	["goal.rebirthReady"] = "REBIRTH READY! TAP → {perk}",
	["goal.rebirthNext"] = "NEXT: REBIRTH → {perk}",
	["goal.found"] = "{n} / {total} found",

	-- HUD·코어 (client/init)
	["hud.gems"] = "{gem}{gems}   COLLECTION {n}/{total}",
	["hud.friends"] = "FRIENDS +{n}",
	["hud.online"] = "ONLINE +{pct}%",
	["hud.tray"] = "tray {n}/{cap}",
	["hud.trayFull"] = "tray {n}/{cap} FULL",
	["toast.online"] = "ONLINE BONUS +{pct}% income!",
	["toast.onlineNext"] = "ONLINE BONUS +{pct}% income! Stay {mins} min more for +{next}%",
	["banner.tierMax"] = "T{tier} IS MAX!",
	["banner.rebirthUpTo"] = "REBIRTH to merge up to T{tier}",
	["cores.queued"] = "Queued cores: {n}",
	["cores.empty"] = "Incubator {i}: empty",
	["cores.hatching"] = "{core} core  +${cash}",
	["cores.claim"] = "CLAIM {core}  +${cash}",
	["cores.timer"] = "hatching {time}",
	["cores.found"] = "{core} core found! Hatch it in CORES",

	-- 연출 글자 (client/Fx)
	["fx.hatched"] = "{core} HATCHED! {cash}",
	["fx.coreFound"] = "{core} CORE!",
	["fx.statUp"] = "{title} UP!",
	["fx.whack"] = "WHACK x{n}!",
	["fx.newClaim"] = "NEW! CLAIM +{gems}◆",
	["fx.faster"] = "FASTER {s}s",
	["fx.tierUp"] = "TIER {tier}!",

	-- 개인 기록·서버 알림 (server/Factory)
	["record.rarest"] = "RAREST EVER: {variant}!",
	["record.income"] = "INCOME ${cash}/s!",
	["toast.foundVariant"] = "{name} found a {variant} tier {tier} cube!",
	["toast.rebirth"] = "REBIRTH {n}! Income x{mult}, merge up to T{tier}",
	["toast.rush"] = "REBIRTH RUSH! Income x{mult} until T{tier} · droppers start at T{start}",

	-- 펫 (client/PetsUi)
	["pets.hud"] = "PETS  +{pct}   {shard}{n}",
	["pets.fused"] = "{pet} {stars}! +{pct}",
	["pets.released"] = "Released · +{shard}{n}",
	["pets.needShards"] = "Need {shard}{n} — merge more cubes!",
	["pets.detail"] = "{pet} {stars}  ·  {rarity}  ·  +{pct} income",
	["pets.rarityBonus"] = "{rarity}  +{pct}",
	["pets.canHatch"] = "You can hatch a {egg}! Go to the PET EGGS pad (green beam)",
	["pets.release"] = "RELEASE +{shard}{n}",

	-- 보스 레이드 (client/RaidUi)
	["raid.getReady"] = "GET READY!  FIGHT STARTS IN {s}s  ·  {n} JOINED",
	["raid.hp"] = "{boss}  {hp}/{max} HITS",
	["raid.hits"] = "{time}   YOUR HITS {n}",
	["raid.coinsOut"] = "+{n} BOSS COIN (helped before you were out)",
	["raid.coins"] = "+{n} BOSS COINS",
	["raid.noReward"] = "Nobody beat the boss - no reward",
	["raid.minHits"] = "Hit the boss {n}+ times to earn coins",
	["raid.result"] = "{n} hits.  {coins}",
	["raid.buff"] = "x{mult} income for {mins} min!",
	["raid.spend"] = "Spend coins at the BOSS SHOP (purple beam in the plaza)",
	["raid.startsIn"] = "Starts in {s}s  ·  {n} joined",
	["raid.chip"] = "RAID x{mult} {time}",

	-- 상점 (client/ShopUi)
	["shop.cashDesc"] = "+${cash} ({desc})",

	-- 훔치기 (client/Steal, server/Steal)
	["steal.nextIn"] = "Next steal in {time}",
	["steal.stolenSub"] = "{name} took your T{tier}! Whack them with your bat!",
	["steal.thiefDist"] = "THIEF! {m}m",
	["steal.caughtMine"] = "You bonked {name} and got your T{tier} back!",
	["steal.caughtOther"] = "You bonked {name}! The T{tier} cube went home",
	["steal.caughtFor"] = "{name} bonked the thief. Your T{tier} is back!",
	["steal.shieldSub"] = "Robbed twice in a row: no one can steal from you for {mins} min",
	["steal.home"] = "HOME ▼ {s}s",
	["steal.doneSub"] = "The T{tier} cube is yours now",
	["steal.button"] = "STEAL x{n}",
	["steal.getPack"] = "GET +{n}",
	["steal.plusOneIn"] = "+1 in {time}",
	["steal.slow"] = "-{pct}% SPEED",
	["steal.shield"] = "SHIELD {time}",
	["steal.shieldMine"] = "YOUR SHIELD {time}",
	["steal.back"] = "Your T{tier} cube is back!",
	["steal.gotAway"] = "{name} got away with your T{tier} cube",

	-- 강화 (client/Upgrades)
	["upg.lv"] = "{title}  Lv{lv}",
	["upg.lvMax"] = "{title}  Lv{lv}/{max}",
	["upg.batLocked"] = "Codex {n}/{need} to unlock Lv{lv}",
	["upg.bossNote"] = "BOSS COINS: {n}  ·  Win BOSS RAIDS to earn more",
	["upg.dropperSpeed"] = "DROPPER {i} SPEED  Lv{lv}/{max}",
	["upg.dropperTier"] = "DROPPER {i} TIER",
	["upg.bigDropAt"] = "Lv{lv}: BIG DROP +15%",
	["upg.tierCap"] = "max T{tier} (rebirth raises)",
	["upg.newDropper"] = "NEW DROPPER  {n}/{max}",
	["upg.milestone"] = "Lv{lv}: {label}",
	["upg.incubators"] = "INCUBATORS  {n}/{max}",
	["upg.rebirth"] = "REBIRTH  {n}/{max}",
	["upg.cardSpeed"] = "SPEED {next}",
	["upg.cardTier"] = "TIER {next}",
	["upg.cardBigDrop"] = "Lv{lv} → Lv{ms}: BIG DROP +15%",
	-- 강화 효과 줄 (지금 → 다음)
	["upg.fxPolish"] = "income x{m}",
	["upg.fxLucky"] = "{pct}% skip a tier",
	["upg.fxHatch"] = "timers x{m}",
	["upg.fxTray"] = "{n} cubes (keeps on rebirth)",
	["upg.fxRange"] = "{n} studs",
	["upg.fxPower"] = "force {n}",
	["upg.fxSwing"] = "{s}s per swing",
	["upg.fxWalk"] = "walk {n}",
	["upg.fxBoss"] = "{pct} {what}",
	["upg.fxSlots"] = "{n} slots",
	["upg.fxMergeTo"] = "{mult}, merge to T{tier}",
	["upg.finds"] = "{n} FINDS",
	["events.waveStorm"] = "DROP STORM x{n}!",
	["golden.frenzy"] = "FRENZY x{mult}!",
	["golden.rain"] = "TIER RAIN x{n}!",
	-- 목표 바 아래 할 일 힌트 (client/GoalBar)
	["hint.arrow"] = "▶ {text}",
	["hint.reward"] = "CLAIM 1 COLLECTION REWARD",
	["hint.rewards"] = "CLAIM {n} COLLECTION REWARDS",
	["hint.quickGift"] = "QUICK GIFT x{n} READY",
	["hint.core"] = "1 CORE READY TO CLAIM",
	["hint.cores"] = "{n} CORES READY TO CLAIM",
	["hint.upgrade"] = "1 UPGRADE AVAILABLE",
	["hint.upgrades"] = "{n} UPGRADES AVAILABLE",
	["hint.steal"] = "STEAL READY x{n}: grab cubes from other factories{key}",
	-- 메뉴 열 때 오프라인 수입 안내 (client/LeaveNote)
	["leave.cash"] = "It earns up to ${cash} while you're away ({hours}h). Come back to collect!",
	["leave.noCash"] = "It keeps earning while you're away (up to {hours}h). Come back to collect!",
	-- 기타 연출·안내
	["fx.combo"] = "x{n} COMBO!",
	["fx.newTier"] = "NEW TIER {tier}: {label}!",
	["fx.lucky"] = "LUCKY! +{n}",
	["codex.discoverToUnlock"] = "Discover {n} special cubes to unlock",
	["inv.more"] = "+{n} MORE · TAP FOR ALL",
	["pets.fuseNeed"] = "Need {n} of the same pet & stars",
	["steal.pickHere"] = "▼ STEAL T{tier}! ▼",
	["steal.getCloser"] = "T{tier}: GET CLOSER",
	["steal.pickRow"] = "T{tier}  {variant} x{mult}",
	["upg.maxTier"] = "(max T{tier})",
	["events.waveFrenzy"] = "INCOME x{mult}!",
	["events.waveFever"] = "FEVER! INCOME x{mult}",
	["upg.needTier"] = "Make a T{tier} cube first to rebirth",
}

-- 이 이름의 매개변수는 고정 이름(변이·펫·등급·보스·코어·강화 이름 등)이라 클라이언트가 원문 기준으로 번역해 넣는다 (Loc.source).
-- 플레이어 이름은 {name}으로 두고 번역하지 않는다
Strings.NAME_ARGS = {
	variant = true,
	pet = true,
	rarity = true,
	egg = true,
	boss = true,
	core = true,
	title = true,
	label = true,
	what = true,
	desc = true,
} :: { [string]: boolean }

-- 매개변수로 들어가는 고정 이름·설명 중 다른 모듈 표에 없는 것 (tools/loc_csv가 변이·펫·보스·코어·등급 이름은 따로 모은다)
Strings.SOURCES = {
	-- 강화 이름 (client/Upgrades INFO·BAT_INFO, shared/Raid UPGRADES)
	"POLISH",
	"LUCKY MERGE",
	"HATCH SPEED",
	"BIGGER TRAY",
	"BAT RANGE",
	"BAT POWER",
	"SWING SPEED",
	"MOVE SPEED",
	"RAIDER INCOME",
	"RAIDER SPEED",
	"RAIDER GUARD",
	"RAIDER INCOME+",
	"INCOME x2",
	-- 강화 효과 설명 (client/Upgrades BOSS_ROW.what), 고정 행 설명
	"income",
	"move speed",
	"knockback & stun resist",
	"Cheapest first",
	"Your factory keeps working!",
	-- 현금 상품 설명 (shared/Shop, CASH_MINUTES)
	"Half of your next rebirth",
	"2x your next rebirth",
	"6x your next rebirth",
}

local function fill(template: string, args: { [string]: any }?): string
	return (
		string.gsub(template, "{(%w+)}", function(name: string): string
			local v = args and args[name]
			if v == nil then
				return `\{{name}\}` -- 그대로 둔다
			end
			if type(v) == "table" and type(v.key) == "string" then
				return Strings.format(v.key, v.args)
			end
			return tostring(v)
		end)
	)
end

-- 영어 원문으로 채우기 (번역기가 없거나 표에 키가 없을 때)
function Strings.format(key: string, args: { [string]: any }?): string
	local template = Strings.KEYS[key]
	if not template then
		return key
	end
	return fill(template, args)
end

function Strings.msg(key: string, args: { [string]: any }?): Msg
	return { key = key, args = args }
end

return Strings
