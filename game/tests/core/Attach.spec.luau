--!nocheck
-- lune run tests/core/Attach.spec.luau (game 디렉터리에서). Pure offset math of Core/Attach.
local roblox = require("@lune/roblox")
CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local T = require("../T")
local Attach = require("../Require")("src/core/shared/Attach")

local function close(a, b)
	local p = (a.Position - b.Position).Magnitude
	local r = (a.LookVector - b.LookVector).Magnitude + (a.UpVector - b.UpVector).Magnitude
	return p < 1e-4 and r < 1e-4
end

-- Tool.Grip convention: handle = hand * gripAttachment * Grip:Inverse()
local hand = CFrame.new(3, 4, 5) * CFrame.Angles(0.3, 1.1, -0.2)
local grip = CFrame.new(0, -1.2, 0.1) * CFrame.Angles(0, math.pi / 2, 0)
T.ok("rootWorld matches Tool.Grip", close(Attach.rootWorld(hand, grip), hand * grip:Inverse()))
T.ok("identity grip = at the attachment", close(Attach.rootWorld(hand), hand))

-- RigidConstraint aligns attachments: root * rootOffset == attachmentWorld
local off = CFrame.new(0, 0.5, -0.2)
local root = Attach.rootWorld(hand, grip, off)
T.ok("constraint alignment", close(root * Attach.rootOffset(grip, off), hand))
T.ok("offset moves in attachment space", close(Attach.rootWorld(hand, nil, off), hand * off))

-- Over head: bottom of a 2-stud box sits 0.3 over the head top
local oh = Attach.overHead(Vector3.new(2, 2, 2))
T.near("over head height", oh.Position.Y, 1.3, 1e-6)
T.near("over head custom gap", Attach.overHead(Vector3.new(1, 4, 1), 0).Position.Y, 2, 1e-6)

-- Root part below box center: carryOffset keeps the box (not the root) centered over the head
local box = CFrame.new(10, 5, 0)
local rootCf = CFrame.new(10, 4, 0) -- 1 stud under the box center
local co = Attach.carryOffset(box, Vector3.new(2, 4, 2), rootCf, 0.5)
local hat = CFrame.new(0, 20, 0)
local rootAt = Attach.rootWorld(hat, nil, co)
local boxAt = rootAt * rootCf:ToObjectSpace(box)
T.near("box center over head", boxAt.Position.Y, 20 + 2 + 0.5, 1e-5)
T.done()
