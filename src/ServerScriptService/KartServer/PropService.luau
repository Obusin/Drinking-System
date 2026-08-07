--[[
	PropService — the fling, owned by the server so everyone sees it.

	WHY THIS MOVED OFF THE CLIENT
	-----------------------------
	Three separate bugs had one cause: the client animated it.

	  1. NOT VISIBLE TO OTHERS. A cone flew on one screen and stood still
	     on every other.
	  2. FROZE MID-AIR. The client stepped props inside its main loop,
	     which returns early when there is no kart, when spectating, and
	     when the kart is AI-driven — so a cone in flight simply stopped
	     wherever it was. That is the "anchoring all over the place".
	  3. Nothing restored them, for the same reason.

	IT RELAYS, IT DOES NOT ANIMATE — and that is the second lesson.
	Server-driven CFrame writes on an anchored part replicate WITHOUT
	interpolation, so a cone moved from here arrives in network steps and
	looks laggy. FINDINGS says exactly this: "Anchored CFrame writes don't
	interpolate. Client-side rendering is the fix." Missiles already work
	this way.

	So the server validates the hit and broadcasts a handful of numbers.
	Every client draws its own smooth arc from them. What crosses the wire
	is one small event per hit rather than a CFrame per part per frame,
	which is both smoother AND far lighter.

	The freezing that sent this to the server in the first place is fixed
	on the client instead, by giving Props its own Heartbeat rather than
	riding the main loop that returns early.

	DETECTION STAYS ON THE CLIENT, and has to: only a client simulates its
	own kart, so only it can know it drove into something. It reports; the
	server decides. That split is the whole design.

	STILL ANCHORED, STILL NON-QUERYABLE, and disarmed here as well as on
	the client so a prop is never a wall for the server's own sweeps
	either — bots use the same filter and a cone is scenery to them too.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart.Config)
local Names = require(BloxKart.Names)
local Util = require(BloxKart.Util)

local KartService = require(script.Parent.KartService)

local P = Config.Props
local log = Util.logger("PropService", P.Debug)

local PropService = {}

-- unit -> when it was last flung. Only used to refuse a second fling
-- while one is in the air; the server tracks nothing else about it.
local busy: { [Instance]: number } = {}
local remote: RemoteEvent? = nil
-- Per player: how many reports this second, and when that second began.
local reports: { [Player]: { n: number, since: number } } = {}

local function pivotOf(unit: Instance): CFrame?
	if unit:IsA("Model") then
		local ok, cf = pcall(unit.GetPivot, unit)
		return if ok then cf else nil
	elseif unit:IsA("BasePart") then
		return unit.CFrame
	end
	return nil
end

--=====================================================================
--  REPORTS
--=====================================================================

local function onReport(player: Player, unit: any)
	-- FLOOD GUARD: a budget per second, not a gap between reports.
	--
	-- A fixed gap was wrong and it showed: at 0.25s per player, driving
	-- through cones 8 studs apart reported one every 0.13s and every
	-- report after the first was refused. The player heard each hit and
	-- watched one cone move.
	--
	-- Per-cone repeats are already prevented by `busy` below, so this
	-- only has to stop an actual flood.
	local now = os.clock()
	local r = reports[player]
	if not r or now - r.since >= 1 then
		r = { n = 0, since = now }
		reports[player] = r
	end
	r.n += 1
	if r.n > P.MaxReportsPerSecond then
		return
	end

	-- IT MUST BE A REAL PROP. The client sends an Instance, and the only
	-- thing that makes that acceptable is checking the tag here — an
	-- untagged Instance is refused, so this cannot be used to fling
	-- arbitrary scenery.
	if typeof(unit) ~= "Instance" or not CollectionService:HasTag(unit, P.Tag) then
		return
	end
	-- Already in the air somewhere. The server does not know where it IS,
	-- only that it is busy — which is all it needs to avoid restarting an
	-- arc every client is halfway through.
	if busy[unit] and os.clock() - busy[unit] < P.KnockTime + P.HoldAfter + P.FadeOut + P.FadeIn then
		return
	end

	local cf = pivotOf(unit)
	if not cf then
		return
	end

	-- AND THEY MUST ACTUALLY BE NEAR IT. Without this a client could
	-- knock over every cone on the map from the start line. Generous,
	-- because the client hit it a moment ago and has moved since.
	local kart = KartService.kartFor(player)
	local hitbox = kart and kart.PrimaryPart
	if not hitbox then
		return
	end
	-- FORGIVES NETWORK LAG. The client hit the cone at its own position;
	-- this hitbox is a hop behind, and at speed that is several studs of
	-- honest disagreement. Without the allowance the FAST hits are the
	-- ones that fail, which is exactly backwards.
	local vel = hitbox.AssemblyLinearVelocity
	local allowed = P.HitRadius * 3 + vel.Magnitude * P.ReportLagAllowance
	local away = (hitbox.Position - cf.Position).Magnitude
	if away > allowed then
		log("refused %s from %s — %.0f studs away (allowed %.0f)", unit.Name, player.Name, away, allowed)
		return
	end

	-- Launched along the kart's own heading, scaled by its speed. Taken
	-- from the hitbox's replicated velocity rather than anything the
	-- client sent, so the power cannot be inflated.
	-- The raw speed. The client scales it against P.MaxPower, so the
	-- server sends a fact and the look is decided in one place.
	local power = vel.Magnitude
	local dir = if vel.Magnitude > 1 then vel.Unit else hitbox.CFrame.LookVector

	-- RELAYED, NOT ANIMATED. Every client draws its own arc from these
	-- few numbers, so what crosses the wire is one small event per hit
	-- instead of a CFrame per part per frame.
	--
	-- The seed makes the tumble identical everywhere without sending the
	-- rotation: same seed, same random sequence, same spin. Cheaper than
	-- replicating three angles and exactly as consistent.
	busy[unit] = os.clock()
	if remote then
		remote:FireAllClients(unit, dir, power, math.random(1, 1e6))
	end
	log("%s flung %s at %.0f studs/s", player.Name, unit.Name, power)
end

--=====================================================================
--  START
--=====================================================================

function PropService.start()
	-- Disarmed HERE as well as on the client, so a prop is never a wall
	-- for the server's own queries either — bots sweep with the same
	-- filter, and a cone should be scenery to them too.
	local function disarm(unit: Instance)
		local parts = {}
		if unit:IsA("BasePart") then
			table.insert(parts, unit)
		end
		for _, d in unit:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		for _, part in parts do
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
		end
	end

	local tagged = CollectionService:GetTagged(P.Tag)
	for _, unit in tagged do
		disarm(unit)
		-- Late arrivals too: Workspace replicates progressively and
		-- StreamingEnabled brings parts back mid-session.
		unit.DescendantAdded:Connect(disarm)
	end
	CollectionService:GetInstanceAddedSignal(P.Tag):Connect(function(unit)
		disarm(unit)
		unit.DescendantAdded:Connect(disarm)
	end)

	local found = BloxKart:FindFirstChild(Names.PROP_REMOTE)
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = Names.PROP_REMOTE
		found.Parent = BloxKart
	end
	remote = found :: RemoteEvent
	found.OnServerEvent:Connect(onReport)

	Players.PlayerRemoving:Connect(function(player)
		reports[player] = nil
	end)

	print(("[PropService] %d prop(s) tagged %q."):format(#tagged, P.Tag))
end

return PropService
