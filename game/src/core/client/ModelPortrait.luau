--!strict
-- Opt-in helper: show a 3D Model as a small portrait in a ViewportFrame (item icons, list rows, cards).
-- Nothing requires this module unless a game does, so games that do not use it are unaffected (docs/33 10.1).
--
--   local vp = ModelPortrait.frame({ Size = UDim2.fromOffset(60, 60), Parent = row })
--   ModelPortrait.show(vp, "plant:12", function() return buildModel() end, { spin = true })
--
-- * frame:  transparent ViewportFrame with flat, bright lighting (readable at icon size).
-- * show:   clones the cached template for `key` (factory runs once per key) into the frame, fits the camera
--           to the model bounds and optionally spins it slowly (only while the frame is visible).
-- * fit:    camera distance from the bounding sphere, so any model fills the frame the same way.
local RunService = game:GetService("RunService")

local ModelPortrait = {}

export type Opts = {
	spin: boolean?, -- slow turntable (default false: static, costs nothing per frame)
	spinSpeed: number?, -- radians per second (default 0.6)
	fov: number?, -- default 28
	pad: number?, -- extra distance multiplier (default 1.08)
	view: Vector3?, -- direction from the model towards the camera (default 3/4 view, slightly above)
}

local templates: { [string]: Model } = {}

-- Template for key (built once by factory, never parented). Clone it; do not put the template itself in a frame.
function ModelPortrait.template(key: string, factory: () -> Model): Model
	local t = templates[key]
	if not t then
		t = factory()
		templates[key] = t
	end
	return t
end

function ModelPortrait.clearCache()
	for _, m in templates do
		m:Destroy()
	end
	table.clear(templates)
end

function ModelPortrait.frame(props: { [string]: any }): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(175, 175, 175)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-0.5, -1, -0.8)
	for k, v in props do
		(vp :: any)[k] = v
	end
	return vp
end

-- Put model (already a private clone) into vp and frame it.
function ModelPortrait.set(vp: ViewportFrame, model: Model, opts: Opts?)
	local o: Opts = opts or {}
	for _, c in vp:GetChildren() do
		c:Destroy()
	end
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = o.fov or 28
	cam.Parent = vp
	vp.CurrentCamera = cam

	local center = model:GetBoundingBox().Position
	local _, size = model:GetBoundingBox()
	local radius = size.Magnitude * 0.5
	local dist = radius / math.sin(math.rad(cam.FieldOfView * 0.5)) * (o.pad or 1.08)
	local dir = (o.view or Vector3.new(0.5, 0.35, 1)).Unit
	cam.CFrame = CFrame.lookAt(center + dir * dist, center)

	if o.spin then
		local speed = o.spinSpeed or 0.6
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			if not vp.Parent then
				conn:Disconnect()
				return
			end
			if vp.Visible and vp.AbsoluteSize.X > 0 then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, speed * dt, 0))
			end
		end)
		vp.Destroying:Once(function()
			conn:Disconnect()
		end)
	end
end

-- Cached portrait: factory builds the template once per key; each frame gets its own clone.
function ModelPortrait.show(vp: ViewportFrame, key: string, factory: () -> Model, opts: Opts?)
	ModelPortrait.set(vp, ModelPortrait.template(key, factory):Clone(), opts)
end

return ModelPortrait
