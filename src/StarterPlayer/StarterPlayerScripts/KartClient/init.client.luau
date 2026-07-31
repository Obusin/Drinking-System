--[[
	KartClient — THE client script.
	--------------------------------------------------------------------
	Single Script Architecture: this is the only LocalScript. Everything
	else is a ModuleScript underneath it, wired together here.

		KartClient (LocalScript)
		├── Simulation   movement. Owns pos/forward/up/speed
		├── Input        every button, plus look-orbit offsets
		├── Effects      drift trails, boost speed lines
		├── Audio        engine, charge notes, boost
		├── CameraRig    surface-rolling chase cam
		├── Boosters     tagged speed pads in the world
		├── Projectiles  draws missiles locally; server owns the hits
		├── TouchHud     mobile on-screen controls (touch devices only)
		├── Race         lap counting and timing
		├── Match        mirrors the server's round phase; holds the grid
		├── MatchHud     countdown, status line, results board
		├── RaceHud      lap/timer readout, bottom right
		├── ControlsHud  key list, bottom left, fades after a few seconds
		├── SpeedHud     speedometer, bottom centre
		└── Rider        steering wheel + hand IK (all karts, always on)

	Tunables all live in ReplicatedStorage.BloxKart.Config.

	Simulation knows nothing about Effects, Audio or the camera. It
	returns an events table each frame and this script dispatches it, so
	adding a new reaction to "tier changed" means touching one place.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config"))
local Names = require(ReplicatedStorage.BloxKart.Names)
local WorldFilter = require(ReplicatedStorage.BloxKart.WorldFilter)
local Simulation = require(ReplicatedStorage.BloxKart.Simulation)
local Input = require(script.Input)
local Effects = require(script.Effects)
local Audio = require(script.Audio)
local Haptics = require(script.Haptics)
local CameraRig = require(script.CameraRig)
local Boosters = require(script.Boosters)
local Race = require(script.Race)
local Match = require(script.Match)
local MatchHud = require(script.MatchHud)
local RaceHud = require(script.RaceHud)
local ControlsHud = require(script.ControlsHud)
local SpeedHud = require(script.SpeedHud)
local ItemHud = require(script.ItemHud)
local FeedHud = require(script.FeedHud)
local Items = require(script.Items)
local Respawn = require(script.Respawn)
local Projectiles = require(script.Projectiles)
local TouchHud = require(script.TouchHud)
local Rider = require(script.Rider)
local RemoteKarts = require(script.RemoteKarts)

local H = Config.Hud
local HAP = Config.Haptics

local player = Players.LocalPlayer

-- Shared empty events table for the frames a subsystem is skipped.
-- Frozen so a stray write can't turn it into a real event next frame.
local NO_EVENTS = table.freeze({})

local humanoid: Humanoid? = nil
local sim, effects, audio, camera, boosters, items = nil, nil, nil, nil, nil, nil

-- The race outlives any single kart, so it isn't torn down with one.
local race = Race.new()
-- So does the match — it's the thing that decides whether there IS a
-- kart to drive, and its HUD has to show "waiting for racers" before
-- anyone has spawned.
local match = Match.new()
local matchHud = MatchHud.new()
local hud = RaceHud.new()
local controls = ControlsHud.new()
local speedo = SpeedHud.new()
local itemHud = ItemHud.new()
local feedHud = FeedHud.new()
local respawn = Respawn.new()
-- Made once rather than per kart: it holds motor state, not kart state,
-- and rebuilding it on every respawn would drop a rumble mid-decay.
local haptics = Haptics.new()
-- Mobile only, and nil everywhere else — every call site is guarded, so
-- desktop carries no touch code at all rather than an inert copy of it.
local touch = if TouchHud.wanted() then TouchHud.new() else nil
local progressRemote = ReplicatedStorage.BloxKart:WaitForChild("KartProgressReport", 10)
local reportAt = 0
local heartbeat: RBXScriptConnection? = nil

local function getHumanoid(): Humanoid?
	return humanoid
end

--=====================================================================
--  TEARDOWN
--=====================================================================
local function teardown()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	Input.unbind()
	if effects then
		effects:Destroy()
		effects = nil
	end
	if audio then
		audio:Destroy()
		audio = nil
	end
	if boosters then
		boosters:Destroy()
		boosters = nil
	end
	if items then
		items:Destroy()
		items = nil
	end
	if camera then
		-- Always restore, even mid-loop, or the player is left stuck in
		-- a Scriptable camera on foot.
		camera:Restore(humanoid)
		camera = nil
	end
	speedo:SetActive(false)
	-- Motors off. A pad still rumbling after the kart it belonged to has
	-- gone is the one haptics bug players actually report.
	haptics:Stop()
	if touch then
		touch:SetActive(false)
	end
	sim = nil
end

--=====================================================================
--  FRAME
--=====================================================================
local function step(dt: number)
	if not sim or sim.seat.Occupant == nil then
		return
	end

	-- FIRST, before the kart moves. This is what holds it on the grid, so
	-- it has to run before the step that would otherwise drive it off.
	local matchEvents = match:Update(dt, sim, race)
	if matchEvents.newRound then
		-- Nobody starts a race holding last race's missile.
		items:Clear()
	end
	if matchEvents.gridded then
		camera:Snap()
	end
	if matchEvents.countdown then
		matchHud:Countdown(matchEvents.countdown)
		audio:PlayTierNote(0) -- one beep per light
	end
	if matchEvents.go then
		matchHud:Go()
		audio:Boost(2)
		camera:BoostPunch(1) -- a kick off the line, from the camera only
	end
	if matchEvents.finished then
		audio:Boost(3)
	end

	Input.update(dt)
	local events = sim:Step(dt, Input)

	-- Publish OUR steer onto OUR kart so Rider can turn the wheel and the
	-- front tyres. The VehicleSeat never sees a touch player's steering —
	-- the pad feeds Simulation directly — so SteerFloat alone leaves a
	-- mobile driver cornering with the wheel dead straight. Client-set, so
	-- it stays local; other people's karts fall back to SteerFloat.
	if sim.model then
		sim.model:SetAttribute(Names.STEER, sim.steer)
		-- ...and the slide angle, so the front wheels can cancel it and
		-- stay pointed down the road through a drift.
		sim.model:SetAttribute(Names.DRIFT, sim.driftAngle)
	end

	-- Dispatch. Simulation doesn't know these modules exist.
	if events.driftStarted then
		haptics:Punch(HAP.DriftPunch)
		effects:SetTrails(true, 0) -- ribbon starts immediately, grey until tier 1
		-- Deliberately NO note here. It shared the asset with the tank-fill
		-- cue, so every drift opened with what sounded like a slot filling
		-- — a reward for having done nothing yet. The tyre screech is the
		-- drift's cue; `tankFilled` below owns this sound alone.
	end
	if events.tierChanged then
		-- Colour only. The note belongs to `tankFilled` below — drift tiers
		-- and tank fills happen at different moments and BOTH used to play
		-- it, which is what doubled the sound. One note per bar.
		effects:SetTrails(true, events.tierChanged)
	end
	if events.driftEnded then
		effects:SetTrails(false, 0)
	end
	-- Touching down. Distinct from itemEvents.landed further below, which
	-- is the item roulette settling — same word, unrelated event.
	if events.landed then
		haptics:Punch(HAP.LandPunch)
	end
	if events.boostFired then
		effects:Boost(events.boostFired)
		audio:Boost(events.boostFired)
		camera:BoostPunch(events.boostFired)
	end

	-- The one nitro cue: a bar filling. Pitch rises with how many you
	-- now hold, so three fills read as an ascending run.
	if events.tankFilled then
		audio:PlayTierNote(math.min(events.tankFilled, 3))
	end
	-- Lighting a stage is the moment that used to be "boost fired".
	if events.nitroStage and events.nitroStage > 0 then
		effects:Boost(events.nitroStage)
		audio:Boost(events.nitroStage)
		camera:BoostPunch(events.nitroStage)
		haptics:Punch(HAP.BoostPunch)
	end

	-- Speed pads. Checked after the step so the overlap test uses the
	-- hitbox where it actually ended up this frame.
	local pad = boosters:Check(sim)
	if pad then
		sim:ApplyBoost(pad.Speed, pad.Duration)
		effects:Boost(pad.Tier)
		audio:Boost(pad.Tier)
		camera:BoostPunch(pad.Tier)
	end

	-- Everything below reacts to driving. A kart held on the starting grid
	-- isn't driving: it can't be stuck, so stuck-detection mustn't run,
	-- and firing an item into the countdown shouldn't be possible.
	-- Simulation ignores the stick while held but Items reads the key
	-- itself, so the guard has to be here.
	if sim.held then
		hud:Update(race)
		-- Cleared explicitly, or an alert left on screen when the round
		-- ended would still be pulsing through the next countdown.
		hud:SetAlert(nil, nil, dt)
		effects:Update(dt, sim)
		audio:Update(dt, sim)
		haptics:Update(dt, sim)
		camera:Update(dt, sim, Input)
		speedo:Update(dt, sim)
		return
	end

	-- Lap triggers, same reasoning: after the move.
	local lapEvents = race:Update(sim)
	if lapEvents.checkpoint then
		audio:PlayTierNote(0) -- soft "do" per checkpoint
	end
	if lapEvents.lapDone then
		audio:PlayTierNote(if lapEvents.finished then 3 else 1)
	end
	if lapEvents.rejected then
		hud:FlashRejected()
	end
	hud:Update(race)

	-- One alert slot, so these are a priority order rather than a pile.
	-- Wrong way outranks scrambled steering: going backwards costs you the
	-- race, whereas inverted steering is survivable and self-explanatory
	-- the moment you touch the stick.
	local alertText, alertColour = nil, nil
	if race:WrongWay(sim, dt) then
		alertText, alertColour = H.WrongWayText, H.WrongWayColor
	elseif sim:IsScrambled() then
		alertText, alertColour = H.ScrambledText, H.ScrambledColor
	end
	hud:SetAlert(alertText, alertColour, dt)

	-- Fell off, drove into a void zone, or asked for a reset.
	local why = respawn:Check(sim, race, Input, dt)
	if why then
		camera:Snap()
		audio:PlayTierNote(0)
	end

	-- Items: pickup, use, and being hit. Racing only — you're free to
	-- roll around between rounds, but not to collect a stack or drop a
	-- mine while the grid is forming. The server enforces this too; this
	-- half is so the HUD and the sounds agree with it.
	local itemEvents = if match:IsRacing() then items:Update(sim, Input) else NO_EVENTS
	-- One click per name the roulette cycles past, then the reveal.
	if itemEvents.ticks then
		audio:PlayTick()
	end
	if itemEvents.landed then
		audio:PlayPickup()
	end
	if itemEvents.used then
		audio:Boost(2)
	end
	-- An item that refused to fire. Lightning and Scramble both need
	-- somebody ahead, so in first place Q did nothing at all and gave no
	-- reason — indistinguishable from a dropped input. The item stays in
	-- your hand; this just says so.
	if itemEvents.failed then
		audio:PlayTick()
	end
	if itemEvents.hit then
		camera:BoostPunch(1)
		haptics:Punch(HAP.HitPunch)
		-- The thump of being spun, plus an item layer over it when there
		-- is one. `item` is only present on hits relayed by the server —
		-- a hazard you drove into names itself through `note` instead.
		audio:PlayHit(itemEvents.hit.item)
		-- Hazards carry their own note so oil and mines sound different
		-- without needing separate sound assets.
		if itemEvents.hit.note then
			audio:PlayTierNote(itemEvents.hit.note)
		end
	end
	if itemEvents.dropped then
		-- Losing the stack needs its own cue, or it reads as a HUD glitch
		-- rather than a consequence.
		audio:PlayTierNote(0)
	end
	if itemEvents.blocked then
		haptics:Punch(HAP.BlockedPunch)
		-- A shield ate it. Different cue, or players can't tell the shield
		-- did anything and it feels like the hit just missed.
		audio:PlayTierNote(3)
	end

	-- Publish progress so every other client can rank the field. Rate
	-- limited: standings only need to be roughly current, and firing a
	-- remote every frame per player is the kind of thing that quietly
	-- eats a server.
	reportAt -= dt
	if reportAt <= 0 then
		reportAt = 0.25
		if progressRemote then
			progressRemote:FireServer(race:ProgressScore(sim))
		end
	end
	itemHud:Update(items:HeldSlots(), race:Place(sim), race:FieldSize())

	effects:Update(dt, sim)
	audio:Update(dt, sim)
	haptics:Update(dt, sim)
	camera:Update(dt, sim, Input)
	speedo:Update(dt, sim)
end

--=====================================================================
--  SEATING
--=====================================================================
local function onSeated(active: boolean, seatPart: BasePart?)
	teardown()

	if not (active and seatPart and seatPart:IsA("VehicleSeat")) then
		return
	end

	local model = seatPart:FindFirstAncestorOfClass("Model")
	local hitbox = model and (model.PrimaryPart or model:FindFirstChild("Hitbox"))
	if not (model and hitbox and hitbox:IsA("BasePart")) then
		warn("[KartClient] No Hitbox found on the seated model.")
		return
	end

	sim = Simulation.new(model, hitbox, seatPart, player.Character)
	effects = Effects.new(hitbox, model)
	audio = Audio.new(hitbox)
	camera = CameraRig.new(sim)
	boosters = Boosters.new()
	items = Items.new(model)

	Input.bind(getHumanoid)
	camera:Engage(seatPart)
	-- Keyboard hints are noise on a phone: the buttons are labelled and
	-- there are no keys to learn.
	if not touch then
		controls:Flash() -- remind them of the keys on getting in
	end
	speedo:SetActive(true)
	if touch then
		touch:SetActive(true)
	end
	heartbeat = RunService.Heartbeat:Connect(step)
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 10)
	if not (h and h:IsA("Humanoid")) then
		return
	end
	humanoid = h
	h.Seated:Connect(onSeated)
	-- Dying while seated never fires Seated(false), so clean up here or
	-- the bindings leak and the camera stays Scriptable after respawn.
	h.Died:Connect(function()
		onSeated(false, nil)
		humanoid = nil
	end)
end

--=====================================================================
--  START
--=====================================================================
-- Before anything queries the world: other racers must be excluded
-- from our collision and ground checks from the very first frame.
-- A pad plugged in mid-session should just start working. Refresh()
-- re-asks what the controller supports; without this, rumble is decided
-- once at join and a player who connects a pad later never gets any.
UserInputService.GamepadConnected:Connect(function()
	haptics:Refresh()
end)
UserInputService.GamepadDisconnected:Connect(function()
	haptics:Stop()
	haptics:Refresh()
end)

WorldFilter.start()

-- Started BEFORE the character handling below, which yields on
-- WaitForChild. The server seats players ~0.2s after they spawn, so
-- anything behind a yield can miss the Seated event entirely.
Rider.start()

-- Item boxes spin whether or not you're driving.
Items.startBoxes()

-- Missiles are drawn locally at full frame rate, whether or not WE fired
-- them — every client renders its own copy of every projectile.
Projectiles.start()

-- Same idea, applied to karts we don't own: the server says where they
-- are, we decide what to draw in between.
RemoteKarts.start()

-- Checkpoint sanity check, once. Delayed rather than immediate: tagged
-- parts stream in with the rest of Workspace, so counting them on the
-- first frame reports a track that looks half-built.
if Config.Race.Debug then
	task.delay(3, function()
		race:Diagnose()
	end)
end

--=====================================================================
--  MATCH  (runs whether or not we're in a kart)
--
--  Its own loop rather than a line in step(): the status line has to
--  say "waiting for racers" before the first kart has ever spawned, and
--  step() returns early when there's no simulation.
--=====================================================================
-- Hits are announced to everyone, so this listens whether or not we're
-- the one who got hit — or did the hitting.
local feedRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.FEED_REMOTE, 10)
if feedRemote then
	feedRemote.OnClientEvent:Connect(function(msg)
		if typeof(msg) == "table" and msg.victim then
			feedHud:Add(tostring(msg.item), msg.by, tostring(msg.victim))
		end
	end)
end

RunService.Heartbeat:Connect(function(dt)
	matchHud:Update(match)
	feedHud:Update()
	-- Outside step() on purpose: the pad has to keep fading after you
	-- leave the kart, and step() returns early once there's no simulation.
	if touch then
		touch:Update(dt)
	end
end)

-- Ready-up. A plain UserInputService binding rather than a
-- ContextAction in Input: those are bound only while driving, and this
-- is a lobby action that has to work between rounds.
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Config.Match.ReadyKey then
		match:SetReady()
	end
end)

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end
