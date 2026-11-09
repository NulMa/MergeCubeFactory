--!strict
-- Theme tokens (docs/33 §Theme). Pure module (Lune-tested: tests/core/Theme.spec.luau).
-- Client Ui.theme(tokens) merges a game's partial tokens over Theme.defaults() and every core UI piece reads the result.
-- Defaults = the look before themes existed (Merge Cube Factory, live). Changing a default changes Merge: don't.
--
-- Groups: fonts, palette, shape, motion, sounds, text, ux (§11 UX modules). A game passes only what it changes:
--   Ui.theme({ fonts = { title = "Bangers" }, palette = { accent = Color3.fromRGB(255, 120, 40) },
--              shape = { buttonStyle = "pill", panelStyle = "glass" }, sounds = { click = 1234567 } })

local Theme = {}

export type Tokens = { [string]: any }

local GROUPS = { fonts = true, palette = true, shape = true, motion = true, sounds = true, text = true, ux = true }

-- Old Ui.THEME names -> palette names. Both are filled in Ui.THEME so old code (THEME.ink) keeps working.
Theme.ALIASES = { ink = "text", dim = "textDim", card = "panelAlt", outline = "stroke" }

-- Allowed widget variants (Ui.button Style / Ui.make PanelStyle / Ui.title Style)
Theme.BUTTON_STYLES = { gradient = true, solid = true, outlined = true, pill = true, image = true }
Theme.PANEL_STYLES = { classic = true, card = true, glass = true, image = true, neon = true }
Theme.TITLE_STYLES = { plain = true, ribbon = true, tab = true }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

function Theme.defaults(): Tokens
	return {
		-- Font per role: Enum.Font, Font (Font.new/fromName/fromId), a name ("Bangers"), an rbxasset family path,
		-- a Creator Store font asset id (number), or { family = <any of those>, weight = "Bold" | Enum.FontWeight, style = "Italic" }
		fonts = {
			title = Enum.Font.FredokaOne, -- Ui.label default role, panel titles, Fx/Reveal banners
			body = Enum.Font.GothamMedium, -- descriptions, list text
			caption = Enum.Font.GothamBold, -- small bold sub lines (banner sub, countdown state)
			number = Enum.Font.FredokaOne, -- prices, scores, timers
			button = Enum.Font.FredokaOne,
		},
		palette = {
			bg = rgb(24, 22, 38), -- screen backdrops (not used by default panels)
			panel = rgb(37, 35, 59),
			panelAlt = rgb(52, 49, 80), -- legacy THEME.card
			button = rgb(66, 63, 99),
			stroke = rgb(30, 24, 40), -- legacy THEME.outline: button/text outlines
			text = rgb(236, 235, 246), -- legacy THEME.ink
			textDim = rgb(132, 128, 166), -- legacy THEME.dim
			accent = rgb(255, 209, 61),
			accentInk = rgb(36, 26, 8), -- text on accent
			accent2 = rgb(150, 90, 255), -- second accent (shop FOREVER ribbon)
			good = rgb(120, 220, 140),
			bad = rgb(240, 90, 110),
			lucky = rgb(130, 255, 150),
			buy = rgb(90, 220, 110), -- shop buy button
			buyText = rgb(255, 255, 255),
			desc = rgb(225, 220, 245), -- shop item description
			sub = rgb(255, 240, 200), -- banner sub line
			mine = rgb(70, 66, 30), -- leaderboard: my row
			medals = { rgb(255, 209, 61), rgb(205, 210, 225), rgb(222, 150, 90) },
			rarity = nil :: { [string]: Color3 }?, -- optional: game rarity colors (Ui.THEME.rarity)
		},
		shape = {
			corner = 10, -- Ui.corner() default radius (px)
			cornerScale = 1, -- multiplies every Ui.corner(r) (0 = square)
			stroke = { panel = 4, card = 2, button = 3 }, -- UIStroke thickness
			padding = { x = 0.06, y = 0.12 }, -- button UIPadding (scale)
			shadow = false, -- true or { color, transparency, offset }: hard drop shadow under panels/buttons
			buttonStyle = "gradient", -- gradient | solid | outlined | pill | image
			panelStyle = "classic", -- frames colored palette.panel: classic | card | glass | image | neon
			cardStyle = "classic", -- frames colored palette.panelAlt
			titleStyle = "plain", -- Ui.title: plain | ribbon | tab
			-- 9-slice images: { image = id, slice = Rect.new(l, t, r, b), scale = 1, tint = true }
			images = { panel = nil :: any, card = nil :: any, button = nil :: any },
			gradients = {
				-- { colors = Color3 | {Color3, Color3} | ColorSequence, rotation = deg, transparency = NumberSequence? }
				button = { colors = { rgb(255, 255, 255), rgb(165, 160, 185) }, rotation = 90 },
				card = { colors = { rgb(255, 255, 255), rgb(165, 160, 185) }, rotation = 90 },
				panel = { colors = { rgb(255, 255, 255), rgb(150, 140, 190) }, rotation = 90 },
				-- panel edge (classic): spinning rainbow on a white stroke
				edge = { colors = { rgb(255, 220, 90), rgb(255, 120, 200), rgb(120, 200, 255) }, spin = 40 },
			},
		},
		motion = {
			press = { scale = 0.9, down = 0.06, up = 0.3, style = Enum.EasingStyle.Back },
			hover = { scale = 1, time = 0.12 }, -- 1 = no hover effect
			open = { duration = 0, from = 0.85, style = Enum.EasingStyle.Back }, -- 0 = appear instantly
			close = { duration = 0, to = 0.85, style = Enum.EasingStyle.Quad },
			pop = { from = 0.6, duration = 0.35, style = Enum.EasingStyle.Back }, -- RatePrompt-style popups
		},
		-- Creator Store audio ids (number or "rbxassetid://..."). nil = silent (click falls back to Ui.configure clickSound)
		sounds = {
			click = nil :: any,
			open = nil :: any,
			close = nil :: any,
			purchase = nil :: any,
			notify = nil :: any,
			volume = { click = 0.4, open = 0.5, close = 0.4, purchase = 0.6, notify = 0.5 },
		},
		text = {
			-- TextStrokeTransparency per font role (nil = no stroke). Color = strokeColor or palette.stroke
			stroke = { title = 0.25, number = 0.25, button = 0.35 } :: { [string]: number },
			strokeColor = nil :: Color3?,
			-- letter case per role: "upper" | "lower" | nil (as written). Applied to Text and later Loc changes
			case = {} :: { [string]: string },
		},
		-- UX modules (docs/33 §11: Tooltip, Ui.statRow, Objective, Profile, ShowcaseUi, HitFx). Merge uses none of them.
		-- Color nil = the palette color named in the comment.
		ux = {
			tooltip = {
				delay = 0.35,
				hold = 0.45,
				maxWidth = 280,
				textSize = 17,
				bg = nil :: Color3?,
				transparency = 0.06,
			}, -- bg = palette.bg
			stat = { label = nil :: Color3?, value = nil :: Color3?, chip = nil :: Color3?, chipStyle = "pill" }, -- textDim / text / panelAlt; pill | square
			objective = { beam = nil :: Color3?, pulse = nil :: Color3?, done = nil :: Color3? }, -- accent / accent / good
			hit = {
				color = rgb(255, 235, 190), -- sparks + normal damage numbers
				crit = rgb(255, 200, 40),
				flash = rgb(255, 255, 255), -- HitFx.flash Highlight fill
				trail = nil :: Color3?, -- swing trail (nil = white -> accent)
			},
			pedestal = {
				color = rgb(236, 232, 246),
				trim = nil :: Color3?, -- palette.accent
				material = Enum.Material.SmoothPlastic,
				glow = true, -- rarity-colored light + ring
				plate = true, -- name plate over the item
				spin = 30, -- item spin deg/s on clients (0 = still)
			},
		},
	}
end

local function isArray(t: any): boolean
	return type(t) == "table" and (rawget(t, 1) ~= nil)
end

-- Deep merge: dicts merge key by key, arrays and datatypes replace. src values of false stay false.
local function mergeInto(dst: { [any]: any }, src: { [any]: any })
	for k, v in src do
		local cur = dst[k]
		if type(v) == "table" and not isArray(v) and type(cur) == "table" and not isArray(cur) then
			mergeInto(cur, v)
		else
			dst[k] = v
		end
	end
end

-- Partial game tokens -> full tokens. Errors on unknown groups/styles (typos would silently do nothing).
function Theme.merge(tokens: Tokens?): Tokens
	local out = Theme.defaults()
	if not tokens then
		return out
	end
	for group, v in tokens do
		if not GROUPS[group] then
			error("Theme: unknown token group '" .. tostring(group) .. "'", 2)
		end
		if type(v) ~= "table" then
			error("Theme: group '" .. tostring(group) .. "' must be a table", 2)
		end
	end
	-- legacy palette names (ink, dim, card, outline) are accepted as input
	if tokens.palette then
		local pal = table.clone(tokens.palette)
		for old, new in Theme.ALIASES do
			if pal[old] ~= nil then
				if pal[new] == nil then
					pal[new] = pal[old]
				end
				pal[old] = nil
			end
		end
		tokens = table.clone(tokens)
		tokens.palette = pal
	end
	mergeInto(out, tokens :: any)
	local shape = out.shape
	if not Theme.BUTTON_STYLES[shape.buttonStyle] then
		error("Theme: unknown buttonStyle '" .. tostring(shape.buttonStyle) .. "'", 2)
	end
	if not Theme.PANEL_STYLES[shape.panelStyle] or not Theme.PANEL_STYLES[shape.cardStyle] then
		error("Theme: unknown panelStyle/cardStyle", 2)
	end
	if not Theme.TITLE_STYLES[shape.titleStyle] then
		error("Theme: unknown titleStyle '" .. tostring(shape.titleStyle) .. "'", 2)
	end
	return out
end

-- Fill a Ui.THEME-shaped table in place (keeps table identity: modules hold `local THEME = Ui.THEME`).
-- Writes every palette key plus the legacy alias names.
function Theme.fillLegacy(target: { [string]: any }, palette: { [string]: any })
	for k, v in palette do
		target[k] = v
	end
	for old, new in Theme.ALIASES do
		target[old :: string] = palette[new :: string]
	end
end

-- Audio id: number -> "rbxassetid://n"; strings pass through; nil/0/"" -> nil
function Theme.soundId(v: any): string?
	if type(v) == "number" then
		return if v > 0 then "rbxassetid://" .. tostring(math.floor(v)) else nil
	elseif type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

local function weightOf(w: any): Enum.FontWeight?
	if typeof(w) == "EnumItem" then
		return w :: any
	elseif type(w) == "string" then
		return (Enum.FontWeight :: any)[w]
	end
	return nil
end

local function styleOf(s: any): Enum.FontStyle?
	if typeof(s) == "EnumItem" then
		return s :: any
	elseif type(s) == "string" then
		return (Enum.FontStyle :: any)[s]
	end
	return nil
end

-- Font token -> (Enum.Font?, Font?). Exactly one is non-nil for a valid token.
-- Enum.Font stays an enum (sets .Font, identical to the pre-theme UI); everything else becomes a FontFace.
function Theme.font(spec: any): (Enum.Font?, Font?)
	local t = typeof(spec)
	if t == "EnumItem" then
		return spec :: any, nil
	elseif t == "Font" then
		return nil, spec :: any
	end
	local family, weight, style = spec, nil, nil
	if type(spec) == "table" then
		family = spec.family
		weight = weightOf(spec.weight)
		style = styleOf(spec.style)
	end
	local w = weight or Enum.FontWeight.Regular
	local s = style or Enum.FontStyle.Normal
	if typeof(family) == "EnumItem" then
		local f = Font.fromEnum(family :: any)
		return nil, Font.new(f.Family, weight or f.Weight, style or f.Style)
	elseif typeof(family) == "Font" then
		local f = family :: Font
		return nil, Font.new(f.Family, weight or f.Weight, style or f.Style)
	elseif type(family) == "number" then
		-- Creator Store font asset id (same as Font.fromId; Font.new also takes ids above 2^31)
		return nil, Font.new("rbxassetid://" .. string.format("%d", family), w, s)
	elseif type(family) == "string" then
		if string.find(family, "^rbxasset") then
			return nil, Font.new(family, w, s)
		end
		return nil, Font.fromName(family, w, s)
	end
	error("Theme: bad font token " .. tostring(spec), 2)
end

-- Gradient token -> ColorSequence (Color3, {Color3...} evenly spaced, or ColorSequence)
function Theme.colorSequence(colors: any): ColorSequence
	if typeof(colors) == "ColorSequence" then
		return colors
	elseif typeof(colors) == "Color3" then
		return ColorSequence.new(colors)
	end
	local list = colors :: { Color3 }
	if #list == 1 then
		return ColorSequence.new(list[1])
	elseif #list == 2 then
		return ColorSequence.new(list[1], list[2])
	end
	local keys = {}
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), c))
	end
	return ColorSequence.new(keys)
end

-- Letter case: "upper" | "lower" | nil
function Theme.applyCase(text: string, case: string?): string
	if case == "upper" then
		return string.upper(text)
	elseif case == "lower" then
		return string.lower(text)
	end
	return text
end

return Theme
