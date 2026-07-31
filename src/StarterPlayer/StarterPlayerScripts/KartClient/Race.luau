--[[
	Race — lap counting, timing and validation. Logic only; RaceHud
	draws it.

	VALIDATION
	----------
	Every checkpoint must be passed IN ORDER before the finish line will
	bank a lap. That's what stops reversing over the line, cutting the
	track, or sitting on a finish line that's also the start line.

	With no checkpoints tagged the system degrades to a plain
	MinLapTime guard, so a bare track still counts laps.

	Client-side and unvalidated by the server, which is fine for a
	placeholder but means times are not authoritative. A real
	leaderboard would move this server-side, or at minimum have the
	server verify the trigger sequence.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local TagZones = require(BloxKart:WaitForChild("TagZones"))
local Standings = require(BloxKart:WaitForChild("Standings"))
local Route = require(BloxKart:WaitForChild("Route"))
local CollectionService = game:GetService("CollectionService")

local R = Config.Race

local Race = {}
Race.__index = Race

-- Shared with the server, which needs the identical answer for missile
-- route-following. Two copies of this is how the two ends start
-- disagreeing about what order a checkpoint is.
local orderOf = Route.orderOf

--=====================================================================
--  FACING
--
--  Which way a race trigger says "down the track". Named after Studio's
--  move-handle arrow colours, because that's what you're looking at
--  while placing the thing.
--
--  Roblox's own LookVector is the part's -Z, so "Z" (the positive axis,
--  the way the blue arrow points) is its negation. That off-by-a-sign is
--  exactly why this is a named table rather than inline maths.
--=====================================================================
local AXES: { [string]: (CFrame) -> Vector3 } = {
	["X"] = function(cf)
		return cf.RightVector
	end,
	["-X"] = function(cf)
		return -cf.RightVector
	end,
	["Y"] = function(cf)
		return cf.UpVector
	end,
	["-Y"] = function(cf)
		return -cf.UpVector
	end,
	["Z"] = function(cf)
		return -cf.LookVector
	end,
	["-Z"] = function(cf)
		return cf.LookVector
	end,
}

local warnedFacing = false

local function facingOf(cf: CFrame): Vector3
	local pick = AXES[R.CheckpointFacing]
	if not pick then
		if not warnedFacing then
			warnedFacing = true
			warn(
				("[Race] CheckpointFacing = %q isn't one of X/-X/Y/-Y/Z/-Z — falling back to the part's front face.")
					:format(tostring(R.CheckpointFacing))
			)
		end
		return cf.LookVector
	end
	return pick(cf)
end

-- Rebuild a trigger's CFrame as "standing here, facing down the track".
--
-- Position is untouched; Respawn lifts it clear of the surface itself.
-- Up stays the part's own up so this still works on a loop, where the
-- track normal is the only meaningful up.
local function facedCFrame(cf: CFrame): CFrame
	local forward = facingOf(cf)
	local up = cf.UpVector
	-- Choosing Y as forward would make up parallel to the view and
	-- lookAt degenerate. Pick any other axis rather than erroring.
	if math.abs(forward:Dot(up)) > 0.99 then
		up = -cf.LookVector
	end
	return CFrame.lookAt(cf.Position, cf.Position + forward, up)
end

function Race.new()
	local opts = { cooldown = R.TriggerCooldown, forceQueryable = R.ForceQueryable }
	return setmetatable({
		startZone = TagZones.new(R.StartTag, opts),
		endZone = TagZones.new(R.EndTag, opts),
		-- Bigger MaxParts than the default: if the road segments are the
		-- checkpoints, the kart straddles two at every seam and a tight cap
		-- could truncate the one it's looking for out of the results.
		checkZone = TagZones.new(R.CheckpointTag, {
			cooldown = R.TriggerCooldown,
			forceQueryable = R.ForceQueryable,
			maxParts = R.CheckpointMaxOverlap,
		}),

		-- Locked means "ignore the world entirely": no starting, no
		-- checkpoints, no laps. MatchService holds the lock outside the
		-- Racing phase, so crossing the line on the grid or during the
		-- results screen can't bank anything.
		locked = false,

		running = false,
		finished = false,
		lapsDone = 0,
		raceStart = 0,
		lapStart = 0,
		lapTimes = {},
		bestLap = nil,

		wrongFor = 0, -- seconds spent pointing back up the track

		cpPassed = 0, -- how many checkpoints banked this lap
		lastCheckpoint = nil, -- CFrame. Ready for a "reset to track"
		-- button whenever you want one.

		_ordersCache = nil,
		_ordersCount = -1,
	}, Race)
end

-- Sorted unique checkpoint orders.
--
-- Cached rather than rebuilt per call: Update() and the HUD both want
-- it every frame, and two throwaway tables per frame is pointless
-- garbage. Invalidated when the tagged set changes size, which is the
-- only realistic runtime mutation.
function Race:_orders(): { number }
	local count = #self.checkZone.parts
	if self._ordersCache and self._ordersCount == count then
		return self._ordersCache
	end

	local seen, list = {}, {}
	for _, part in self.checkZone.parts do
		local o = orderOf(part)
		if not seen[o] then
			seen[o] = true
			table.insert(list, o)
		end
	end
	table.sort(list)

	self._ordersCache = list
	self._ordersCount = count
	return list
end

--=====================================================================
--  SETUP DIAGNOSTIC
--
--  The failure this catches: checkpoints with no Order attribute and no
--  trailing digit in the name ALL resolve to order 0. Distinct orders
--  are what the sequence is built from, so five unnumbered gates
--  collapse into ONE — the first you touch registers and every other
--  one silently does nothing.
--
--  From the driver's seat that looks exactly like "the kart drives
--  through tagged checkpoints and nothing happens", which is impossible
--  to distinguish from a broken trigger without being told.
--=====================================================================
function Race:Diagnose()
	local parts = self.checkZone.parts
	if #parts == 0 then
		print("[Race] no Checkpoint-tagged parts — laps fall back to a MinLapTime guard.")
		return
	end

	local byOrder: { [number]: { string } } = {}
	for _, part in parts do
		local o = orderOf(part)
		byOrder[o] = byOrder[o] or {}
		table.insert(byOrder[o], part.Name)
	end

	local orders = self:_orders()
	print(("[Race] %d checkpoint parts, %d distinct order(s):"):format(#parts, #orders))
	for _, o in orders do
		print(("          order %-4d  %s"):format(o, table.concat(byOrder[o], ", ")))
	end

	if #orders == 1 and #parts > 1 then
		warn(
			("[Race] ⚠ all %d checkpoints share one order, so only ONE counts per lap "
				.. "and the rest do nothing. Set an `Order` attribute (1, 2, 3…) on each, "
				.. "or rename them Checkpoint1, Checkpoint2…"):format(#parts)
		)
	end

	-- Not necessarily wrong — a wide gate built from two parts at the
	-- same order is legitimate, and passing either should count. Worth
	-- surfacing so an accidental duplicate isn't invisible.
	for _, o in orders do
		if #byOrder[o] > 1 then
			print(
				("[Race]   note: order %d has %d parts (%s) — passing any ONE of them advances the sequence."):format(
					o,
					#byOrder[o],
					table.concat(byOrder[o], ", ")
				)
			)
		end
	end

	-- Whether a checkpoint is track you drive ON or a volume you drive
	-- THROUGH decides if it stays part of the kart's world (see
	-- WorldFilter). Both are valid; reported because getting it wrong is
	-- invisible in the code and very obvious from the driving seat —
	-- either you bump an invisible wall or you fall through the road.
	local surface, volume, bumpy = 0, 0, {}
	for _, part in parts do
		if CollectionService:HasTag(part, R.SurfaceTag) then
			surface += 1
		else
			volume += 1
			-- Excluded from kart movement either way, so not a bug — but a
			-- solid volume still blocks players on foot, and it's almost
			-- always left over from creating the part.
			if part.CanCollide then
				table.insert(bumpy, part.Name)
			end
		end
	end

	if surface > 0 and volume > 0 then
		print(("[Race] %d tagged %s (driven ON), %d volumes (driven THROUGH)."):format(surface, R.SurfaceTag, volume))
	elseif surface > 0 then
		print(("[Race] all %d tagged %s — the road itself is the checkpoint."):format(surface, R.SurfaceTag))
	else
		print(("[Race] all %d are gate volumes you drive through."):format(volume))
	end

	if #bumpy > 0 then
		print(
			("[Race]   tidy-up: %d volume(s) still have CanCollide on (%s). The kart ignores them, "
				.. "but players on foot will walk into them."):format(#bumpy, table.concat(bumpy, ", "))
		)
	end

	print(("[Race] respawns face the %s axis of each trigger."):format(R.CheckpointFacing))
end

function Race:_begin(now: number)
	self.running = true
	self.finished = false
	self.lapsDone = 0
	self.raceStart = now
	self.lapStart = now
	self.cpPassed = 0
	self.lastCheckpoint = nil
	self.wrongFor = 0
	table.clear(self.lapTimes)
	self.bestLap = nil
end

-- Start the clock NOW, rather than waiting to cross a line. This is how
-- a match starts a race: timing begins the instant the lights go out,
-- which is also the instant the karts are released.
--
-- Note the karts are SITTING ON the start line when this is called, so
-- the line must not also count as a crossing — checkpoint validation
-- handles that, since no checkpoints have been passed yet.
function Race:Begin()
	self.locked = false
	self:_begin(os.clock())
end

-- Back to pre-race. Called on entering the grid, so a second round
-- doesn't inherit the first one's laps or times.
function Race:Reset()
	self.locked = true
	self.running = false
	self.finished = false
	self.lapsDone = 0
	self.cpPassed = 0
	self.raceStart = 0
	self.lapStart = 0
	self.lastCheckpoint = nil
	self.wrongFor = 0
	table.clear(self.lapTimes)
	self.bestLap = nil
end

-- Returns an events table: { started, checkpoint = n, lapDone = n,
-- finished, rejected = true }
function Race:Update(sim): { [string]: any }
	local events = {}
	if self.locked then
		return events
	end

	local now = os.clock()
	local cf, size = sim.hitbox.CFrame, sim.hitbox.Size

	local hitStart = self.startZone:Touch(cf, size)
	local hitEnd = self.endZone:Touch(cf, size)

	----------------------------------------------------------------
	-- Not started yet
	----------------------------------------------------------------
	if not self.running then
		if hitStart then
			self:_begin(now)
			events.started = true
		elseif R.AutoStartOnMove and self.startZone:isEmpty() and math.abs(sim.speed) > R.AutoStartSpeed then
			-- No start line in the world; fall back to "you moved".
			self:_begin(now)
			events.started = true
		end
		return events
	end

	if self.finished then
		return events
	end

	----------------------------------------------------------------
	-- Checkpoints — only the NEXT one in sequence counts. Driving back
	-- through an earlier one, or skipping ahead, does nothing.
	----------------------------------------------------------------
	--
	-- We look for the EXPECTED order among everything we're overlapping,
	-- rather than asking which trigger we just entered. The order gate is
	-- already the anti-retrigger — you can't pass order 3 twice in a lap
	-- — so the per-part cooldown adds nothing here and actively hurts
	-- when overlaps are continuous, as they are when the road segments
	-- themselves are the checkpoints.
	local orders = self:_orders()
	if self.cpPassed < #orders then
		local expected = orders[self.cpPassed + 1]
		for _, part in self.checkZone:Overlapping(cf, size) do
			if orderOf(part) == expected then
				self.cpPassed += 1
				self.lastCheckpoint = part.CFrame
				events.checkpoint = self.cpPassed
				break
			end
		end
	end

	----------------------------------------------------------------
	-- Bank a lap
	----------------------------------------------------------------
	if hitEnd then
		local valid
		if #orders > 0 then
			-- Checkpoints are the validation. Time doesn't come into it.
			valid = self.cpPassed >= #orders
		else
			-- Bare track: elapsed time is all we have to go on.
			valid = now - self.lapStart >= R.MinLapTime
		end

		if valid then
			local lapTime = now - self.lapStart
			self.lapsDone += 1
			table.insert(self.lapTimes, lapTime)
			if not self.bestLap or lapTime < self.bestLap then
				self.bestLap = lapTime
			end
			self.lapStart = now
			self.cpPassed = 0
			events.lapDone = self.lapsDone

			if self.lapsDone >= R.TotalLaps then
				self.finished = true
				events.finished = true
			end
		elseif self.cpPassed > 0 then
			-- Crossed the line without completing the route.
			--
			-- Only warned about once they've actually banked something.
			-- With zero checkpoints passed they're either still sitting on
			-- the start line at the lights, or they reversed straight back
			-- over it — neither is a wrong turn worth flashing about.
			events.rejected = true
		end
	end

	return events
end

--=====================================================================
--  READOUTS
--=====================================================================

-- 1-based lap currently being driven, clamped so it never shows 4/3.
function Race:CurrentLap(): number
	return math.clamp(self.lapsDone + 1, 1, R.TotalLaps)
end

--=====================================================================
--  WRONG WAY
--
--  Reuses CheckpointFacing rather than inventing a second convention:
--  the arrow you aim down the track for respawns is already a statement
--  of which way traffic flows, so the checkpoint you're currently inside
--  knows the local road direction. With the road segments tagged as
--  checkpoints that's exact; with gates it's the direction of the last
--  gate you crossed, which is close enough at the scale this matters.
--
--  Deliberately NOT the straight line to the next checkpoint: round a
--  hairpin that points through a wall, and driving the track correctly
--  would read as going backwards.
--=====================================================================
function Race:_intendedDirection(): Vector3?
	local ref = self.lastCheckpoint
	if not ref then
		-- Before the lap's first checkpoint, the start line is the best
		-- available statement of "this way".
		local pad = self.startZone.parts[1] or self.checkZone.parts[1]
		ref = pad and pad.CFrame
	end
	return if ref then facingOf(ref) else nil
end

-- Sustained, so a spin or a big drift doesn't flash it. Reset instantly
-- once you're pointing the right way again — a warning that lingers
-- after you've fixed it trains people to ignore it.
function Race:WrongWay(sim, dt: number): boolean
	if not self.running or self.finished then
		self.wrongFor = 0
		return false
	end

	local dir = self:_intendedDirection()
	-- Below the speed floor you're most likely reversing off a wall on
	-- purpose, which doesn't need a scolding.
	if not dir or math.abs(sim.speed) < R.WrongWaySpeed then
		self.wrongFor = 0
		return false
	end

	-- Actual direction of MOTION, not where the nose points: reversing
	-- flips it, and reversing at speed up the track is wrong way too.
	local heading = if sim.speed < 0 then -sim.travel else sim.travel

	if heading:Dot(dir) < R.WrongWayDot then
		self.wrongFor += dt
	else
		self.wrongFor = 0
	end
	return self.wrongFor >= R.WrongWayTime
end

-- Wrong way for long enough that they are not coming back on their own.
--
-- Deliberately a LONG time after the warning, not a second one. Going
-- backwards briefly is a legitimate thing to do — turning around after
-- an overshoot, doubling back for an item box, catching a slide that
-- spun you. Yanking someone out of any of those is worse than the
-- problem being solved.
--
-- This is for the player who has genuinely lost the track, and it is
-- the last resort behind the warning and the manual reset.
function Race:IsLost(): boolean
	return self.wrongFor >= R.LostTime
end

-- The checkpoint they still owe, for the HUD. Nil once the lap is
-- complete and the finish line is what's left.
function Race:NextCheckpoint(): number?
	local orders = self:_orders()
	if self.cpPassed >= #orders then
		return nil
	end
	return orders[self.cpPassed + 1]
end

function Race:CheckpointProgress(): (number, number)
	return self.cpPassed, #self:_orders()
end

function Race:LapElapsed(): number
	if not self.running or self.finished then
		return self.lapTimes[#self.lapTimes] or 0
	end
	return os.clock() - self.lapStart
end

function Race:TotalElapsed(): number
	if not self.running then
		return 0
	end
	if self.finished then
		local sum = 0
		for _, t in self.lapTimes do
			sum += t
		end
		return sum
	end
	return os.clock() - self.raceStart
end

-- Best known place to put a fallen kart: the last checkpoint passed,
-- else the start line, else nil so the caller can fall back to the grid.
--
-- Reoriented so the kart faces down the track — see CheckpointFacing.
-- The raw trigger CFrame is NOT usable directly: a checkpoint gate is a
-- slab spanning the road, so its natural front face points across the
-- track, not along it.
function Race:RespawnCFrame(): CFrame?
	if self.lastCheckpoint then
		return facedCFrame(self.lastCheckpoint)
	end
	local pad = self.startZone.parts[1]
	return if pad then facedCFrame(pad.CFrame) else nil
end

-- One monotonic number describing how far round the track we are, for
-- the standings relay. See Standings for why it's a single scalar.
function Race:ProgressScore(sim): number
	local distance = 0
	if self.lastCheckpoint then
		distance = (sim.pos - self.lastCheckpoint.Position).Magnitude
	end
	return Standings.score(self.lapsDone, self.cpPassed, distance)
end

-- Our place in the field, from the replicated progress attributes.
function Race:Place(sim): number
	local kart = sim.model
	if not kart then
		return 0
	end
	local place = Standings.placeOf(Standings.order(Standings.allKarts()), kart)
	return place
end

function Race:FieldSize(): number
	return #Standings.order(Standings.allKarts())
end

function Race:Destroy()
	self.startZone:Destroy()
	self.endZone:Destroy()
	self.checkZone:Destroy()
end

return Race
