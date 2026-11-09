--!nocheck
-- lune run tests/core/Theme.spec.luau (game 디렉터리에서)
-- Theme uses Roblox datatypes (Color3, Font, Enum...) as globals; Lune provides them in @lune/roblox.
local roblox = require("@lune/roblox")
Color3, ColorSequence, ColorSequenceKeypoint, Font, Enum =
	roblox.Color3, roblox.ColorSequence, roblox.ColorSequenceKeypoint, roblox.Font, roblox.Enum

local T = require("../T")
local Require = require("../Require")
local Theme = Require("src/core/shared/Theme")

local rgb = Color3.fromRGB

-- 1. Defaults reproduce the pre-theme constants (Ui.luau, ShopUi, LeaderboardUi, Banner before 2026-10-29).
--    Merge Cube Factory (live) never calls Ui.theme, so these ARE its look. Do not edit to make a test pass.
local OLD_THEME = {
	panel = rgb(37, 35, 59),
	card = rgb(52, 49, 80),
	button = rgb(66, 63, 99),
	accent = rgb(255, 209, 61),
	accentInk = rgb(36, 26, 8),
	ink = rgb(236, 235, 246),
	dim = rgb(132, 128, 166),
	good = rgb(120, 220, 140),
	bad = rgb(240, 90, 110),
	lucky = rgb(130, 255, 150),
	outline = rgb(30, 24, 40),
}
local d = Theme.defaults()
local legacy = {}
Theme.fillLegacy(legacy, d.palette)
for k, v in OLD_THEME do
	T.eq("legacy THEME." .. k, legacy[k], v)
end
T.eq("panelAlt = card", d.palette.panelAlt, OLD_THEME.card)
T.eq("text = ink", d.palette.text, OLD_THEME.ink)
T.eq("textDim = dim", d.palette.textDim, OLD_THEME.dim)
T.eq("stroke = outline", d.palette.stroke, OLD_THEME.outline)
-- hard-coded colors in core panels
T.eq("accent2 (FOREVER ribbon)", d.palette.accent2, rgb(150, 90, 255))
T.eq("buy", d.palette.buy, rgb(90, 220, 110))
T.eq("buyText", d.palette.buyText, Color3.new(1, 1, 1))
T.eq("desc", d.palette.desc, rgb(225, 220, 245))
T.eq("sub", d.palette.sub, rgb(255, 240, 200))
T.eq("mine", d.palette.mine, rgb(70, 66, 30))
T.eq("medal 1", d.palette.medals[1], rgb(255, 209, 61))
T.eq("medal 2", d.palette.medals[2], rgb(205, 210, 225))
T.eq("medal 3", d.palette.medals[3], rgb(222, 150, 90))

T.eq("font title", d.fonts.title, Enum.Font.FredokaOne)
T.eq("font button", d.fonts.button, Enum.Font.FredokaOne)
T.eq("font number", d.fonts.number, Enum.Font.FredokaOne)
T.eq("font body", d.fonts.body, Enum.Font.GothamMedium)
T.eq("font caption", d.fonts.caption, Enum.Font.GothamBold)

T.eq("corner", d.shape.corner, 10)
T.eq("cornerScale", d.shape.cornerScale, 1)
T.eq("stroke panel", d.shape.stroke.panel, 4)
T.eq("stroke card", d.shape.stroke.card, 2)
T.eq("stroke button", d.shape.stroke.button, 3)
T.eq("padding x", d.shape.padding.x, 0.06)
T.eq("padding y", d.shape.padding.y, 0.12)
T.eq("shadow off", d.shape.shadow, false)
T.eq("buttonStyle", d.shape.buttonStyle, "gradient")
T.eq("panelStyle", d.shape.panelStyle, "classic")
T.eq("cardStyle", d.shape.cardStyle, "classic")
T.eq("titleStyle", d.shape.titleStyle, "plain")
local g = d.shape.gradients
T.eq("SHADE", Theme.colorSequence(g.button.colors), ColorSequence.new(Color3.new(1, 1, 1), rgb(165, 160, 185)))
T.eq("card shade", Theme.colorSequence(g.card.colors), ColorSequence.new(Color3.new(1, 1, 1), rgb(165, 160, 185)))
T.eq("panel shade", Theme.colorSequence(g.panel.colors), ColorSequence.new(Color3.new(1, 1, 1), rgb(150, 140, 190)))
T.eq(
	"PANEL_EDGE",
	Theme.colorSequence(g.edge.colors),
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 220, 90)),
		ColorSequenceKeypoint.new(0.5, rgb(255, 120, 200)),
		ColorSequenceKeypoint.new(1, rgb(120, 200, 255)),
	})
)
T.eq("edge spin", g.edge.spin, 40)
T.eq("rotation", g.button.rotation, 90)

T.eq("press scale", d.motion.press.scale, 0.9)
T.eq("press down", d.motion.press.down, 0.06)
T.eq("press up", d.motion.press.up, 0.3)
T.eq("press style", d.motion.press.style, Enum.EasingStyle.Back)
T.eq("hover none", d.motion.hover.scale, 1)
T.eq("open instant", d.motion.open.duration, 0)
T.eq("close instant", d.motion.close.duration, 0)
T.eq("pop from", d.motion.pop.from, 0.6)
T.eq("pop duration", d.motion.pop.duration, 0.35)

T.eq("no click sound", d.sounds.click, nil)
T.eq("no open sound", d.sounds.open, nil)
T.eq("click volume", d.sounds.volume.click, 0.4)
T.eq("stroke title", d.text.stroke.title, 0.25)
T.eq("stroke button", d.text.stroke.button, 0.35)
T.eq("no body stroke", d.text.stroke.body, nil)
T.eq("no caption stroke", d.text.stroke.caption, nil)
T.eq("no case", next(d.text.case), nil)

-- defaults() is a fresh copy each call
d.palette.panel = rgb(1, 2, 3)
T.eq("defaults not shared", Theme.defaults().palette.panel, OLD_THEME.panel)

-- 2. Merging
local m = Theme.merge(nil)
T.eq("merge nil = defaults", m.palette.accent, OLD_THEME.accent)

m = Theme.merge({
	palette = { accent = rgb(1, 1, 1), ink = rgb(2, 2, 2), medals = { rgb(3, 3, 3) } },
	shape = { buttonStyle = "pill", stroke = { button = 5 }, shadow = { offset = 6 } },
	text = { case = { title = "upper" } },
	sounds = { click = 123 },
})
T.eq("override accent", m.palette.accent, rgb(1, 1, 1))
T.eq("alias ink -> text", m.palette.text, rgb(2, 2, 2))
T.eq("alias key removed", m.palette.ink, nil)
T.eq("untouched kept", m.palette.panel, OLD_THEME.panel)
T.eq("array replaces", #m.palette.medals, 1)
T.eq("nested merge keeps siblings", m.shape.stroke.panel, 4)
T.eq("nested override", m.shape.stroke.button, 5)
T.eq("table replaces false", m.shape.shadow.offset, 6)
T.eq("buttonStyle", m.shape.buttonStyle, "pill")
T.eq("case", m.text.case.title, "upper")
T.eq("press kept", m.motion.press.scale, 0.9)
T.eq("sound raw", m.sounds.click, 123)
T.eq("sound volume kept", m.sounds.volume.click, 0.4)

local legacy2 = { panel = OLD_THEME.panel }
local same = legacy2
Theme.fillLegacy(legacy2, m.palette)
T.ok("fillLegacy keeps identity", legacy2 == same)
T.eq("fillLegacy ink", legacy2.ink, rgb(2, 2, 2))
T.eq("fillLegacy text", legacy2.text, rgb(2, 2, 2))
T.eq("fillLegacy outline", legacy2.outline, OLD_THEME.outline)

-- text wins over alias when both are given
m = Theme.merge({ palette = { ink = rgb(9, 9, 9), text = rgb(8, 8, 8) } })
T.eq("canonical wins", m.palette.text, rgb(8, 8, 8))

-- input table is not mutated
local input = { palette = { dim = rgb(5, 5, 5) } }
Theme.merge(input)
T.eq("input untouched", input.palette.dim, rgb(5, 5, 5))

T.ok("unknown group errors", not pcall(Theme.merge, { colours = {} }))
T.ok("bad buttonStyle errors", not pcall(Theme.merge, { shape = { buttonStyle = "fancy" } }))
T.ok("bad panelStyle errors", not pcall(Theme.merge, { shape = { panelStyle = "wood" } }))
T.ok("bad titleStyle errors", not pcall(Theme.merge, { shape = { titleStyle = "big" } }))
for s in Theme.BUTTON_STYLES do
	T.ok("button style ok " .. s, pcall(Theme.merge, { shape = { buttonStyle = s } }))
end
for s in Theme.PANEL_STYLES do
	T.ok("panel style ok " .. s, pcall(Theme.merge, { shape = { panelStyle = s, cardStyle = s } }))
end

-- 3. Fonts
local e, f = Theme.font(Enum.Font.FredokaOne)
T.eq("enum stays enum", e, Enum.Font.FredokaOne)
T.eq("enum no face", f, nil)
e, f = Theme.font("Bangers")
T.eq("name -> face", e, nil)
T.ok("name family", string.find(f.Family, "Bangers") ~= nil)
_, f = Theme.font({ family = "Montserrat", weight = "Bold" })
T.eq("weight string", f.Weight, Enum.FontWeight.Bold)
_, f = Theme.font({
	family = "rbxasset://fonts/families/GothamSSm.json",
	weight = Enum.FontWeight.Heavy,
	style = "Italic",
})
T.eq("rbxasset family", f.Family, "rbxasset://fonts/families/GothamSSm.json")
T.eq("rbxasset weight", f.Weight, Enum.FontWeight.Heavy)
T.eq("style string", f.Style, Enum.FontStyle.Italic)
_, f = Theme.font(12187365364)
T.eq("store id", f.Family, "rbxassetid://12187365364")
_, f = Theme.font({ family = Enum.Font.FredokaOne, weight = "Bold" })
T.eq("enum + weight family", f.Family, "rbxasset://fonts/families/FredokaOne.json")
T.eq("enum + weight", f.Weight, Enum.FontWeight.Bold)
local face = Font.new("rbxasset://fonts/families/Bangers.json")
_, f = Theme.font(face)
T.eq("Font passes", f, face)
T.ok("bad font errors", not pcall(Theme.font, true))

-- 4. Small helpers
T.eq("soundId number", Theme.soundId(123), "rbxassetid://123")
T.eq("soundId string", Theme.soundId("rbxassetid://9"), "rbxassetid://9")
T.eq("soundId 0", Theme.soundId(0), nil)
T.eq("soundId nil", Theme.soundId(nil), nil)
T.eq("case upper", Theme.applyCase("Shop", "upper"), "SHOP")
T.eq("case lower", Theme.applyCase("Shop", "lower"), "shop")
T.eq("case none", Theme.applyCase("Shop", nil), "Shop")
T.eq("1 color", Theme.colorSequence(rgb(1, 2, 3)), ColorSequence.new(rgb(1, 2, 3)))

-- ux group (docs/33 §11): defaults present, partial override keeps the rest
local ux = Theme.defaults().ux
T.ok("ux defaults", ux.tooltip.delay == 0.35 and ux.pedestal.glow == true and ux.stat.chipStyle == "pill")
local mux = Theme.merge({ ux = { pedestal = { spin = 0 }, hit = { crit = rgb(1, 2, 3) } } }).ux
T.ok("ux partial merge", mux.pedestal.spin == 0 and mux.pedestal.plate == true and mux.hit.crit == rgb(1, 2, 3))

T.done()
