--[[
	Props — knock the scenery over. Client-local, cosmetic, safe.

	THE TRAP THIS AVOIDS
	--------------------
	The obvious build is "make the prop CanCollide false and let the kart
	push it". That does not work here for two reasons, and both are
	load-bearing:

	  1. CanCollide is not the flag. Movement in this game is QUERY based
	     — Simulation sweeps with a Blockcast — so a part with CanCollide
	     false and CanQuery TRUE is still a solid wall to the kart. A cone
	     would stop you dead while looking like it should not.

	  2. The kart is kinematic. There is no force to transfer, so nothing
	     would be "pushed" even if it could be.

	So a prop is made NON-QUERYABLE — invisible to movement entirely —
	and the hit is detected here by distance. The prop never affects
	handling, and the collision you appear to have is the animation.

	ANCHORED THROUGHOUT. Nothing is unanchored, so Roblox physics is
	never involved and cannot fight anyone for ownership.

	IT IS A TIMELINE, NOT A SIMULATION — AND THAT IS THE WHOLE FIX.
	---------------------------------------------------------------
	This ran as an integrated arc first: velocity, gravity, a ground
	raycast, bounce, roll, a resting flag. Every single props bug came
	out of that one decision, because integrated state can DRIFT — and
	once it has drifted there is no frame that puts it back:

	  hovering        the ground check measured an axis-aligned box that
	                  grew as the cone tumbled, so the floor rose with it
	  frozen mid-air  a phase that stopped advancing stayed stopped
	  crooked restore home was a guess, and a wrong guess is permanent
	  never settling   roll decayed per frame, so it depended on framerate

	Now the pose is a pure function of `home` and elapsed time, rebuilt
	from scratch every frame. Nothing accumulates, so nothing can drift,
	and the total life is a constant — "it is back" happens on a known
	frame rather than eventually.

	The floor is DERIVED, NOT SEARCHED FOR. Whatever the prop was authored
	standing on is directly beneath its lowest point, so that height is
	recorded once and the prop is seated on it at every instant, at any
	orientation, from its own measured box. There is no ground ray to aim
	in the wrong direction and nothing to be fooled by whatever the prop
	happens to be overlapping. Measuring is not what broke this; measuring
	EVERY FRAME, with a box that grew as the cone turned, is what broke it.

	EVERY CLIENT DRAWS ITS OWN ARC, FROM A BROADCAST.
	--------------------------------------------------
	The client that hits a cone reports it. The server validates and
	broadcasts a direction, a power and a seed. Every client — including
	the one that hit it — animates locally from those three numbers.

	That is deliberate and it is the third design this went through:

	  client-only   smooth, but nobody else saw it
	  server-driven shared, but anchored CFrame writes do not interpolate,
	                so it arrived in visible network steps
	  relay (this)  shared AND smooth, and roughly a thousandth of the
	                traffic: one small event per hit instead of a CFrame
	                per part per frame

	FINDINGS says it outright — "anchored CFrame writes don't interpolate,
	client-side rendering is the fix" — and missiles already work this way.

	The seed is what keeps the tumble identical everywhere without sending
	any rotation.

	IT OWNS ITS OWN HEARTBEAT. It used to be stepped from the client's
	main loop, which returns early with no kart, while spectating and
	while AI-driven — so cones froze mid-air. Nothing about a piece of
	scenery cares whether you are driving.

	WRITES CFRAME ON A PART THE SERVER NEVER TOUCHES. That is what makes
	the local write safe: with no second writer there is nothing to fight,
	which is the same rule the kart's own ownership follows.

	TAG THE MODEL OR TAG THE PART — BOTH WORK.
	------------------------------------------
	A cone is almost always a Model, and tagging the Model is the natural
	thing to do. The first version only accepted BaseParts, so a tagged
	Model was skipped silently and nothing ever flew.

	A tagged unit is now whatever you tagged: a Model moves by PivotTo and
	a bare part by CFrame. Every BasePart underneath is made
	non-queryable either way, because it only takes ONE queryable part in
	a model to turn the whole cone back into a wall.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local RunService = game:GetService("RunService")

local Names = require(BloxKart:WaitForChild("Names"))
local Util = require(BloxKart:WaitForChild("Util"))

local P = Config.Props
local log = Util.logger("Props", P.Debug)

local Props = {}
Props.__index = Props

-- A tagged unit is a Model or a BasePart. These helpers are the only
-- places that care which, so nothing else has to branch.
local function pivotOf(unit: Instance): CFrame?
	if unit:IsA("Model") then
		local ok, cf = pcall(unit.GetPivot, unit)
		return if ok then cf else nil
	elseif unit:IsA("BasePart") then
		return unit.CFrame
	end
	return nil
end

local function setPivot(unit: Instance, cf: CFrame)
	if unit:IsA("Model") then
		unit:PivotTo(cf)
	elseif unit:IsA("BasePart") then
		unit.CFrame = cf
	end
end

-- The unit's own bounding box: its centre and its size, in the unit's
-- own frame rather than the world's.
--
-- Model:GetBoundingBox is aligned to the model's PIVOT, not to the world
-- axes — which is the whole reason it is usable here and GetExtentsSize
-- was not. An axis-aligned box grows as the thing inside it rotates; a
-- pivot-aligned one does not. Even so this is read ONCE, while the prop
-- is still standing where it was authored, and never again.
local function boxOf(unit: Instance): (CFrame?, Vector3?)
	if unit:IsA("BasePart") then
		return unit.CFrame, unit.Size
	elseif unit:IsA("Model") then
		local ok, cf, size = pcall(unit.GetBoundingBox, unit)
		if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" and size.Magnitude > 1e-3 then
			return cf, size
		end
	end
	return nil, nil
end

-- How far a box of these half-extents reaches BELOW its own centre when
-- rotated like this.
--
-- The standard support-function answer: project each of the box's three
-- axes onto world up and add the magnitudes. This is what lets a prop be
-- seated on the ground at any orientation without a single raycast — and
-- unlike a ground ray it cannot be fooled by whatever the prop is
-- currently overlapping.
local function halfDrop(rot: CFrame, half: Vector3): number
	return math.abs(rot.XVector.Y) * half.X
		+ math.abs(rot.YVector.Y) * half.Y
		+ math.abs(rot.ZVector.Y) * half.Z
end

-- Every BasePart under the unit. ONE queryable part is enough to turn a
-- cone back into a wall, so this has to reach all of them.
local function partsOf(unit: Instance): { BasePart }
	local out = {}
	if unit:IsA("BasePart") then
		table.insert(out, unit)
	end
	for _, d in unit:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

function Props.new()
	local self = setmetatable({
		known = {}, -- unit -> true
		sentAt = {}, -- unit -> last report, local debounce only
		inside = {}, -- unit -> kart is within its radius, for edge detection
		flying = {}, -- unit -> arc state
		home = {}, -- unit -> CFrame it belongs at, taken at adopt
		box = {}, -- unit -> its size and its floor, measured once at adopt
		alpha = {}, -- part -> its authored Transparency
		sim = nil :: any,
		conns = {},
	}, Props)

	local function adopt(unit: Instance)
		if self.known[unit] then
			return
		end
		if not (unit:IsA("Model") or unit:IsA("BasePart")) then
			warn(("[Props] %s is tagged %q but is a %s — tag a Model or a BasePart."):format(
				unit:GetFullName(),
				P.Tag,
				unit.ClassName
			))
			return
		end
		-- ADOPTED ON THE TAG, not on a part count. The client starts
		-- before Workspace has finished replicating, so a Model routinely
		-- looks empty for the first frames — and with StreamingEnabled
		-- parts come and go all session.
		self.known[unit] = true

		-- RE-MEASURED EVERY TIME A PART ARRIVES, UNTIL IT IS FLUNG.
		--
		-- THIS IS THE BUG THAT KEPT IT FROM COMING BACK TO ITS SPOT, and
		-- it survived every rewrite because it is in the measuring, not
		-- the animating:
		--
		-- A Model with no PrimaryPart has no pivot of its own — GetPivot
		-- derives one from the parts that exist RIGHT NOW. Workspace
		-- replicates progressively, so a cone routinely has two of its
		-- five parts when we first look at it, and the pivot of two parts
		-- is not the pivot of five. The old code locked that first answer
		-- in and every restore afterwards aimed at it. Permanently a few
		-- studs off, and no amount of fixing the animation could help.
		--
		-- The fix is an invariant rather than a guess: A PROP THAT IS NOT
		-- FLYING IS AT HOME. So measuring it at any such moment is correct
		-- by definition, and the newest measurement is always the best one.
		-- It stops updating the moment it is flung, which is the only time
		-- the reading would be wrong.
		local function measure()
			if self.flying[unit] or #partsOf(unit) == 0 then
				return
			end
			local home = pivotOf(unit)
			local boxCF, size = boxOf(unit)
			if not home or not boxCF or not size then
				return
			end
			self.home[unit] = home

			local half = size / 2
			self.box[unit] = {
				half = half,
				-- Where the box centre sits relative to the PIVOT. A pivot
				-- is often not the centre of the thing — set by hand, or
				-- inherited from whichever part happened to be primary — and
				-- rotating about the wrong point is what makes a settled
				-- prop look like it is standing beside itself.
				offset = home:PointToObjectSpace(boxCF.Position),
				centre = boxCF.Position,
				-- THE FLOOR, DERIVED RATHER THAN SEARCHED FOR.
				--
				-- Whatever the prop was authored standing on is directly
				-- under its lowest point right now. No raycast: a ray would
				-- have to guess a direction and could hit the wrong thing,
				-- whereas this is simply true of where the artist put it.
				-- Uses home's rotation, so a prop authored on a slope keeps
				-- the height the slope gave it.
				groundY = boxCF.Position.Y - halfDrop(home.Rotation, half),
			}
		end

		local function disarm(part: Instance)
			if not part:IsA("BasePart") then
				return
			end
			if P.ForceNonQueryable then
				-- Belt and braces. What actually keeps props out of the
				-- movement sweep is Config.Props.Tag being in
				-- Triggers.TAGS, which is live and shared with the server.
				part.CanQuery = false
				part.CanCollide = false
			end
			part.Anchored = true
			-- Recorded BEFORE anything fades it, so a deliberately
			-- translucent prop is restored to its own value and not to 0.
			if self.alpha[part] == nil then
				self.alpha[part] = part.Transparency
			end
		end

		for _, part in partsOf(unit) do
			disarm(part)
		end
		table.insert(self.conns, unit.DescendantAdded:Connect(function(part)
			disarm(part)
			measure()
		end))

		-- HOME IS RECORDED NOW, not at fling time.
		--
		-- It used to be captured on the first hit, which is only correct
		-- if the cone was still home when you hit it. A cone already
		-- displaced — by an earlier arc that never finished, or by a
		-- streaming hiccup — had its WRONG position recorded as home and
		-- then dutifully "restored" itself there forever.
		--
		-- Adopt time is the one moment nothing has moved it yet, which is
		-- also the only moment its size means anything: measure() reads
		-- the box here, while the prop is still standing as authored, and
		-- never reads it again.
		--
		-- The old code called GetExtentsSize EVERY FRAME, and that is the
		-- AXIS-ALIGNED box — which GROWS as the cone tumbles. The floor it
		-- rested on rose with the tilt and changed every frame: the cone
		-- hovered and never settled. That was the anti-gravity, and the
		-- bug was the "every frame", not the measuring.
		measure()
	end

	local tagged = CollectionService:GetTagged(P.Tag)
	for _, unit in tagged do
		adopt(unit)
	end
	table.insert(self.conns, CollectionService:GetInstanceAddedSignal(P.Tag):Connect(adopt))
	table.insert(
		self.conns,
		CollectionService:GetInstanceRemovedSignal(P.Tag):Connect(function(unit)
			self.known[unit] = nil
			self.sentAt[unit] = nil
			self.flying[unit] = nil
			self.inside[unit] = nil
			self.box[unit] = nil
		end)
	)

	local n = 0
	for _ in self.known do
		n += 1
	end
	if n > 0 then
		print(("[Props] watching %q — adopted %d unit(s)."):format(P.Tag, n))
	else
		warn(("[Props] watching %q — adopted NOTHING (%d tagged). Tag a Model or a Part."):format(P.Tag, #tagged))
	end

	-- The broadcast. Fired for EVERY client, including whoever hit it, so
	-- there is exactly one code path producing the animation.
	local remote = BloxKart:WaitForChild(Names.PROP_REMOTE, 10)
	if remote and remote:IsA("RemoteEvent") then
		table.insert(
			self.conns,
			remote.OnClientEvent:Connect(function(unit, dir, power, seed)
				self:_fling(unit, dir, power, seed)
			end)
		)
	end

	-- ITS OWN LOOP. See the header: riding the main client loop is what
	-- left cones frozen in mid-air.
	table.insert(self.conns, RunService.Heartbeat:Connect(function()
		self:_step()
	end))

	return self
end

-- Called by the client loop purely to hand over the live simulation.
-- Detection needs it; the animation does not.
function Props:SetSim(sim)
	self.sim = sim
end

-- Played AT THE CONE, for everyone, on the broadcast.
--
-- Positional rather than on the kart, so another player's cone sounds
-- like it came from over there. Parented to the part and cleaned up by
-- Roblox once it finishes, so nothing is tracked.
--
-- The hitter hears it about half a ping late, which for an impact is
-- imperceptible — and it buys the guarantee that a sound never plays
-- without a cone moving.
function Props:_playAt(unit: Instance)
	local parts = partsOf(unit)
	local host = parts[1]
	if not host or P.HitSoundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = P.HitSoundId
	sound.Volume = P.HitSoundVolume
	sound.RollOffMaxDistance = P.HitSoundRange
	-- Randomised per hit: a cone is something you clip constantly, and a
	-- fixed pitch becomes a rattle you stop hearing within a lap.
	sound.PlaybackSpeed = P.PitchMin + math.random() * (P.PitchMax - P.PitchMin)
	sound.PlayOnRemove = false
	sound.Parent = host
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Backstop: Ended does not fire if the sound never loads.
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function Props:_setAlpha(unit: Instance, hidden: number)
	for _, part in partsOf(unit) do
		local base = self.alpha[part] or 0
		-- Toward the part's OWN value, never toward 0, so a translucent
		-- prop lands back where it started.
		part.Transparency = base + (1 - base) * hidden
	end
end

function Props:_fling(unit: any, dir: any, power: any, seed: any)
	if typeof(unit) ~= "Instance" or not self.known[unit] or self.flying[unit] then
		return
	end
	if typeof(dir) ~= "Vector3" or type(power) ~= "number" or power ~= power then
		return
	end
	-- NO RECORDED HOME AND NO MEASUREMENT, NO KNOCK. Better a cone that
	-- ignores you than one that can never be put back, or one that has to
	-- guess how tall it is to lie down.
	local home = self.home[unit]
	local box = self.box[unit]
	if not home or not box then
		return
	end

	-- Seeded, so every client tumbles it identically without any rotation
	-- crossing the wire.
	local rng = Random.new(if type(seed) == "number" then seed else 0)
	local strength = math.clamp(power / P.MaxPower, 0.25, 1)

	-- Flattened and normalised ONCE. Everything below is a function of
	-- these constants and `t` — nothing is integrated, so nothing drifts.
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, 1)

	-- WHERE IT ENDS UP IS DECIDED HERE, BEFORE IT HAS MOVED.
	--
	-- Backwards from how you would write a physics knock, and that is the
	-- point: the landing is not something the tumble happens to produce,
	-- it is the thing the tumble is built to reach. Pick the pose, then
	-- find the rotation that gets there, then spin some whole extra turns
	-- on top — which change nothing about where it stops.
	--
	-- Every hit is different: a random lean, about a random horizontal
	-- axis, with a random twist. No two cones settle alike and none of it
	-- is guesswork about where the ground is.
	local lean = math.rad(P.RestLean + (rng:NextNumber() * 2 - 1) * P.RestLeanJitter)
	local tipAt = rng:NextNumber() * math.pi * 2
	local rest = CFrame.fromAxisAngle(Vector3.new(math.cos(tipAt), 0, math.sin(tipAt)), lean)
		* CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)

	-- The single axis that takes it from standing to fallen, and the
	-- angle along it. Adding whole turns to that angle leaves the
	-- destination untouched, so the cone can spin as much as we like and
	-- still arrive exactly where it was always going.
	local axis, angle = rest:ToAxisAngle()
	local turns = math.max(1, math.round(P.SpinTurns * (0.7 + rng:NextNumber() * 0.6)))

	self.flying[unit] = {
		at = os.clock(),
		dir = flat,
		strength = strength,
		axis = if axis.Magnitude > 1e-3 then axis.Unit else Vector3.yAxis,
		sweep = angle + turns * math.pi * 2,
	}
	self:_playAt(unit)
	log("knocked %s — rests %.0f° over", unit.Name, math.deg(lean))
end

function Props:_step()
	local now = os.clock()

	-- DETECT. Needs a live kart; the animation below does not.
	--
	-- FIRES ON ENTERING THE RADIUS, NOT ON BEING INSIDE IT.
	--
	-- Being-inside was survivable while a prop's whole life was 1.7s and
	-- barely noticeable at 0.35s of hold. Now that a cone lies there for
	-- two seconds, stopping on top of its home spot would re-fling it the
	-- instant it returned, forever — a cone endlessly launching itself out
	-- from under a parked kart. An edge is also just the truer reading of
	-- "I hit it": you hit something once by arriving at it.
	local sim = self.sim
	if sim and sim.pos then
		local remote = BloxKart:FindFirstChild(Names.PROP_REMOTE)
		for unit in self.known do
			local cf = self.home[unit]
			if not unit.Parent or not cf then
				self.inside[unit] = nil
				continue
			end
			-- Measured against HOME, not the cone's current position: while
			-- it is in the air it is somewhere else entirely, and the spot
			-- is what you drove into.
			local near = (cf.Position - sim.pos).Magnitude < P.HitRadius
			local entered = near and not self.inside[unit]
			self.inside[unit] = near or nil

			if entered and not self.flying[unit] and (now - (self.sentAt[unit] or 0)) > P.ReportDebounce then
				self.sentAt[unit] = now
				if remote and remote:IsA("RemoteEvent") then
					remote:FireServer(unit)
				end
			end
		end
	end

	-- ANIMATE. A pure function of home and elapsed time.
	--
	-- The total life is fixed, so there is no phase that can fail to
	-- advance and nothing to get stuck in. Past the end, the cone is home
	-- and the entry is gone — not "eventually", but on that exact frame.
	local knock, hold, out, inn = P.KnockTime, P.HoldAfter, P.FadeOut, P.FadeIn
	local total = knock + hold + out + inn

	for unit, state in self.flying do
		local home, box = self.home[unit], self.box[unit]
		if not unit.Parent or not home or not box then
			self.flying[unit] = nil
			continue
		end

		local age = now - state.at
		if age >= total then
			-- Exactly home, fully visible, entry cleared. The only end
			-- state there is.
			setPivot(unit, home)
			self:_setAlpha(unit, 0)
			self.flying[unit] = nil
			continue
		end

		-- Where along the knock, 0..1, clamped so it simply holds at the
		-- end pose while it waits and fades.
		local t = math.clamp(age / knock, 0, 1)

		-- EASED, NOT LINEAR. Most of the distance and most of the spin
		-- happen in the first moments, so the prop leaves the bumper hard
		-- and slows into its resting pose. Linear motion is the single
		-- biggest reason an effect reads as "animated" rather than "hit".
		--
		-- Runs 0 to 1 exactly, so easing changes the pacing and never the
		-- destination.
		local travel = 1 - (1 - t) ^ P.SettleEase

		-- Rotation first, because how far the prop hangs below its own
		-- centre depends on it.
		local rot = home.Rotation * CFrame.fromAxisAngle(state.axis, state.sweep * travel)

		-- IT IS SAT ON THE GROUND AT EVERY INSTANT, NOT JUST AT THE END.
		--
		-- `groundY` is the height the artist's own placement implies, and
		-- `halfDrop` is how far this box reaches under its centre at this
		-- rotation. Add them and the prop touches down — so as it rolls
		-- through the tumble it rides the floor correctly the whole way,
		-- and at t=1 the hop is zero and it is simply resting there.
		--
		-- No raycast anywhere. A ray has to pick a direction and can hit
		-- the wrong surface; this cannot be wrong, because it is derived
		-- from where the prop already was.
		local seated = box.groundY + halfDrop(rot, box.half)

		-- IT BOUNCES, AND EACH BOUNCE IS LOWER THAN THE LAST.
		--
		-- |sin| is a run of arcs and (1 - t) shrinks them as they go, so
		-- with two bounces the cone throws itself up, comes down, hops
		-- once more at a quarter of the height and settles. Every zero of
		-- that curve is a moment the prop is touching the ground — and
		-- because `seated` is exact, it touches down properly each time
		-- rather than clipping through or hovering over.
		--
		-- The last zero is at t = 1, which is what leaves it ON the road
		-- at the end of the knock. That is why Bounces must be whole.
		local bounces = math.max(1, math.floor(P.Bounces))
		local hop = P.KnockHeight * state.strength * (1 - t) * math.abs(math.sin(math.pi * bounces * t))

		-- THE OFFSET IS WORLD SPACE, SO IT IS ADDED TO THE CENTRE AND NOT
		-- MULTIPLIED THROUGH IT.
		--
		-- `home * CFrame.new(offset)` would read the offset in the prop's
		-- OWN frame, so an identical hit would fling a cone rotated 90° in
		-- the map sideways. The direction came off the kart's velocity in
		-- world space; it has to be applied in world space.
		local out3 = state.dir * (P.KnockDistance * state.strength * travel)
		local centre = Vector3.new(box.centre.X + out3.X, seated + hop, box.centre.Z + out3.Z)

		-- Placed by its CENTRE, then backed out to the pivot — because a
		-- pivot is frequently not the middle of the thing, and rotating
		-- about the wrong point is what leaves a settled prop standing
		-- beside itself instead of where it fell.
		--
		-- ONE WRITE PER FRAME, from one decision. Posing it and then
		-- correcting it would be two owners of the same position inside a
		-- single frame, which is the exact shape of the bug this rewrite
		-- exists to remove.
		local pose = CFrame.new(centre - rot:VectorToWorldSpace(box.offset)) * rot
		local hidden = 0

		-- Fades where it lies; then it IS home for the whole fade back,
		-- because the swap happens at full transparency.
		if age > knock + hold then
			local f = age - knock - hold
			if f < out then
				hidden = f / out
			else
				pose = home
				hidden = 1 - math.clamp((f - out) / inn, 0, 1)
			end
		end

		setPivot(unit, pose)
		self:_setAlpha(unit, hidden)
	end
end

function Props:Destroy()
	for _, c in self.conns do
		c:Disconnect()
	end
	for unit in self.flying do
		if unit.Parent then
			-- Same rule as everywhere else: a recorded home or nothing.
			-- `CFrame.new()` as a fallback would have teleported the cone
			-- to the world ORIGIN, which is about the worst possible
			-- interpretation of "put it back".
			local home = self.home[unit]
			if home then
				setPivot(unit, home)
			end
			self:_setAlpha(unit, 0)
		end
	end
	table.clear(self.flying)
	table.clear(self.known)
end

return Props
