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
local Standings = require(BloxKart:WaitForChild("Standings"))
local WorldFilter = require(script.Parent.WorldFilter)

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
local function makePart(item): BasePart
	local spec = item.Projectile
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
	return part
end

-- Where the target is and how far round the track, from replicated
-- state. The route index is what decides when the missile stops
-- following the road and commits to a chase — see Ballistics.
local function targetOf(kart: Model?): Ballistics.Target?
	if not kart then
		return nil
	end
	local hb = kart.PrimaryPart
	if not hb then
		return nil
	end
	return {
		pos = hb.Position,
		abs = Route.absoluteOf(kart:GetAttribute(Standings.ATTRIBUTE), #Route.nodes()),
	}
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
		target = msg.target,
		shooter = msg.shooter,
		part = makePart(item),
	}
	state.part.CFrame = Ballistics.cframe(state)
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
			p.part.CFrame = Ballistics.cframe(p)
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

			p.part.CFrame = Ballistics.cframe(p)

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
