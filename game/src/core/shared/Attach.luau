--!strict
-- Attach held / worn / carried things to a character (docs/33 §11-6). Shared: call it on the server so everyone
-- sees it (welds replicate), or on the client for local-only visuals. No anchored parts moved by script.
--   Attach.toHand(character, sword, CFrame.new(0, -1.2, 0))         -- grip = where the hand holds the model, in
--                                                                   -- the model's root-part space (like Tool.Grip)
--   Attach.toAttachment(character, crown, "HatAttachment", CFrame.new(0, 0.3, 0))
--   Attach.carryOverHead(character, crate)                          -- sits on top of the head, any size
--   Attach.detach(crate)                                            -- removes only what Attach made
-- Works for R15 and R6 (both rigs have RightGripAttachment, HatAttachment, BodyBackAttachment...) and scaled avatars:
-- the character's own attachments carry the body scale; opts.scale = true also scales the model with the rig.
-- How: every part of the model is unanchored, massless, non-colliding and welded to its root part
-- (WeldConstraint), and the root is held by a RigidConstraint between the character attachment and an
-- attachment on the root at `offset`. Pure math (Lune-tested): Attach.rootOffset, Attach.overHead.

local Attach = {}

-- R6 / R15 part names that own each standard attachment (searched in this order; accessories are skipped)
Attach.HAND = { "RightHand", "Right Arm" }

local TAG = "CoreAttach"

-- Root part of what we hold: a BasePart itself, or Model.PrimaryPart, or the biggest part
function Attach.rootOf(model: Instance): BasePart?
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	local best: BasePart? = nil
	local size = -1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > size then
				best, size = d, v
			end
		end
	end
	return best
end

-- Character attachment by name on a body part (not inside accessories, which reuse the same names)
function Attach.find(character: Model, name: string): Attachment?
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") then
			local a = child:FindFirstChild(name)
			if a and a:IsA("Attachment") then
				return a
			end
		end
	end
	return nil
end

-- Pure: where the root-part attachment sits (root space) so that the character attachment holds `grip`.
-- Tool.Grip convention: grip is the hand's frame in the handle's space -> the root attachment CFrame = grip.
-- `offset` (character attachment space) moves the item: the root attachment = grip * offset:Inverse().
function Attach.rootOffset(grip: CFrame?, offset: CFrame?): CFrame
	local g = grip or CFrame.identity
	local o = offset or CFrame.identity
	return g * o:Inverse()
end

-- Pure: world CFrame of the root part for a character attachment world CFrame (for checks and previews)
function Attach.rootWorld(attachmentWorld: CFrame, grip: CFrame?, offset: CFrame?): CFrame
	return attachmentWorld * Attach.rootOffset(grip, offset):Inverse()
end

-- Pure: offset above HatAttachment for a thing `size` tall (bounding box), `gap` studs over the head top
function Attach.overHead(size: Vector3, gap: number?): CFrame
	return CFrame.new(0, size.Y / 2 + (gap or 0.3), 0)
end

-- Pure: offset for carryOverHead when the root part is not the bounding-box center (box = model:GetBoundingBox())
function Attach.carryOffset(boxCFrame: CFrame, boxSize: Vector3, rootCFrame: CFrame, gap: number?): CFrame
	return Attach.overHead(boxSize, gap) * boxCFrame:ToObjectSpace(rootCFrame)
end

export type Options = {
	scale: boolean?, -- Model:ScaleTo(character:GetScale()) first (Models only)
	parent: Instance?, -- default: the character (cleaned up on respawn)
	collide: boolean?, -- keep CanCollide (default false)
	keepTouch: boolean?, -- keep CanTouch (default true; weapons use Touched)
}

local function prepare(model: Instance, root: BasePart, o: Options?)
	local parts: { BasePart } = {}
	if model:IsA("BasePart") then
		table.insert(parts, model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	for _, p in parts do
		p.Anchored = false
		p.Massless = true
		if not (o and o.collide) then
			p.CanCollide = false
		end
		if o and o.keepTouch == false then
			p.CanTouch = false
		end
		if p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Name = TAG
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
end

-- Core: hold `model` at character attachment `attachName` (offset in that attachment's space)
local function attachAt(
	character: Model,
	model: Instance,
	attach: Attachment,
	grip: CFrame?,
	offset: CFrame?,
	o: Options?
): RigidConstraint?
	Attach.detach(model)
	local root = Attach.rootOf(model)
	if not root then
		warn("Attach: no BasePart in " .. model:GetFullName())
		return nil
	end
	if o and o.scale and model:IsA("Model") then
		local s = character:GetScale()
		if math.abs(s - model:GetScale()) > 1e-3 then
			model:ScaleTo(s)
		end
	end
	-- place first (same frame) so nothing visibly snaps, then weld
	local worldRoot = Attach.rootWorld(attach.WorldCFrame, grip, offset)
	if model:IsA("Model") then
		model:PivotTo(worldRoot * root.CFrame:ToObjectSpace(model:GetPivot()))
	else
		(model :: BasePart).CFrame = worldRoot
	end
	prepare(model, root, o)
	local a1 = Instance.new("Attachment")
	a1.Name = TAG
	a1.CFrame = Attach.rootOffset(grip, offset)
	a1.Parent = root
	local rc = Instance.new("RigidConstraint")
	rc.Name = TAG
	rc.Attachment0 = attach
	rc.Attachment1 = a1
	rc.Parent = root
	model:SetAttribute(TAG, attach.Name)
	model.Parent = (o and o.parent) or character
	return rc
end

-- In the right hand. grip = Tool.Grip-style (hand frame in the root part's space; CFrame.new(0, -1, 0) holds it
-- 1 stud above the root center). For a real Tool use Humanoid:EquipTool + Tool.Grip instead.
function Attach.toHand(character: Model, model: Instance, grip: CFrame?, o: Options?): RigidConstraint?
	local a = Attach.find(character, "RightGripAttachment")
	if not a then
		warn("Attach.toHand: no RightGripAttachment on " .. character.Name)
		return nil
	end
	return attachAt(character, model, a, grip, nil, o)
end

-- On a named character attachment ("HatAttachment", "BodyBackAttachment", "WaistBackAttachment",
-- "LeftGripAttachment", "FaceFrontAttachment", ...). offset is in that attachment's space.
function Attach.toAttachment(
	character: Model,
	model: Instance,
	attachmentName: string,
	offset: CFrame?,
	o: Options?
): RigidConstraint?
	local a = Attach.find(character, attachmentName)
	if not a then
		warn("Attach.toAttachment: no " .. attachmentName .. " on " .. character.Name)
		return nil
	end
	return attachAt(character, model, a, nil, offset, o)
end

-- Carried over the head (crates, eggs, loot): bottom of the model sits `gap` over the head top
function Attach.carryOverHead(character: Model, model: Instance, gap: number?, o: Options?): RigidConstraint?
	local size: Vector3
	if model:IsA("Model") then
		local cf, s = model:GetBoundingBox()
		local root = Attach.rootOf(model)
		size = s
		-- bounding-box center may differ from the root part: correct by the root's offset from the box center
		if root then
			return Attach.toAttachment(
				character,
				model,
				"HatAttachment",
				Attach.carryOffset(cf, s, root.CFrame, gap),
				o
			)
		end
	elseif model:IsA("BasePart") then
		size = model.Size
	else
		return nil
	end
	return Attach.toAttachment(character, model, "HatAttachment", Attach.overHead(size, gap), o)
end

-- Remove the constraints Attach made. The model stays where it is, unanchored (destroy or re-parent it).
function Attach.detach(model: Instance)
	if model:GetAttribute(TAG) == nil then
		return
	end
	local list = model:GetDescendants()
	if model:IsA("BasePart") then
		table.insert(list, model)
	end
	for _, d in list do
		if d.Name == TAG and (d:IsA("RigidConstraint") or d:IsA("Attachment") or d:IsA("WeldConstraint")) then
			d:Destroy()
		end
	end
	model:SetAttribute(TAG, nil)
end

function Attach.isAttached(model: Instance): boolean
	return model:GetAttribute(TAG) ~= nil
end

return Attach
