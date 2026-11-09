--!strict
-- Hit feel (docs/33 §11-5): layered impact sound, sparks, hit-stop, shake, damage numbers, hit flash,
-- knockback, swing trail, camera punch. Opt-in core client module (Merge does not use it).
--   HitFx.impact(enemyModel, { damage = 120, crit = true, knockbackDir = look })   -- one call per hit
--   HitFx.impact(rockPart.Position, { heavy = true, color = Color3.fromRGB(180, 140, 90) })   -- smash, no number
--   HitFx.number(pos, 45, false)            -- damage number alone ("+12" collect numbers: HitFx.number(pos, "+12"))
--   HitFx.flash(model)                       -- white hit flash (Highlight)
--   HitFx.swingTrail(tool); HitFx.swing(tool)   -- trail on the handle; swing = whoosh + trail for 0.25 s
--   HitFx.bindTool(tool)                     -- swing on every Tool.Activated
--   HitFx.settings({ shake = false, hitstop = false, numbers = true, flash = true })  -- player settings toggle
-- Default sounds are Creator Store ids (Fx keys HitLight, HitHeavy, HitCrack, HitCrit, Swing). A game that already
-- registered one of these keys in Fx.configure keeps its own. Everything respects Fx.setLimits and Quality
-- (fewer particles / numbers on low, no hit-stop on low).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Fx = require(script.Parent.Fx)
local Quality = require(script.Parent.Quality)
local Format = require(script.Parent.Parent.Core.Format)

local player = Players.LocalPlayer
local HitFx = {}

-- Creator Store audio (free, public). Verified to load in Studio 2026-10-31 (docs/33 §11-5).
HitFx.SOUNDS = {
	HitLight = "rbxassetid://132504023010884", -- "Punch Impact 1" (NickySergal): short body punch
	HitHeavy = "rbxassetid://9118616114", -- "Rock Impact Dirt Hard Muted Thuds 1" (ProSoundEffects): low thud layer
	HitCrack = "rbxassetid://9125672726", -- "Metal Impact Sledge Hammer Hits" (ProSoundEffects): bright crack layer
	HitCrit = "rbxassetid://9119072660", -- "Shield Clang As Hit Metal Sword Hubcap 1" (ProSoundEffects): crit ring
	Swing = "rbxassetid://9120972444", -- "Wood Whoosh Slicing Air Quick Swings 1" (ProSoundEffects)
}
HitFx.SOUND_MAX =
	{ HitLight = 0.5, HitHeavy = 0.7, HitCrack = 0.6, HitCrit = 0.9, Swing = 0.45 } :: { [string]: number }

local registered = false
local function ensureSounds()
	if registered then
		return
	end
	registered = true
	for key: string, id: string in HitFx.SOUNDS :: { [string]: string } do
		if not Fx.hasSound(key) then
			Fx.registerSound(key, id, HitFx.SOUND_MAX[key])
		end
	end
end

local opts = { shake = true, hitstop = true, numbers = true, flash = true }
function HitFx.settings(s: { shake: boolean?, hitstop: boolean?, numbers: boolean?, flash: boolean? })
	for k, v in s do
		if (opts :: any)[k] ~= nil and type(v) == "boolean" then
			(opts :: any)[k] = v
		end
	end
end

local function tw(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tween =
		TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

local function hitColors()
	local h = Ui.tokens().ux.hit
	return h.color, h.crit, h.flash, h.trail
end

local function posOf(target: any): Vector3?
	if typeof(target) == "Vector3" then
		return target
	elseif typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			return target.Position
		elseif target:IsA("Attachment") then
			return target.WorldPosition
		elseif target:IsA("Model") then
			local hrp = target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				return hrp.Position
			end
			return target:GetPivot().Position
		end
	end
	return nil
end

local function modelOf(target: any): Model?
	if typeof(target) == "Instance" then
		if target:IsA("Model") then
			return target
		end
		return target:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

------------------------------------------------------------------------
-- Damage numbers
------------------------------------------------------------------------

local MAX_NUMBERS = { 5, 9, 16 } -- per Quality tier
local liveNumbers = 0

-- Floating number. value: number (Format.short) or text ("+12", "MISS"). crit = bigger, crit color, "!"
function HitFx.number(at: Vector3, value: any, crit: boolean?, color: Color3?)
	if not opts.numbers or liveNumbers >= MAX_NUMBERS[Quality.tier()] then
		return
	end
	liveNumbers += 1
	local base, critColor = hitColors()
	local text = if type(value) == "number" then Format.short(math.floor(value + 0.5)) else tostring(value)
	if crit then
		text ..= "!"
	end
	local holder = Instance.new("Part")
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one
	local jitter = Vector3.new((math.random() - 0.5) * 2.4, 1.5 + math.random() * 0.8, (math.random() - 0.5) * 2.4)
	holder.CFrame = CFrame.new(at + jitter)
	holder.Parent = Fx.folder
	local scale = if crit then 1.45 else 1
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(150 * scale, 54 * scale)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 160
	bb.Parent = holder
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	Ui.font(l, "number")
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color or (if crit then critColor else base)
	l.TextStrokeColor3 = Color3.fromRGB(25, 18, 30)
	l.TextStrokeTransparency = 0
	l.Rotation = if crit then (math.random() - 0.5) * 16 else 0
	l.Parent = bb
	local s = Instance.new("UIScale")
	s.Scale = if crit then 2.2 else 1.6
	s.Parent = l
	tw(s, if crit then 0.25 else 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
	local life = if crit then 1.0 else 0.75
	tw(holder, life, { CFrame = holder.CFrame + Vector3.new(0, 2.6, 0) })
	task.delay(life * 0.55, function()
		tw(l, life * 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(life + 0.05, function()
		holder:Destroy()
		liveNumbers -= 1
	end)
end

------------------------------------------------------------------------
-- Hit flash
------------------------------------------------------------------------

local MAX_FLASH = 6
local flashing: { [Instance]: Highlight } = {}
local flashCount = 0

function HitFx.flash(model: Instance, color: Color3?, dur: number?)
	if not opts.flash then
		return
	end
	local _, _, flashColor = hitColors()
	local h = flashing[model]
	if not h then
		if flashCount >= MAX_FLASH then
			return
		end
		flashCount += 1
		local nh = Instance.new("Highlight")
		nh.Name = "CoreHitFlash"
		nh.DepthMode = Enum.HighlightDepthMode.Occluded
		nh.OutlineTransparency = 1
		nh.Adornee = model
		nh.Parent = model
		flashing[model] = nh
		h = nh
	end
	local hl = h :: Highlight
	hl.FillColor = color or flashColor
	hl.FillTransparency = 0.15
	local t = dur or 0.16
	tw(hl, t, { FillTransparency = 1 })
	local my = (hl:GetAttribute("Token") :: number?) or 0
	hl:SetAttribute("Token", my + 1)
	task.delay(t + 0.05, function()
		if hl:GetAttribute("Token") == my + 1 then
			flashing[model] = nil
			flashCount -= 1
			hl:Destroy()
		end
	end)
end

------------------------------------------------------------------------
-- Hit-stop: freeze animations of the attacker (local character) and the target for a few frames
------------------------------------------------------------------------

local function freeze(model: Model?, dur: number)
	local hum = model and model:FindFirstChildWhichIsA("Humanoid")
	local anim = hum and hum:FindFirstChildWhichIsA("Animator")
	if not anim then
		local ac = model and model:FindFirstChildWhichIsA("AnimationController")
		anim = ac and ac:FindFirstChildWhichIsA("Animator")
	end
	if not anim then
		return
	end
	local tracks = (anim :: Animator):GetPlayingAnimationTracks()
	local speeds = {}
	for i, tr in tracks do
		speeds[i] = tr.Speed
		tr:AdjustSpeed(0)
	end
	task.delay(dur, function()
		for i, tr in tracks do
			if tr.IsPlaying then
				tr:AdjustSpeed(speeds[i])
			end
		end
	end)
end

function HitFx.hitstop(dur: number, target: Model?)
	if not opts.hitstop or Quality.tier() <= 1 or dur <= 0 then
		return
	end
	freeze(player.Character, dur)
	if target and target ~= player.Character then
		freeze(target, dur)
	end
end

------------------------------------------------------------------------
-- Impact
------------------------------------------------------------------------

export type ImpactOpts = {
	damage: number?, -- shows a damage number (opts.numbers)
	crit: boolean?, -- bigger everything + crit sound/color
	heavy: boolean?, -- layered heavy sound, ring, camera punch (default: crit or damage >= heavyAt)
	heavyAt: number?, -- damage that counts as heavy (default math.huge = only crit/heavy flag)
	color: Color3?, -- sparks + number color
	sound: (string | boolean)?, -- Fx sound key to use instead of the default layers; false = silent
	volume: number?,
	shake: number?, -- camera shake amount (default 0.12 light / 0.35 heavy; 0 = none)
	hitstop: number?, -- seconds (default 0.045 light / 0.08 heavy; 0 = none)
	knockbackDir: Vector3?, -- push direction (client-owned assemblies only; NPCs: impulse on the server)
	knockback: number?, -- studs/s (default 28)
	flash: boolean?, -- default true when the target is a Model/part
	sparks: number?, -- particle count (default 10 light / 22 heavy)
	punch: number?, -- FOV punch degrees on heavy hits (default 3)
}

function HitFx.impact(target: any, o: ImpactOpts?)
	ensureSounds()
	local op: ImpactOpts = o or {}
	local at = posOf(target)
	if not at then
		return
	end
	local model = modelOf(target)
	local crit = op.crit == true
	local heavy = op.heavy == true or crit or (op.damage ~= nil and op.damage >= (op.heavyAt or math.huge))
	local base, critColor = hitColors()
	local color = op.color or (if crit then critColor else base)
	local near = Fx.nearCamera(at, 140)
	-- sound layers
	if op.sound ~= false then
		local vol = op.volume or 0.6
		local pitch = 0.92 + math.random() * 0.16
		if type(op.sound) == "string" then
			Fx.sound(op.sound, at, vol, pitch, 0.03)
		else
			Fx.sound("HitLight", at, vol, pitch, 0.03)
			if heavy then
				Fx.sound("HitHeavy", at, vol * 0.9, pitch * 0.95, 0.05)
				Fx.sound("HitCrack", at, vol * 0.45, pitch * 1.1, 0.05)
			end
			if crit then
				Fx.sound("HitCrit", at, vol * 0.55, 1.1 + math.random() * 0.1, 0.08)
			end
		end
	end
	if not near then
		return
	end
	-- sparks
	local n = op.sparks or (if heavy then 22 else 10)
	Fx.burst("Sparkle", at, n, if heavy then 1.3 else 0.9, color)
	if heavy then
		Fx.ring(at, if crit then 7 else 5, color, 0.35)
	end
	-- number
	if op.damage then
		HitFx.number(at, op.damage, crit, op.color)
	end
	-- flash
	if op.flash ~= false and model and model ~= player.Character then
		HitFx.flash(model)
	end
	-- shake / punch (Fx applies setLimits)
	if opts.shake then
		local amt = op.shake or (if heavy then 0.35 else 0.12)
		if amt > 0 then
			Fx.shake(amt)
		end
		if heavy then
			Fx.fovPunch(op.punch or 3)
		end
	end
	-- hit-stop
	local hs = op.hitstop or (if heavy then 0.08 else 0.045)
	HitFx.hitstop(hs, model)
	-- knockback (works where this client owns the physics: own character, local props)
	if op.knockbackDir and op.knockbackDir.Magnitude > 1e-3 then
		local part: BasePart? = nil
		if typeof(target) == "Instance" and target:IsA("BasePart") then
			part = target
		elseif model then
			part = (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart?
		end
		if part and not part.Anchored then
			local dir = op.knockbackDir.Unit
			local speed = op.knockback or 28
			part.AssemblyLinearVelocity += (dir + Vector3.new(0, 0.35, 0)).Unit * speed
		end
	end
end

------------------------------------------------------------------------
-- Swing trail
------------------------------------------------------------------------

local function handleOf(t: Instance): BasePart?
	if t:IsA("BasePart") then
		return t
	end
	local h = t:FindFirstChild("Handle")
	if h and h:IsA("BasePart") then
		return h
	end
	return t:FindFirstChildWhichIsA("BasePart", true)
end

-- Trail along the longest axis of the handle (disabled until HitFx.swing). Returns the Trail.
function HitFx.swingTrail(tool: Instance, o: { color: Color3?, lifetime: number?, width: number? }?): Trail?
	local part = handleOf(tool)
	if not part then
		return nil
	end
	local existing = part:FindFirstChild("CoreSwingTrail")
	if existing and existing:IsA("Trail") then
		return existing
	end
	local s = part.Size
	local axis = if s.X >= s.Y and s.X >= s.Z
		then Vector3.xAxis * s.X
		elseif s.Y >= s.Z then Vector3.yAxis * s.Y
		else Vector3.zAxis * s.Z
	local a0 = Instance.new("Attachment")
	a0.Name = "CoreTrail0"
	a0.Position = axis * 0.5
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "CoreTrail1"
	a1.Position = -axis * 0.1
	a1.Parent = part
	local _, _, _, trailColor = hitColors()
	local c = (o and o.color) or trailColor
	local tr = Instance.new("Trail")
	tr.Name = "CoreSwingTrail"
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Color = if c then ColorSequence.new(c) else ColorSequence.new(Color3.new(1, 1, 1), Ui.THEME.accent)
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	tr.Lifetime = (o and o.lifetime) or (if Quality.tier() <= 1 then 0.1 else 0.18)
	tr.LightEmission = 0.7
	tr.LightInfluence = 0
	tr.FaceCamera = false
	tr.MinLength = 0.05
	tr.Enabled = false
	tr.Parent = part
	return tr
end

-- Swing moment: whoosh + trail on for `dur` seconds
function HitFx.swing(tool: Instance, dur: number?)
	ensureSounds()
	local tr = HitFx.swingTrail(tool)
	local part = handleOf(tool)
	Fx.sound("Swing", part and part.Position, 0.5, 0.9 + math.random() * 0.25, 0.08)
	if tr then
		tr.Enabled = true
		local my = ((tr:GetAttribute("Swing") :: number?) or 0) + 1
		tr:SetAttribute("Swing", my)
		task.delay(dur or 0.25, function()
			if tr:GetAttribute("Swing") == my then
				tr.Enabled = false
			end
		end)
	end
end

-- Whoosh + trail every time the tool is used
function HitFx.bindTool(tool: Tool): RBXScriptConnection
	HitFx.swingTrail(tool)
	return tool.Activated:Connect(function()
		HitFx.swing(tool)
	end)
end

return HitFx
