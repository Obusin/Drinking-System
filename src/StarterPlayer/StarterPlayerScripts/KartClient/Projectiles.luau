--[[
	Projectiles — draws the missiles. Visual only; the server decides
	everything that matters (see ProjectileService).

	WHY THE CLIENT DRAWS THEM
	-------------------------
	A server-driven Anchored part replicates its CFrame at replication
	rate with no interpolation, which at 210 studs/s is a visible stutter.
	Here each client owns a local Part and integrates it with the same
	Ballistics code the server runs, so it moves at whatever frame rate
	the player has.

	The parts are created locally and never replicate — nobody else's
	client can see them, which is exactly right, because everyone is
	drawing their own copy of the same projectile.

	DRIFT AND CORRECTION
	--------------------
	Two integrations of the same guidance diverge slowly: the client homes
	on its replicated view of the target kart, the server on the real one.
	`sync` messages carry the authoritative position a few times a second
	and the visual is EASED toward them rather than snapped — a snap is a
	visible jump, and the whole point of this module is smoothness. If the
	error gets large enough that easing would look like the missile is
	sliding sideways, it snaps instead and accepts one jump.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Registry = require(BloxKart:WaitForChild("Items"))
local Ballistics = require(BloxKart:WaitForChild("Ballistics"))
local Route = require(BloxKart:WaitForChild("Route"))
local WorldFilter = require(BloxKart:WaitForChild("WorldFilter"))

local IT = Config.Items

local Projectiles = {}

local live: { [number]: any } = {} -- uid → state
local folder: Folder? = nil

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "BloxKartProjectiles"
	f.Parent = workspace
	folder = f
	return f
end

--=====================================================================
--  VISUAL
--=====================================================================
-- The authored rocket, if the server published one. Nil means draw the
-- plain part instead, which is a missile that looks basic rather than a
-- missile that doesn't appear.
local warnedNoRocket = false

local function rocketTemplate(): Instance?
	if IT.ProjectileModel == "" then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local model = assets and assets:FindFirstChild(IT.ProjectileModel)

	-- SAY SO, ONCE. The fallback is deliberate and silent by design, and
	-- that is precisely how a missing rocket goes unnoticed: the missile
	-- still flies, still homes, still explodes, and just looks like a
	-- neon box. Without this the only symptom is "the new asset isn't
	-- in", with nothing anywhere to say why.
	if not model and not warnedNoRocket then
		warnedNoRocket = true
		warn(
			("[Projectiles] no %q in ReplicatedStorage.Assets — drawing the plain part. The server publishes it from ServerStorage at startup; check the Output for an [Assets] line."):format(
				IT.ProjectileModel
			)
		)
	end
	return model
end

-- WHICH WAY THE MODEL'S NOSE POINTS, worked out from the model.
--
-- Guessing this in config is a round trip per attempt — build, launch,
-- watch it fly sideways, change a number, repeat — and it has to be
-- redone for every rocket anyone ever authors. The model already knows
-- the answer: a missile is long and thin, so its longest bounding-box
-- axis IS its nose axis.
--
-- So the offset is derived. Rotate that axis onto lookAt's -Z and the
-- rocket points where it is going, whatever local axis it was built
-- along.
--
-- WHAT THIS CANNOT KNOW is nose from tail — both ends of the long axis
-- look identical to a bounding box. That single bit is
-- ProjectileModelFlip, which is one boolean rather than four rotations
-- to choose between.
local function faceOffset(art: Instance): CFrame
	if not IT.ProjectileModelAutoFace then
		return CFrame.identity
	end

	local size: Vector3
	if art:IsA("Model") then
		local _, s = art:GetBoundingBox()
		size = s
	elseif art:IsA("BasePart") then
		size = art.Size
	else
		return CFrame.identity
	end

	local axis
	if size.X >= size.Y and size.X >= size.Z then
		axis = Vector3.xAxis
	elseif size.Y >= size.Z then
		axis = Vector3.yAxis
	else
		axis = Vector3.zAxis
	end

	-- Already built the right way round: -Z is what lookAt wants.
	if axis == Vector3.zAxis then
		return if IT.ProjectileModelFlip then CFrame.Angles(0, math.pi, 0) else CFrame.identity
	end

	-- lookAt(origin, axis) maps -Z onto `axis`; the inverse maps `axis`
	-- onto -Z, which is exactly the correction. The explicit up vector
	-- matters for a nose-up model, where the default up is parallel to
	-- the look direction and lookAt has no answer.
	local up = if axis == Vector3.yAxis then Vector3.zAxis else Vector3.yAxis
	local o = CFrame.lookAt(Vector3.zero, axis, up):Inverse()
	return if IT.ProjectileModelFlip then o * CFrame.Angles(0, math.pi, 0) else o
end

local function makePart(item): BasePart
	local spec = item.Projectile

	-- THE ROOT IS ALWAYS A PLAIN PART, and the art hangs off it.
	--
	-- Everything downstream moves the missile by writing one CFrame, in
	-- three separate places. Returning a Model would mean teaching all of
	-- them about PivotTo, and PivotTo walks every part in the model every
	-- frame. A welded root is one CFrame write however many pieces the
	-- rocket has, and it keeps this function's contract unchanged.
	local part = Instance.new("Part")
	part.Name = item.Id .. "Visual"
	part.Size = spec.Size
	part.Color = spec.Color
	part.Material = spec.Material
	part.Anchored = true
	part.CanCollide = false
	-- Must never read as a wall to our own kart's movement queries, and
	-- must never be picked up by the camera's occlusion raycast.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = container()

	local template = rocketTemplate()
	if not template then
		return part
	end

	-- With art on it the root becomes an invisible handle. Its size still
	-- matters — Ballistics knows nothing about the model — so it stays
	-- exactly as it was and simply stops being drawn.
	part.Transparency = 1

	local art = template:Clone()
	art.Name = "Art"

	-- Pose the art on the root BEFORE welding, or the weld freezes it
	-- wherever the template happened to sit.
	--
	-- Offset corrects the model's authored facing against lookAt's -Z
	-- forward. Art only; the flight path never sees it.
	local pose = part.CFrame * faceOffset(art) * IT.ProjectileModelOffset
	if art:IsA("Model") then
		art:PivotTo(pose)
	elseif art:IsA("BasePart") then
		art.CFrame = pose
	end
	art.Parent = part

	local pieces = if art:IsA("BasePart") then { art } else {}
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(pieces, d)
		end
	end

	for _, d in pieces do
		-- UNANCHORED AND WELDED, not anchored. An anchored part ignores
		-- welds, so an anchored rocket would hang at the launch point
		-- while the root flew off without it.
		d.Anchored = false
		d.Massless = true
		-- Inert, all of it. This is scenery moving at 200 studs/s through
		-- a world full of raycasts: a queryable rocket reads as a wall to
		-- a kart's sweep and as an obstruction to the camera.
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = part, d
		weld.Parent = part
	end

	return part
end

-- The drawn CFrame: where the server says it is, rolled about its own
-- nose.
--
-- PURELY COSMETIC, and it has to be. The server owns where a missile
-- goes; this rotates the picture around the direction of travel and
-- feeds nothing back. A lookAt CFrame's forward is -Z, so rolling about
-- the nose is a rotation about Z.
local function drawnCF(p): CFrame
	return Ballistics.cframe(p) * CFrame.Angles(0, 0, p.spin or 0)
end

-- Where the target is. Trivial now that a Target is only a position —
-- it carried a route index until the server took over deciding when to
-- commit.
local function targetOf(kart: Model?): Ballistics.Target?
	local hb = kart and kart.PrimaryPart
	return if hb then { pos = hb.Position } else nil
end

--=====================================================================
--  PATH DEBUG
--
--  Draws what the guidance actually decided, because we've now guessed
--  at this missile twice and been wrong both times.
--
--    green line   following the checkpoint route
--    red line     committed to chasing the target
--    yellow flash obstacle avoidance firing, at the thing it saw
--    blue markers the route nodes themselves
--
--  Every part is CanQuery false — a debug marker that a kart could
--  collide with would be a debugging tool that causes bugs.
--=====================================================================
local nodeMarkers: { BasePart } = {}

local function debugPart(name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Parent = container()
	return part
end

-- One marker per route node, rebuilt when the route changes size.
local function showNodes()
	local nodes = Route.nodes()
	if #nodeMarkers == #nodes then
		return
	end
	for _, m in nodeMarkers do
		m:Destroy()
	end
	table.clear(nodeMarkers)
	for i, node in nodes do
		local m = debugPart("RouteNode" .. i)
		m.Shape = Enum.PartType.Ball
		m.Size = Vector3.one * IT.ProjectileDebugNodeSize
		m.Color = IT.ProjectileDebugNode
		m.Transparency = 0.4
		m.Position = node.position
		table.insert(nodeMarkers, m)
	end
	print(("[Missile] %d route nodes marked"):format(#nodes))
end

-- A thin bar between two points. Rebuilt in place each frame rather than
-- recreated, so a missile in flight isn't churning instances.
local function drawLine(part: BasePart, from: Vector3, to: Vector3, colour: Color3)
	local span = to - from
	local len = span.Magnitude
	if len < 0.1 then
		part.Transparency = 1
		return
	end
	part.Transparency = 0.25
	part.Color = colour
	part.Size = Vector3.new(IT.ProjectileDebugWidth, IT.ProjectileDebugWidth, len)
	part.CFrame = CFrame.lookAt(from + span * 0.5, to)
end

local function updateDebug(p)
	if not p.dbgLine then
		p.dbgLine = debugPart("AimLine")
		p.dbgHit = debugPart("AvoidHit")
		p.dbgHit.Shape = Enum.PartType.Ball
		p.dbgHit.Size = Vector3.one * 2
		p.dbgHit.Color = IT.ProjectileDebugAvoid
	end

	if p.dbgAim then
		-- Avoidance overrides the aim, so it gets the line's colour: what
		-- you're seeing is what's actually steering.
		local colour = if p.dbgAvoid
			then IT.ProjectileDebugAvoid
			elseif p.dbgMode == "route" then IT.ProjectileDebugRoute
			else IT.ProjectileDebugHome
		drawLine(p.dbgLine, p.pos, p.dbgAim, colour)
	else
		p.dbgLine.Transparency = 1
	end

	p.dbgHit.Transparency = if p.dbgAvoid then 0.2 else 1
	if p.dbgAvoid then
		p.dbgHit.Position = p.dbgAvoid
	end
end

local function clearDebug(p)
	if p.dbgLine then
		p.dbgLine:Destroy()
	end
	if p.dbgHit then
		p.dbgHit:Destroy()
	end
end

local function destroy(uid: number)
	local p = live[uid]
	if not p then
		return
	end
	live[uid] = nil
	if p.part then
		p.part:Destroy()
	end
	clearDebug(p)
end


--=====================================================================
--  MESSAGES
--=====================================================================
local function onLaunch(msg)
	local item = Registry.byId(msg.itemId)
	if not (item and item.Projectile) then
		return
	end
	local state = {
		uid = msg.uid,
		item = item,
		pos = msg.pos,
		dir = msg.dir,
		up = msg.up,
		u = msg.u,
		lateral = msg.lateral or 0,
		way = msg.way,
		shooter = msg.shooter,
		part = makePart(item),
		-- Radians of roll, accumulated per frame. Rolled at spawn so two
		-- missiles in the air are never in phase with each other.
		spin = math.random() * math.pi * 2,
	}
	state.part.CFrame = drawnCF(state)
	live[msg.uid] = state
	if IT.ProjectileDebug then
		showNodes()
	end
end

local function onSync(msg)
	local p = live[msg.uid]
	if not p then
		return
	end
	-- Direction and up are taken outright: they're cheap to correct and a
	-- wrong heading compounds, whereas position error does not.
	p.dir = msg.dir
	p.up = msg.up
	-- Who the server locked. Not a local decision: every client has to
	-- draw the same chase.
	p.target = msg.target
	p.locked = msg.locked

	local err = (msg.pos - p.pos).Magnitude
	if err > IT.ProjectileSnapDistance then
		p.pos = msg.pos -- too far gone to ease; take the one jump
	else
		p.correct = msg.pos -- eased in over the next few frames
	end
end

local function onGone(msg)
	local p = live[msg.uid]
	if p and msg.pos then
		-- Put it where the server says it died before removing it, so an
		-- explosion doesn't appear a few studs off.
		p.pos = msg.pos
		if p.part then
			p.part.CFrame = drawnCF(p)
		end
	end
	destroy(msg.uid)
end

--=====================================================================
--  FRAME
--=====================================================================
local function step(dt: number)
	if next(live) == nil then
		return
	end
	local params = WorldFilter.rayParams

	for _, p in live do
		-- Stalled means we locally think it hit a wall. We keep drawing it
		-- where it stopped and wait: only the server may declare a
		-- projectile gone, and guessing would mean an explosion that never
		-- happened for anybody else.
		if not p.stalled then
			-- Our own view of the target — position AND route index, both off
			-- replicated state. Deliberately not authoritative: this is a
			-- picture, and it should follow what this player can actually see.
			if Ballistics.step(p, dt, targetOf(p.target), params) then
				p.stalled = true
			end

			-- Ease onto the last correction. Spread over several frames so a
			-- correction reads as the missile adjusting, not teleporting.
			if p.correct then
				p.pos = p.pos:Lerp(p.correct, math.min(IT.ProjectileCorrectRate * dt, 1))
				if (p.correct - p.pos).Magnitude < 0.1 then
					p.correct = nil
				end
			end

			-- Advanced by dt, so the roll is the same speed on every
			-- machine regardless of frame rate.
			p.spin = (p.spin or 0) + math.rad(IT.ProjectileSpin) * dt
			p.part.CFrame = drawnCF(p)

			if IT.ProjectileDebug then
				updateDebug(p)
			end
		end
	end
end

--=====================================================================
--  START
--=====================================================================
function Projectiles.start()
	local viewRemote = BloxKart:WaitForChild("KartProjectileView", 10)
	if not viewRemote then
		warn("[Projectiles] no KartProjectileView remote — is ProjectileService running?")
		return
	end

	viewRemote.OnClientEvent:Connect(function(kind, msg)
		if typeof(msg) ~= "table" then
			return
		end
		if kind == "launch" then
			onLaunch(msg)
		elseif kind == "sync" then
			onSync(msg)
		elseif kind == "gone" then
			onGone(msg)
		end
	end)

	RunService.Heartbeat:Connect(step)

	-- Nothing here survives a respawn meaningfully, and a leftover visual
	-- part in workspace would outlive the round.
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		for uid in live do
			destroy(uid)
		end
	end)
end

return Projectiles
