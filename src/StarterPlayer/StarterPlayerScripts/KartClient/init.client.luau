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

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config"))
local Names = require(ReplicatedStorage.BloxKart.Names)
-- The shared match contract (phase names, finish attributes), distinct
-- from script.Match which is the client's mirror of it.
local Shared = require(ReplicatedStorage.BloxKart.Match)
local Place = require(ReplicatedStorage.BloxKart.Place)
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
local Transition = require(script.Transition)
local XpHud = require(script.XpHud)
local Tally = require(script.Tally)
local QuestHud = require(script.QuestHud)
local Minimap = require(script.Minimap)
local RaceHud = require(script.RaceHud)
local LiveStandingsHud = require(script.LiveStandingsHud)
local ControlsHud = require(script.ControlsHud)
local VehicleHud = require(script.VehicleHud)
local QueueHud = require(script.QueueHud)
local MainMenuHud = require(script.MainMenuHud)
local GarageHud = require(script.GarageHud)
local LoadingBar = require(script.LoadingBar)
local SpeedHud = require(script.SpeedHud)
local ItemHud = require(script.ItemHud)
local ThreatHud = require(script.ThreatHud)
local FeedHud = require(script.FeedHud)
local RivalSpotlight = require(script.RivalSpotlight)
local Items = require(script.Items)
-- The shared item CATALOGUE, not the client controller above it. Named
-- apart because both modules are called Items and confusing them is a
-- silent nil rather than an error.
local ItemRegistry = require(ReplicatedStorage.BloxKart.Items)
local Respawn = require(script.Respawn)
local Projectiles = require(script.Projectiles)
local TouchHud = require(script.TouchHud)
local Props = require(script.Props)
local Rider = require(script.Rider)
local RemoteKarts = require(script.RemoteKarts)
local RemoteAudio = require(script.RemoteAudio)
local Crowd = require(script.Crowd)
local Music = require(script.Music)
local Spectate = require(script.Spectate)
local Rainbow = require(script.Rainbow)
local RouteGuide = require(script.RouteGuide)
local IntermissionCamera = require(script.IntermissionCamera)
local GridIntroCamera = require(script.GridIntroCamera)

local H = Config.Hud
local HANDLING = Config.Handling
local IT = Config.Items
local SPEC = Config.Spectate
local HAP = Config.Haptics
local AUDIO = Config.Audio

local player = Players.LocalPlayer
-- The server waits for this one-way acknowledgement before it creates and
-- seats the initial race kart.  It is intentionally sent only after the
-- systems below have installed their listeners, so the first Seated event
-- cannot arrive while the driving client is still half-initialised.
local clientReadyRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.CLIENT_READY_REMOTE, 20)
local kartAttachedRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.KART_ATTACHED_REMOTE, 20)

-- Shared empty events table for the frames a subsystem is skipped.
-- Frozen so a stray write can't turn it into a real event next frame.
local NO_EVENTS = table.freeze({})

local humanoid: Humanoid? = nil
local sim, effects, audio, camera, boosters, items, rainbow = nil, nil, nil, nil, nil, nil, nil
-- `Humanoid.Seated` is normally enough, but can arrive before the rest of a
-- streamed kart does. This prevents a property-change reconciliation from
-- starting a second attach while the first is still waiting for the hitbox.
local attachingModel: Model? = nil
-- Which kart's lobby spawn placement has already been applied. Model
-- IDENTITY, not a flag reset per round the way the grid's is — a lobby
-- kart has no rounds. Falling out and being reseated into the SAME
-- model (bindLockIn) reruns onSeated and must NOT reapply this, or a
-- stumble near your kart teleports you back to where you first called
-- it. A freshly called kart is always a new Model, so this is enough.
local vehicleSpawnAppliedFor: Model? = nil

-- The race outlives any single kart, so it isn't torn down with one.
local race = Race.new()
-- So does the match — it's the thing that decides whether there IS a
-- kart to drive, and its HUD has to show "waiting for racers" before
-- anyone has spawned.
local match = Match.new()
local intermissionCamera = IntermissionCamera.new()
local gridIntroCamera = GridIntroCamera.new()
-- The initial splash is the one thing that can cover an Intermission rail.
-- Tell MatchService only after it has fully wiped away, so the server starts
-- the rail clock when people can see it rather than while they are loading.
local function confirmIntermissionVisible()
	if player:GetAttribute(Names.SPLASH_DISMISSED) == true then
		match:ConfirmIntermissionVisible()
	end
end
player:GetAttributeChangedSignal(Names.SPLASH_DISMISSED):Connect(confirmIntermissionVisible)
confirmIntermissionVisible()
local matchHud = MatchHud.new()
local routeGuide = RouteGuide.new()
local transition = Transition.new()
local transitionRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.TRANSITION_REMOTE, 10)
local returnRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.RETURN_REMOTE, 10)
local xpHud = XpHud.new()
local tally = Tally.new()
-- Longer now that the panel shows in-flight progress itself: the
-- flush is for the SERVER's benefit, not the display's.
local TALLY_FLUSH = 8 -- seconds between partial stat sends
local flushAt = TALLY_FLUSH
-- The incoming warning outlives the threat by IncomingHold so a
-- fraction-of-a-second missile is still readable.
-- THE FINISH SEQUENCE. Crossing the line is a beat, not a cut:
--   banner  →  the kart drives on under a wider camera  →  wipe  →  board
-- `finishAt` is when we crossed; everything else is measured from it.
local finishAt = nil
local finishShown = false

local incomingUntil = 0
local incomingEta = 0
-- The icon of whatever is inbound. A missile today; read from the
-- catalogue so a second homing item needs no change here.
local incomingIcon = nil
-- What last hit us, and for how long to say so.
-- A wind-up item on its way: what it is, and when it lands.
local warnedUntil = 0
local warnedName = nil
local warnedIcon = nil
local mainMenu = nil
local garageHud = nil

-- DEVELOPER OVERRIDE: treat this client as "racing" for item purposes.
--
-- Exists because the two halves of the game disagree (BUGS #29): the
-- SERVER allows items in the lobby and grants them happily, while this
-- client gates `items:Update` on match:IsRacing(), which a lobby can
-- never satisfy. So a granted item lands in a slot and can never be
-- used, which makes the practice ring untestable.
--
-- LOCAL ONLY, AND THAT IS THE WHOLE POINT. It does not touch the server,
-- does not fake a match phase, and changes nothing for anybody else. The
-- server has ALREADY decided items are allowed here — this only unlocks
-- this client's ability to use what it was legitimately given.
--
-- It is therefore not a privilege escalation: an exploiter can flip
-- their own client's local state whenever they like, and the reason that
-- is not a problem is that the server never asked this flag anything.
local devForceRace = false
if transitionRemote then
	transitionRemote.OnClientEvent:Connect(function(action, destination, label)
		if action == "teleportOut" then
			if mainMenu and mainMenu:IsOpen() then
				if destination == "race" and typeof(label) == "string" then
					mainMenu:SetStatus("Sending you to " .. label .. "...")
				elseif destination == "lobby" then
					mainMenu:SetStatus("Returning to lobby...")
				end
			end
			transition:CoverHold()
		elseif action == "release" then
			transition:Release()
		end
	end)
else
	warn("[KartClient] no transition remote — cross-place teleports will not get a hold-cover wipe.")
end
matchHud:SetResultsActions(function()
	-- The round loop returns to Intermission when Results expires. Hiding the
	-- compact board is enough to keep watching the track until then.
end, function()
	if returnRemote then
		returnRemote:FireServer()
	end
end)
local questHud = QuestHud.new(tally)
-- Knockable scenery. Built once and kept for the session: props are
-- world geometry, not per-kart, and they must keep flying through a
-- respawn rather than freezing mid-arc.
local props = Props.new()
local minimap = Minimap.new()
-- Bound directly rather than through Input: this is UI, it must work
-- while spectating and out of a kart, and Input's bindings are released
-- the moment you stop driving.
UserInputService.InputBegan:Connect(function(input, typing)
	if not typing and input.KeyCode == Config.Level.QuestOpenKey and not (mainMenu and mainMenu:IsOpen()) then
		questHud:Toggle()
	end
end)
-- DEVELOPER CONSOLE.
--
-- Asks the SERVER whether this client may have it, and builds nothing at
-- all if the answer is no — so an unauthorized player never loads Iris,
-- never holds the window, and has nothing local to tamper with.
--
-- That is a convenience, not the security boundary. Every command is
-- re-checked server-side whether or not this UI exists, which is the
-- only statement that matters. See docs/developer-console/SECURITY.md.
task.spawn(function()
	local ok, err = pcall(function()
		local DevConsoleClient = require(script.DeveloperConsole.DevConsoleClient)
		local allowed, grantedRole, code = DevConsoleClient.probe()
		-- The server creates console remotes near the end of startup. A
		-- client that wins that race gets a short bounded retry, while a
		-- genuine permission denial stays silent and does not poll.
		for _ = 1, 5 do
			if allowed or (code ~= "UNAVAILABLE" and code ~= "INTERNAL") then
				break
			end
			task.wait(0.5)
			allowed, grantedRole, code = DevConsoleClient.probe()
		end
		if not allowed then
			return
		end
		-- ONE hooks table, shared by the push listener and the console.
		--
		-- These are SETTERS AND READERS, not access. The console submits
		-- an intent and this file — which owns the game wiring — acts on
		-- it. A tab that could reach `sim` or `items` directly would break
		-- the layering the whole console is built on.
		local hooks = {
			-- Local-only race-state override; see devForceRace above.
			setForceRace = function(on: boolean)
				devForceRace = on == true
			end,
			getForceRace = function()
				return devForceRace
			end,
			-- Read-only, for the speed graph. Plots the value this client
			-- is already simulating with, so the graph cannot disagree
			-- with the kart.
			getSpeed = function(): number?
				return sim and math.abs(sim.speed) or nil
			end,
			-- Applied through RespawnAt, the same call the existing
			-- respawn and grid placement use, so the client stays the
			-- SINGLE owner of its kart's position. The server resolved
			-- the destination; this only applies it.
			teleport = function(cf: CFrame)
				if sim then
					sim:RespawnAt(cf)
				end
			end,
		}

		DevConsoleClient.listen(hooks)
		local DevConsoleController = require(script.DeveloperConsole.DevConsoleController)
		DevConsoleController.start(grantedRole or "viewer", Config.DevConsole.Hotkey, hooks)
		print("[DevConsole] ready — press " .. Config.DevConsole.Hotkey.Name .. " to toggle.")
	end)
	if not ok then
		warn("[DevConsole] failed to start: " .. tostring(err))
	end
end)

local hud = RaceHud.new()
local liveStandings = LiveStandingsHud.new()

-- THE LOBBY IS A PLACE YOU DRIVE, NOT A RACE.
--
-- Everything else on the client is either inert without a track (no
-- checkpoints, so no laps; no boxes, so no items) or wanted in the hub
-- anyway — the speedo, the quest panel, the XP toasts, the music.
--
-- These two are the exception: they would draw a lap counter and a
-- countdown for a round that does not exist, and a HUD confidently
-- reporting nothing is worse than no HUD at all.
--
-- Hidden rather than skipped, because a nil hud would mean guarding
-- every one of its call sites for a state that lasts the whole session.
local lobby = Place.isLobby()
if Config.Build.Announce then
	print(("[BloxKart] client %s — %s place"):format(Config.Build.Version, Place.role():upper()))
end
local controls = ControlsHud.new()
local speedo = SpeedHud.new()
local itemHud = ItemHud.new()
local threatHud = ThreatHud.new()

-- THE DRIVING HUD FOLLOWS THE KART, NOT THE PLACE.
--
-- Items, speed and the control list all describe something you are
-- doing right now. On foot you are doing none of it, and a speedometer
-- reading zero beside three empty item slots is not "no information",
-- it is wrong information.
--
-- Keyed on having a kart rather than on being in a lobby, because that
-- is the honest condition: in a race you always have one so it is
-- always up, and in a hub it appears exactly when you call your kart.
-- One rule, both places, nothing to keep in sync.
-- ITEMS ARE THE ONE EXCEPTION, and it is a second condition on purpose.
--
-- Having a kart is the honest test for the speedo and the controls: both
-- are about DRIVING, and you drive in the hub. Items are not. There are
-- no item boxes outside a race, so in the hub the slots are not "empty
-- and waiting", they are empty forever — which is the same wrong
-- information the rule above exists to avoid, just quieter. Three dead
-- boxes also teach a new player that the hub is where items live.
local function setDrivingHud(on: boolean)
	itemHud:SetVisible(on and not lobby)
	-- Same race-only rule, same reason: nobody is racing you in the hub,
	-- so a rear indicator there reports traffic, not threat.
	threatHud:SetVisible(on and not lobby)
	liveStandings:SetVisible(on and not lobby)
	controls:SetVisible(on)
	speedo:SetActive(on)
end

local vehicleHud, queueHud = nil, nil
local function setLobbyPrompts(on: boolean)
	if vehicleHud then
		vehicleHud:SetVisible(on)
	end
	if queueHud then
		queueHud:SetVisible(on)
	end
end

if lobby then
	hud:SetVisible(false)
	matchHud:SetVisible(false)
	questHud:SetVisible(false)
	-- Only in a hub. A race place hands you a kart because a round is
	-- starting, so there is nothing to call for.
	-- "Still loading", without taking the menu away. The splash already
	-- covered the part that must not be seen half-done; this reports the
	-- art still streaming in behind a menu that is fully usable.
	--
	-- Lobby only: in a race place the wipe lands on a track and there is
	-- no menu to be usable underneath it.
	LoadingBar.new():Start()

	vehicleHud = VehicleHud.new()
	queueHud = QueueHud.new()
	setLobbyPrompts(false)
	queueHud:SetResultHandler(function(result, trackName)
		if not mainMenu then
			return
		end
		if result == "pending" then
			mainMenu:SetStatus(if typeof(trackName) == "string" then "Sending you to " .. trackName .. "..." else "Finding you a race...")
		elseif result == "notrack" then
			mainMenu:SetStatus("No configured track yet. Add a real placeId in Config.Places.Tracks.")
		elseif result == "failed" then
			mainMenu:SetStatus("Teleport failed. Try Play Game again in a moment.")
		end
	end)
	mainMenu = MainMenuHud.new({
		onPlay = function()
			if queueHud then
				queueHud:Play()
			end
		end,
		onLobby = function(closeMenu)
			transition:Play(function()
				if typeof(closeMenu) == "function" then
					closeMenu()
				end
				setLobbyPrompts(true)
				questHud:SetVisible(true)
			end)
		end,
		getHumanoid = function()
			return humanoid
		end,
		onCallKart = function()
			if vehicleHud then
				vehicleHud:Toggle()
			end
		end,
		onQuests = function()
			questHud:Toggle()
		end,
		onGarage = function()
			if garageHud then
				garageHud:Open()
				-- The menu chrome steps aside but the menu stays OPEN: the
				-- garage needs its camera lock and its stage kart.
				mainMenu:SetChromeVisible(false)
				mainMenu:SetInspecting(true)
			end
		end,
	})

	-- THE GARAGE. Picking previews on the local stage kart; DONE writes it
	-- to the profile and re-dresses the real kart, CANCEL puts back what
	-- the server last confirmed. Set Config.Garage.Debug to trace the
	-- whole save path, both ends.
	garageHud = GarageHud.new({
		-- ASK THE MENU FIRST. It is the AUTHORITY on which kart is on
		-- screen, and it is the only thing that knows.
		--
		-- `getMenuStage` CLONES ReplicatedStorage.MenuStage into
		-- `_BloxKartMenuStage` and shows that. `workspace.MenuStage` is a
		-- different instance that nothing displays — so an earlier version
		-- of this getter, which searched the workspace first to avoid
		-- "building the stage as a side effect of looking for it", dressed
		-- that one instead. Every single time, because it exists from the
		-- start. The log then reported `preview ready` on a kart nobody
		-- could see, while the real one sat in stock until the garage was
		-- opened — which is when StageKart() finally got called.
		--
		-- Building the stage on demand is not a side effect to avoid. It
		-- is the point: the kart it builds IS the kart being shown, and
		-- this makes the join path and the garage-open path resolve to the
		-- same object rather than two that merely look alike.
		--
		-- The workspace search stays as a fallback for the case the menu
		-- has no template to clone and falls back to workspace.MenuStage
		-- itself, so both ends agree even then.
		getKart = function()
			local kart = mainMenu and mainMenu:StageKart()
			if kart then
				return kart
			end
			local stage = workspace:FindFirstChild("_BloxKartMenuStage") or workspace:FindFirstChild("MenuStage")
			return stage and stage:FindFirstChild("Kart", true)
		end,
		onZoom = function(studs)
			if mainMenu then
				mainMenu:SetZoom(studs)
			end
		end,
		onClose = function()
			if mainMenu then
				mainMenu:SetChromeVisible(true)
				mainMenu:SetInspecting(false)
				mainMenu:ResetView() -- back to the authored framing
			end
		end,
	})

	-- INSPECTION CAMERA — only while the garage owns the screen. The menu's
	-- own framing is authored and must not be scrollable or draggable.
	--
	-- Right-drag orbits (left is left free for the UI underneath), scroll
	-- zooms. Touch drags too, since there is no right button there.
	local orbiting, lastDrag = false, nil
	UserInputService.InputBegan:Connect(function(input, typing)
		if typing or not (garageHud and garageHud:IsOpen()) then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			orbiting = true
			lastDrag = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			orbiting = false
			lastDrag = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input, typing)
		if typing or not (garageHud and garageHud:IsOpen()) then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			mainMenu:Zoom(-input.Position.Z * 1.6)
		elseif
			orbiting
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local at = Vector2.new(input.Position.X, input.Position.Y)
			if lastDrag then
				mainMenu:Orbit(at.X - lastDrag.X, at.Y - lastDrag.Y)
			end
			lastDrag = at
		end
	end)
	-- The lobby's actions live in the menu's top bar now: the bottom key
	-- prompts are hidden (the G/P KEYS still work), MISSIONS is a nav tab so
	-- the floating quest pill would be a duplicate, and the kart button
	-- mirrors the server's CALL KART / PUT AWAY state.
	vehicleHud:SetPromptShown(false)
	queueHud:SetPromptShown(false)
	questHud:SetButtonVisible(false)
	vehicleHud:SetLabelHandler(function(label)
		if mainMenu then
			mainMenu:SetKartLabel(label)
		end
	end)
	-- You arrive on foot, so it starts off. speedo:SetActive(false) is a
	-- no-op here — it is already inactive and the call early-returns —
	-- so the other two are the ones that matter.
	setDrivingHud(false)
	print("[KartClient] LOBBY — race HUD off, kart button on.")
end

if not lobby then
	-- Missions belong in the lobby/results flow. Even the collapsed tab is a
	-- large, non-driving target on a phone and does not earn space over a race.
	questHud:SetVisible(false)
end

local feedHud = FeedHud.new()
local rivalSpotlight = RivalSpotlight.new()
local respawn = Respawn.new()
-- Made once rather than per kart: it holds motor state, not kart state,
-- and rebuilding it on every respawn would drop a rumble mid-decay.
local haptics = Haptics.new()
-- Outlives any kart: the soundtrack shouldn't restart because you
-- respawned.
local music = Music.new()
local crowd = Crowd.new()
-- Mobile only, and nil everywhere else — every call site is guarded, so
-- desktop carries no touch code at all rather than an inert copy of it.
local touch = if TouchHud.wanted() then TouchHud.new() else nil
local heartbeat: RBXScriptConnection? = nil

local function getHumanoid(): Humanoid?
	return humanoid
end

-- Also outlives the kart: you spectate precisely when you no longer
-- have one to drive.
local spectate = Spectate.new(getHumanoid)

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
	if rainbow then
		rainbow:Destroy()
		rainbow = nil
	end
	if camera then
		-- Always restore, even mid-loop, or the player is left stuck in
		-- a Scriptable camera on foot.
		camera:Restore(humanoid)
		camera = nil
	end
	setDrivingHud(false)
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
-- SUB-STEP. DO NOT CLAMP AND THROW THE REST AWAY.
--
-- `Simulation.Step` begins with `dt = math.min(dt, MaxTimestep)`, and
-- MaxTimestep is 1/20. That clamp is right and necessary — a huge frame
-- integrated in one go tunnels the sweep straight through walls. But
-- calling Step ONCE with the raw dt means every frame longer than 50ms
-- silently DISCARDS the excess, and discarded time is lost motion:
--
--     30 fps -> fine, 33ms is under the cap
--     15 fps -> 66ms elapsed, 50ms integrated -> the kart runs at 75% speed
--     10 fps -> 50% speed
--
-- The kart does not stutter, it goes SLOW, smoothly, and the speedometer
-- agrees with it because the simulation genuinely is moving that slowly.
-- Which makes it near-impossible to recognise as a frame-rate problem
-- from the driver's seat — it reads as the handling having been nerfed.
--
-- So a long frame is integrated as SEVERAL capped steps instead of one
-- truncated one. `MaxSubSteps` bounds the catch-up: past that we do
-- deliberately drop time, because trying to fully repay a one-second
-- hitch costs a second of simulation on the very next frame and turns
-- one hitch into a spiral.
--
-- Events merge later-wins. Sub-steps only ever ADD keys they raised, so
-- a `landed` in the first sub-step survives a second that was quiet.
-- The input taps are consumed by the first sub-step, which is correct:
-- one press is one hop however many steps the frame was split into.
local function stepSim(sim, dt: number)
	local cap = HANDLING.MaxTimestep
	if dt <= cap then
		return sim:Step(dt, Input)
	end

	local steps = math.min(math.ceil(dt / cap), HANDLING.MaxSubSteps)
	-- Capped explicitly: once MaxSubSteps is the binding limit, dt/steps
	-- is BIGGER than cap and Step would clamp it right back, which is the
	-- deliberate time-drop above. Saying it here rather than relying on
	-- that clamp keeps the slice honest at the call site.
	local slice = math.min(dt / steps, cap)
	local merged = {}
	for _ = 1, steps do
		for k, v in sim:Step(slice, Input) do
			merged[k] = v
		end
	end
	return merged
end

local function step(dt: number)
	if not sim or sim.seat.Occupant == nil then
		return
	end

	-- HANDED TO THE AI. We finished, the server took the kart over, and
	-- it now owns the hitbox outright.
	--
	-- We must stop simulating it. Our Simulation would carry on writing
	-- CFrames that no longer replicate — so the kart would drive off
	-- normally on OUR screen and be somewhere else entirely for everyone
	-- else, which is the two-authorities failure in its most confusing
	-- form. Spectating takes over the camera from here.
	if sim.model and sim.model:GetAttribute(Names.AI_DRIVEN) then
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
		-- Arm immediately after the local grid teleport, not when the server
		-- later begins 3-2-1. That removes the normal-chase-camera pause
		-- between seeing the player appear and seeing their intro move begin.
		gridIntroCamera:Arm()
	end
	if matchEvents.countdown then
		matchHud:Countdown(matchEvents.countdown)
		audio:CountdownVoice(matchEvents.countdown)
		audio:PlayTierNote(0) -- one beep per light
	end
	if matchEvents.go then
		matchHud:Go()
		audio:CountdownVoice(0)
		audio:Boost(2)
		camera:BoostPunch(1) -- a kick off the line, from the camera only
	end
	if matchEvents.finished then
		audio:Boost(3)
	end

	-- Stepped with the sim so a knocked cone travels with the same frame
	-- the kart moved on. Tolerates a nil sim — the arc must continue
	-- while you are on foot or spectating.

	-- Props run on their OWN Heartbeat, so this only hands over the live
	-- simulation for hit detection. Nothing here can freeze a cone
	-- mid-air any more, which is what the early returns above used to do.
	props:SetSim(sim)

	Input.update(dt)
	local events = stepSim(sim, dt)
	if rainbow then
		rainbow:Update(sim, dt)
	end

	-- Publish OUR steer onto OUR kart so Rider can turn the wheel and the
	-- front tyres. The VehicleSeat never sees a touch player's steering —
	-- the pad feeds Simulation directly — so SteerFloat alone leaves a
	-- mobile driver cornering with the wheel dead straight. Client-set, so
	-- it stays local; other people's karts fall back to SteerFloat.
	if sim.model then
		sim.model:SetAttribute(Names.STEER, sim.steer)
		-- The raw intent as well. The bike leans on this so the lean
		-- LEADS the turn instead of trailing it; see Simulation.
		sim.model:SetAttribute(Names.STEER_INPUT, sim.steerInput or sim.steer)
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
	tally:Sample(dt, sim)
	-- Flushed on a slow timer as well as at the flag. Deltas, so this
	-- costs nothing but a few remote calls and is the difference between
	-- a bar that moves while you play and one that jumps once at the
	-- end.
	flushAt -= dt
	if flushAt <= 0 then
		flushAt = TALLY_FLUSH
		tally:Flush()
	end
	tally:Drive(events)
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
	-- SPLASH ON A WAVE LANDING, and only that. Simulation reports it
	-- rather than the client inferring it, because "did that landing
	-- happen on water after being thrown by a wave" is three pieces of
	-- state the client would have to reconstruct and could get wrong.
	if events.splashed then
		audio:Splash(events.splashed)
	end

	if events.landed then
		haptics:Punch(HAP.LandPunch)
	end
	-- The camera reacts to the DROP, not to the fact of landing. A drift
	-- hop and a fall off a bridge both raise `landed`; only one of them
	-- should move the camera, and the impact speed is the difference.
	-- THE SMALL CROWD. A landed trick is a routine flourish — worth a
	-- reaction, not worth the big sample. Fired on the LANDING rather
	-- than the launch: a crowd cheers what you pulled off, not what you
	-- attempted.
	if events.trickLanded then
		crowd:Cheer(false)
	end

	if events.bouncedLanding then
		if camera then
			camera:Land(events.bouncedLanding)
		end
		-- The wall bump sound, reused: it is already a bouncy noise, and
		-- a landing bounce and a wall bounce are the same event to the
		-- ear. Scaled the same way, by how hard it was — PlayBump takes a
		-- 0..1 and pitches itself from it.
		audio:PlayBump(math.clamp(events.bouncedLanding / 140, 0.25, 1))
	end
	-- The bike wobbles when something hits it, and ONLY then. Fed from
	-- the same events the camera shake uses, so a wobble can never
	-- appear without a cause the player saw.
	if events.bounced and sim and sim.model then
		Rider.impact(sim.model, Config.Bike.WobbleOnBump * math.clamp(events.bounced, 0, 1))
	end
	if events.wallStunned and sim and sim.model then
		Rider.impact(sim.model, Config.Bike.WobbleOnHit)
	end

	if events.wallStunned and camera then
		camera:WallHit()
	end
	-- Only raised for a square impact, so wall-riding stays silent and a
	-- real crash does not. The value IS how head-on it was, which the
	-- sound uses for its pitch.
	if events.bounced then
		audio:PlayBump(events.bounced)
		haptics:Punch(HAP.LandPunch)
	end
	-- DEAD SINCE DRIFT RELEASE STOPPED FIRING A BOOST. Simulation banks
	-- nitro while you slide and `nitroStage` below drives all of this
	-- when you spend it. Kept only because an item boost could route
	-- through here again; nothing raises it today.
	if events.boostFired then
		effects:Boost(events.boostFired)
		audio:Boost(events.boostFired)
		camera:BoostPunch(events.boostFired)
	end

	-- LEAVING THE GROUND. Ramps and water skips share one sound, pitched
	-- by how big the leap is — see Audio:Leap.
	--
	-- Fired at the LAUNCH, because going up is the moment worth hearing;
	-- the landing already has the bump and the splash.
	--
	-- Both ramp events already existed and nothing consumed them, so this
	-- needed no new plumbing in Simulation.
	if events.trickStarted or events.glideStarted then
		audio:Leap(1)
	elseif events.leaped then
		-- QUIETER AND GATED, because this one fires up to 2.89 times a
		-- second at top speed where a ramp fires once. Small skips stay
		-- silent so only the meatier ones speak.
		if events.leaped >= AUDIO.WaterLeapMinScale then
			local over = (events.leaped - AUDIO.WaterLeapMinScale)
				/ math.max(1 - AUDIO.WaterLeapMinScale, 1e-3)
			audio:Leap(over, AUDIO.WaterLeapVolume)
		end
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
		-- The camera falls behind for a moment. Only on the stage
		-- STARTING, which is what this event is.
		camera:BoostLag(events.nitroStage)
		haptics:Punch(HAP.BoostPunch)
	end

	-- Speed pads. Checked after the step so the overlap test uses the
	-- hitbox where it actually ended up this frame.
	local pad = boosters:Check(sim)
	if pad then
		tally:Pad()
	end
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
	tally:Lap(lapEvents)
	if lapEvents.lapDone then
		audio:PlayTierNote(if lapEvents.finished then 3 else 1)
	end
	hud:Update(race)

	-- One alert slot, so these are a priority order rather than a pile.
	-- Wrong way outranks scrambled steering: going backwards costs you the
	-- race, whereas inverted steering is survivable and self-explanatory
	-- the moment you touch the stick.
	local alertText, alertColour = nil, nil
	local alertUrgency = 0

	-- INCOMING OUTRANKS EVERYTHING. Wrong way and scrambled will both
	-- still be true in a second; a missile will not, and it is the only
	-- one of the three you can still do something about — a shield, or a
	-- corner. It also answers "who do we warn": the missile has a locked
	-- target and the client knows which kart that is, so exactly one
	-- person is told. Two racers side by side do not both get it, and an
	-- alarm that fires when you are not in danger is one people learn to
	-- ignore.
	local alertIcon = nil

	-- A WIND-UP ITEM ALREADY ON ITS WAY outranks a missile still
	-- crossing the map: this one is certain and timed, and the missile
	-- may still miss.
	if warnedName and os.clock() < warnedUntil then
		local left = warnedUntil - os.clock()
		alertText = H.WarnedText:format(warnedName)
		alertColour = H.IncomingColor
		alertIcon = warnedIcon
		-- Counts down to the strike, so the blink arrives with it.
		alertUrgency = 1 - math.clamp(left / math.max(IT.LightningWindUp, 0.01), 0, 1)
	end

	local eta = if alertText then nil else Projectiles.threatTo(sim.model)
	if eta and eta <= H.IncomingLead then
		-- HELD, so a threat that exists for two frames is still seen. A
		-- missile fired from close behind closes in a fraction of a
		-- second, and a warning that appears and vanishes inside that is
		-- indistinguishable from one that never fired.
		incomingUntil = math.max(incomingUntil, os.clock() + H.IncomingHold)
		incomingEta = eta
		local missile = ItemRegistry.byId("Missile")
		incomingIcon = if missile then missile.Icon else nil
	end

	if alertText then
		-- already claimed by the wind-up warning above
	elseif os.clock() < incomingUntil then
		alertText, alertColour = H.IncomingText, H.IncomingColor
		alertIcon = incomingIcon
		-- Counts down from whatever the last real reading was, so the
		-- held tail keeps escalating rather than freezing mid-blink.
		incomingEta = math.max(incomingEta - dt, 0)
		alertUrgency = 1 - math.clamp(incomingEta / H.IncomingLead, 0, 1)
	elseif race:WrongWay(sim, dt) then
		-- NAME THE GATE THEY STILL OWE.
		--
		-- "WRONG WAY" alone says you're facing the wrong direction. It
		-- does not say that the lap you're driving has already stopped
		-- counting, which is the part that actually costs you the race —
		-- and a lap silently not counting is the single most confusing
		-- thing this game can do to somebody.
		--
		-- Missing a gate is meant to be recoverable, so the message has
		-- to say what to recover.
		-- No gate is "owed" any more — checkpoints stopped gating laps, so
		-- naming one would send the player back for something that was
		-- never going to stop them finishing. Turning round is the whole
		-- instruction.
		alertText = H.WrongWayText
		alertColour = H.WrongWayColor
	elseif sim:IsScrambled() then
		alertText, alertColour = H.ScrambledText, H.ScrambledColor
		-- Counts DOWN: slow while you are stuck with it, hurrying as it
		-- is about to let go, so the blink tells you when to expect your
		-- steering back.
		alertUrgency = 1 - sim:ScrambleFrac()
	end
	hud:SetAlert(alertText, alertColour, dt, alertUrgency, alertIcon)

	-- Fell off, drove into a void zone, or asked for a reset.
	local why = respawn:Check(sim, race, Input, dt)
	if why then
		tally:Respawned()
	end
	if why then
		camera:Snap()
		audio:PlayTierNote(0)
	end

	-- Items are live during Racing and in the lobby practice ring, but not
	-- while a race grid is forming. The server follows the same policy;
	-- keeping this client gate aligned prevents a legitimate lobby pickup
	-- from spinning forever in an unusable slot.
	-- A finish is final before the server's takeover attribute has necessarily
	-- replicated back. Stop reading item input on this frame as well, so a
	-- last-moment button press cannot fire after the official time is banked.
	local finished = race.finished or sim.model:GetAttribute(Shared.FINISH_PLACE) ~= nil
	local itemEvents = if (match:IsRacing() or lobby or devForceRace) and not finished then items:Update(sim, Input) else NO_EVENTS
	-- One click per name the roulette cycles past, then the reveal.
	tally:Items(itemEvents)
	if itemEvents.ticks then
		audio:PlayTick()
	end
	if itemEvents.landed then
		audio:PlayPickup()
	end
	if itemEvents.used then
		audio:Boost(2)
		if itemEvents.throwForward then
			Rider.Throw(sim.model)
		end
	end
	-- An item that refused to fire. Lightning and Scramble both need
	-- somebody ahead, so in first place Q did nothing at all and gave no
	-- reason — indistinguishable from a dropped input. The item stays in
	-- your hand; this just says so.
	if itemEvents.failed then
		audio:PlayTick()
	end
	if itemEvents.warned then
		-- Something with a wind-up is on its way. Named and iconed,
		-- because "you are about to be struck by Lightning" is a
		-- different thing to know than "something is coming".
		local def = ItemRegistry.byId(itemEvents.warned.item)
		warnedName = string.upper(if def then def.Name else tostring(itemEvents.warned.item))
		warnedIcon = if def then def.Icon else nil
		warnedUntil = os.clock() + (itemEvents.warned.in_ or 0)
	end

	if itemEvents.hit then
		camera:BoostPunch(1)
		haptics:Punch(HAP.HitPunch)
		-- The wind-up warning has done its job; stop saying it is coming.
		--
		-- Nothing replaces it. A "HIT BY" line used to go here, added
		-- when Lightning could arrive with no visible cause — and the
		-- wind-up warning now names Lightning BEFORE it lands, which is
		-- the same information a second earlier and actually useful.
		-- Everything else already announces itself: you saw the missile,
		-- you drove into the hazard, or your steering inverted and the
		-- alert slot says so. Saying it again afterwards was a third
		-- thing on screen describing an event the player had just
		-- experienced.
		warnedUntil = 0

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

	-- Standings are server-projected from each live kart's route position.
	-- There is deliberately no client progress report here: even a clamped
	-- client lap bank was an authority seam that could be forged.
	itemHud:Update(items:HeldSlots())
	liveStandings:SetMyPlace(race:Place(sim), race:FieldSize(sim))

	-- The rear strip runs off the SAME held reading the INCOMING banner
	-- uses, not a second call to threatTo. Two readers asking the same
	-- question separately is how the banner and the strip end up
	-- disagreeing about whether you are being shot at — and the hold is
	-- the whole reason a brief threat is visible at all.
	threatHud:Update(sim, if os.clock() < incomingUntil then incomingEta else nil, dt)

	effects:Update(dt, sim)
	audio:Update(dt, sim)
	haptics:Update(dt, sim)
	camera:Update(dt, sim, Input)
	speedo:Update(dt, sim)
end

--=====================================================================
--  SEATING
--=====================================================================
local function waitForHitbox(model: Model): BasePart?
	local hitbox = model.PrimaryPart or model:FindFirstChild("Hitbox")
	if hitbox and hitbox:IsA("BasePart") then
		return hitbox
	end

	-- The server deliberately gives the client a full attachment window. Match
	-- that window here: a slow initial replication must not turn a healthy
	-- seated player into an inert kart just because the hitbox took >2 seconds.
	local found = model:WaitForChild("Hitbox", 8)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

local function waitForVehicleSpawnCf(model: Model): CFrame?
	local spawnCf = model:GetAttribute(Names.VEHICLE_SPAWN_CF)
	if typeof(spawnCf) == "CFrame" then
		return spawnCf
	end
	if not lobby then
		return nil
	end

	local started = os.clock()
	while model.Parent and os.clock() - started < 1 do
		task.wait()
		spawnCf = model:GetAttribute(Names.VEHICLE_SPAWN_CF)
		if typeof(spawnCf) == "CFrame" then
			return spawnCf
		end
	end
	return nil
end

local function onSeated(active: boolean, seatPart: BasePart?)
	if not (active and seatPart and seatPart:IsA("VehicleSeat")) then
		attachingModel = nil
		teardown()
		return
	end

	local model = seatPart:FindFirstAncestorOfClass("Model")
	if sim and sim.model == model then
		return -- duplicate Seated/SeatPart notification for the same kart
	end
	if not model or attachingModel == model then
		return
	end
	attachingModel = model
	teardown()

	local hitbox = model and waitForHitbox(model)
	if not (model and hitbox and hitbox:IsA("BasePart")) then
		warn("[KartClient] No Hitbox found on the seated model.")
		attachingModel = nil
		return
	end

	local spawnCf = if model ~= vehicleSpawnAppliedFor then waitForVehicleSpawnCf(model) else nil
	-- THE VEHICLE'S OWN HANDLING. Looked up from the replicated kind
	-- rather than sent as numbers: Config.Vehicles is shared, so both
	-- ends resolve the same table and there is no second copy to drift.
	local kind = model:GetAttribute(Names.VEHICLE_KIND)
	local vehicle = Config.Vehicles.Kinds[if type(kind) == "string" then kind else Config.Vehicles.Default]
	sim = Simulation.new(model, hitbox, seatPart, player.Character, vehicle and vehicle.handling)

	-- A LOBBY KART SPAWNS WHERE YOU WERE STANDING, NOT WHERE IT WAS BUILT.
	--
	-- PlayerVehicleService stamps this rather than moving the part itself
	-- — a server PivotTo on a kart with a seated player loses the race to
	-- the client's OWN Simulation construction above, which just read
	-- hitbox.CFrame as of whenever the client happened to observe it. See
	-- PlayerVehicleService for the full account; this is the other half.
	--
	-- Applied once per MODEL, matching how the grid's own CFrame
	-- attribute is consumed once per round — the attribute is left in
	-- place rather than cleared, and it is this check, not the server,
	-- that decides whether it still needs acting on.
	if model ~= vehicleSpawnAppliedFor then
		if typeof(spawnCf) == "CFrame" then
			sim:RespawnAt(spawnCf)
		end
		vehicleSpawnAppliedFor = model
	end

	effects = Effects.new(hitbox, model)
	audio = Audio.new(hitbox)
	camera = CameraRig.new(sim)
	boosters = Boosters.new()
	items = Items.new(model)
	rainbow = Rainbow.new(model)

	-- This is a lifecycle acknowledgement, not a movement request. The server
	-- validates that this is our currently owned, actually occupied kart before
	-- it marks the join as drive-ready and lets the splash reveal the race.
	if kartAttachedRemote and kartAttachedRemote:IsA("RemoteEvent") then
		kartAttachedRemote:FireServer(model)
	end
	attachingModel = nil

	Input.bind(getHumanoid)
	camera:Engage(seatPart)
	-- Keyboard hints are noise on a phone: the buttons are labelled and
	-- there are no keys to learn.
	if not touch then
		controls:Flash() -- remind them of the keys on getting in
	end
	setDrivingHud(true)
	if touch and UserInputService:GetLastInputType().Name:sub(1, 7) ~= "Gamepad" then
		touch:SetActive(true)
	end
	heartbeat = RunService.Heartbeat:Connect(step)
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 10)
	if not (h and h:IsA("Humanoid")) then
		return
	end
	if character ~= player.Character then
		return
	end
	humanoid = h
	h.Seated:Connect(onSeated)
	-- A networked seat can become occupied before this LocalScript observes the
	-- Seated signal. Reconcile the state as well as listening for transitions;
	-- this is the recovery path that makes the first race kart reliable.
	local function reconcileSeat()
		local seatPart = h.SeatPart
		if h.Sit and seatPart and seatPart:IsA("VehicleSeat") then
			onSeated(true, seatPart)
		end
	end
	h:GetPropertyChangedSignal("SeatPart"):Connect(reconcileSeat)
	task.defer(reconcileSeat)
	-- Dying while seated never fires Seated(false), so clean up here or
	-- the bindings leak and the camera stays Scriptable after respawn.
	h.Died:Connect(function()
		onSeated(false, nil)
		humanoid = nil
	end)
end

local characterHandlingStarted = false
local function startCharacterHandling()
	if characterHandlingStarted then
		return
	end
	characterHandlingStarted = true

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- Bind Humanoid.Seated as soon as onCharacter exists. Lobby kart calls can
-- seat the player before the rest of client startup reaches the music/update
-- loop, which used to make the first kart spawn look attached but inert.
startCharacterHandling()

-- Server-side attach retry. This is intentionally idempotent: if the normal
-- Seated path already built Simulation it simply acknowledges that same kart;
-- if the event was missed, reconciling the current seat builds it first.
if kartAttachedRemote and kartAttachedRemote:IsA("RemoteEvent") then
	kartAttachedRemote.OnClientEvent:Connect(function(model)
		if typeof(model) ~= "Instance" or not model:IsA("Model") then
			return
		end
		local h = humanoid
		local seatPart = h and h.SeatPart
		if h and h.Sit and seatPart and seatPart:IsA("VehicleSeat") and seatPart:IsDescendantOf(model) then
			onSeated(true, seatPart)
			if sim and sim.model == model then
				kartAttachedRemote:FireServer(model)
			end
		end
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
UserInputService.GamepadConnected:Connect(function(pad)
	haptics:Refresh(pad)
end)
UserInputService.GamepadDisconnected:Connect(function()
	haptics:Stop()
	haptics:Refresh()
end)
UserInputService.LastInputTypeChanged:Connect(function(inputType)
	haptics:UseGamepad(inputType)
	-- A touch-capable tablet can still be played with a controller. Do not
	-- leave its custom touch pad active: it disables PlayerModule and would
	-- otherwise take the controller's VehicleSeat movement with it.
	if touch and sim then
		if inputType.Name:sub(1, 7) == "Gamepad" then
			touch:SetActive(false)
		elseif inputType == Enum.UserInputType.Touch then
			touch:SetActive(true)
		end
	end
end)

WorldFilter.start()

-- Character handling already started above, so this can boot without putting
-- Seated behind another startup yield.
Rider.start(function(kart: Model)
	-- Rider has already waited for the rig to replicate before calling us.
	-- Do not touch a stale or another player's model: Simulation is the only
	-- writer for our current kart's position, and Race owns the last known
	-- good checkpoint.
	if not (sim and sim.model == kart) then
		return
	end
	local target = race:RespawnCFrame() or sim.spawnCF
	if target then
		warn("[KartClient] local kart rig stayed incomplete; returning to the last checkpoint.")
		sim:RespawnAt(target + target.UpVector * Config.Respawn.RespawnLift)
	end
end)

-- Item boxes spin whether or not you're driving.
Items.startBoxes()

-- Missiles are drawn locally at full frame rate, whether or not WE fired
-- them — every client renders its own copy of every projectile.
Projectiles.start()

-- Same idea, applied to karts we don't own: the server says where they
-- are, we decide what to draw in between.
RemoteKarts.start()

-- Everyone else's engines and tyres, worked out from how their karts
-- move. Without it a race is silent except for your own kart.
RemoteAudio.start()

	-- Do not acknowledge client setup until the server has finished creating
	-- the shared race services/remotes. This prevents each client module from
	-- independently winning a startup race and falling through its timeout.
	local serverReadyDeadline = os.clock() + 10
	while not ReplicatedStorage.BloxKart:GetAttribute(Names.SERVER_READY) and os.clock() < serverReadyDeadline do
		task.wait(0.05)
	end
	if clientReadyRemote and clientReadyRemote:IsA("RemoteEvent") then
		clientReadyRemote:FireServer()
else
	warn("[KartClient] client-ready remote unavailable; server will use its spawn fallback.")
end

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
-- What the client cannot work out for itself: XP and level live on the
-- server. Standings it already rebuilds from replicated attributes, so
-- they are deliberately not sent — one board, described once.
--
-- Held rather than shown on arrival. It lands as the flag drops and the
-- panel opens a moment later; showing it here would race the phase.
-- XP as it lands, not ten laps later on the results screen.
local xpRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.XP_REMOTE, 10)
if xpRemote then
	xpRemote.OnClientEvent:Connect(function(info)
		xpHud:Award(info)
	end)
end

-- THE BOARD, from whichever source has it.
--
-- The server's wins outright when it has arrived: karts retire a few
-- seconds after finishing, so by the flag the early finishers have left
-- the world and anything rebuilt from live karts is missing exactly the
-- racers who did best. preview() survives as the fallback, and it is
-- what the FINISH shot uses — at that moment the server has not sent
-- anything yet, and a provisional board over your own finish is right.
--=====================================================================
--  THE HORN
--
--  Played LOCALLY the instant it is pressed and relayed separately, so
--  it never feels like it lagged for the one person guaranteed to be
--  listening for it. The server rebroadcasts to everybody else and does
--  NOT echo it back, or the presser would hear it twice a round-trip
--  apart.
--
--  Audio:Horn owns the cooldown and reports whether it actually
--  sounded, so a swallowed press costs no network message either.
--=====================================================================
local hornRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.HORN_REMOTE, 10)

local function onHorn(_action, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if audio and audio:Horn() and hornRemote then
		hornRemote:FireServer()
	end
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("KartHorn", onHorn, false, table.unpack(Config.Audio.HornKeys))

if hornRemote then
	hornRemote.OnClientEvent:Connect(function(who: Player)
		-- Find the honker's kart by owner. Nothing to play it at means
		-- they are not driving, which is not an error.
		if typeof(who) ~= "Instance" or not who:IsA("Player") then
			return
		end
		for _, kart in CollectionService:GetTagged("Kart") do
			if kart:GetAttribute(Names.OWNER) == who.UserId then
				RemoteAudio.playHorn(kart)
				break
			end
		end
	end)
end

local feedRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.FEED_REMOTE, 10)
if feedRemote then
	feedRemote.OnClientEvent:Connect(function(msg)
	if typeof(msg) == "table" and msg.victim then
			feedHud:Add(tostring(msg.item), msg.by, tostring(msg.victim), msg.icon)
			if msg.victimUserId == player.UserId then
				rivalSpotlight:Show({
					kind = "hit",
					item = msg.item,
					opponent = { name = msg.by or "Track hazard", userId = msg.byUserId },
				})
			end
			-- And hear it. The feed already reached us with everything
			-- needed; it was only ever drawing the line.
			RemoteAudio.playHit(msg.kart, msg.id)
			-- THE BIG CROWD. A hit landing is the spectacle the feed
			-- exists to announce, so it is the moment worth the larger
			-- sample. Rate-limited inside Cheer, which matters here
			-- because a pile-up raises several of these at once.
			crowd:Cheer(true)
		end
	end)
end

local rivalRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.OVERTAKE_REMOTE, 10)
if rivalRemote then
	rivalRemote.OnClientEvent:Connect(function(message)
		rivalSpotlight:Show(message)
	end)
end

local liveStandingsRemote = ReplicatedStorage.BloxKart:WaitForChild(Names.LIVE_STANDINGS_REMOTE, 10)
if liveStandingsRemote and liveStandingsRemote:IsA("RemoteEvent") then
	liveStandingsRemote.OnClientEvent:Connect(function(entries)
		liveStandings:Update(entries)
	end)
	-- RemoteEvents do not replay a broadcast that happened while this client
	-- was loading, so ask once for the current compact snapshot.
	liveStandingsRemote:FireServer()
end

-- Gamepad sticks HOLD a value rather than reporting movement, so they
-- are stored here and integrated each frame. Touch is scaled to land in
-- the same range as a mouse delta.
local padLook = Vector2.zero
local padMove = Vector2.zero
local TOUCH_LOOK = 1.4
local PAD_LOOK_RATE = 320 -- pixels-equivalent per second at full stick

-- SPECTATOR INPUT. Plain UserInputService for the same reason as
-- ready-up below: ContextActions are bound only while driving, and
-- spectating is by definition what you do when you aren't.
--
-- Every binding checks IsActive() first, so none of it does anything
-- while you still have a race to drive.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not spectate:IsActive() then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.E or key == Enum.KeyCode.Right or key == Enum.KeyCode.ButtonR1 then
		spectate:Next()
	elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.Left or key == Enum.KeyCode.ButtonL1 then
		spectate:Prev()
	elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonY then
		spectate:ToggleFree()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		spectate:SetLooking(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		spectate:SetLooking(false)
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not spectate:IsActive() then
		return
	end
	local kind = input.UserInputType

	-- LOOK IS NOT GATED ON `processed`, deliberately.
	--
	-- Moving the pointer across the results board marks the event as
	-- processed, and gating on it meant look died the moment the cursor
	-- crossed the one piece of UI that is always on screen while
	-- spectating. Nothing else competes for a look delta, so there is
	-- nothing here to protect.
	if kind == Enum.UserInputType.MouseMovement then
		if spectate:IsLooking() then
			spectate:Look(Vector2.new(input.Delta.X, input.Delta.Y))
		end
	elseif kind == Enum.UserInputType.Touch then
		-- Touch drag anywhere is a look. There is no right button on a
		-- phone, so without this a mobile spectator could not turn the
		-- camera at all — in either mode.
		spectate:Look(Vector2.new(input.Delta.X, input.Delta.Y) * TOUCH_LOOK)
	elseif kind == Enum.UserInputType.MouseWheel then
		if not processed then
			spectate:Zoom(input.Position.Z)
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		-- Gamepad look, scaled to feel like a mouse rather than to match
		-- its raw units. Stored rather than applied: a stick HOLDS a
		-- value, so it has to be integrated every frame, where a mouse
		-- delta is already per-frame movement.
		padLook = Vector2.new(input.Position.X, -input.Position.Y)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
		padMove = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

-- Free-cam movement, polled rather than event-driven: holding a key is a
-- state, and reading it once a frame is simpler than tracking presses
-- and releases for six keys.
local function readSpectateMove(): Vector3
	if not spectate:IsFree() then
		return Vector3.zero
	end
	-- Gamepad stick first: on a controller there are no WASD keys to
	-- read, and a free cam you can only fly with a keyboard is a free cam
	-- half the players cannot use.
	local v = Vector3.new(padMove.X, 0, -padMove.Y)
	if v.Magnitude < 0.15 then
		v = Vector3.zero -- stick deadzone
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		v += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		v += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		v += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		v += Vector3.new(1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		v += Vector3.new(0, 1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		v += Vector3.new(0, -1, 0)
	end
	return if v.Magnitude > 1e-3 then v.Unit else v
end

-- The reward panel owns the Results phase, and MatchHud's plain board
-- stands down while it is up. Two boards describing the same finish is
-- the same question answered in two places, and the reason the simple
-- one survives at all is that it is the fallback if the panel is ever
-- suppressed.
-- The board your own finish puts up, and the one the flag puts up, are
-- SEPARATE EVENTS. One flag for both meant an early finisher never saw
-- the final standings.

-- EVERY PHASE CHANGE THAT MOVES THE PLAYER OR THE SCREEN GOES BEHIND THE
-- WIPE. There are three, and they are all cuts:
--
--   → Grid     everyone is teleported onto the start line
--   → Results  the panel opens over the world
--   Results →  the panel closes and racing resumes
--
-- Driven off the phase the client already tracks rather than a new
-- message from the server. A transition is presentation, and the client
-- can see the phase change perfectly well on its own.
local lastPhase = nil
local gridWiped = false

RunService.Heartbeat:Connect(function(dt)
	local phase = match:Phase()
	-- This runs after the driving step, deliberately overriding the chase
	-- camera during Intermission only. At Grid the authored shot releases,
	-- then the normal camera snaps to the kart's confirmed grid position.
	intermissionCamera:Update(
		dt,
		phase == Shared.Phase.Intermission and player:GetAttribute(Names.SPLASH_DISMISSED) == true
	)
	-- It is armed on the exact local grid teleport above, so this begins as
	-- soon as OUR kart is ready rather than waiting through other players'
	-- loading barrier.
	gridIntroCamera:Update(dt, phase == Shared.Phase.Grid, sim)
	-- Visual guide only. Every client draws the same authored BotPath, but
	-- this module never writes input, kart state, race progress, or AI.
	routeGuide:Update(phase == Shared.Phase.Racing)

	----------------------------------------------------------------
	-- CROSSING THE LINE
	--
	-- Watched here rather than off a lap event, because the finish is
	-- the SERVER's call — it decides the place — and the attribute
	-- landing is the only moment that is true on this client.
	----------------------------------------------------------------
	local mineNow = sim and sim.model
	local myPlace = mineNow and mineNow:GetAttribute(Shared.FINISH_PLACE)
	if myPlace and not finishAt then
		finishAt = os.clock()
		matchHud:Finish(myPlace)
		-- Swing out and orbit. The kart is already the AI's by now, so
		-- there is nothing to take control away from.
		spectate:BeginFinish(mineNow)
	end

	-- The finish shot ends naturally in spectate. Final standings belong
	-- solely to the server Results phase, never to an individual finish.
	if finishAt and not finishShown and os.clock() >= finishAt + SPEC.FinishHold then
		finishShown = true
		spectate:EndFinish()
	end

	if phase ~= lastPhase then
		local was = lastPhase
		lastPhase = phase

		-- A new round: forget the last one's finish.
		if phase == Shared.Phase.Grid then
			finishAt, finishShown = nil, false
			spectate:EndFinish()
		end

		-- Armed once per round, on the way INTO the countdown. Reset
		-- inside the per-frame branch instead and it re-arms on the
		-- frame after it fires, which is a wipe every frame until the
		-- lights go out.
		if phase == Shared.Phase.Intermission or phase == Shared.Phase.Waiting then
			gridWiped = false
		end

		-- The race's driving counters: cleared on the way to the grid,
		-- sent once at the flag. Sent on the PHASE rather than on our own
		-- finish, so a racer who never crossed the line still reports the
		-- laps and drifts they did manage.
		if phase == Shared.Phase.Grid then
			tally:Reset()
		elseif phase == Shared.Phase.Results then
			tally:Send()
		end

		-- Not on the first frame: `was == nil` is joining the server, and
		-- wiping the screen at someone who has only just arrived hides
		-- the game from them for no reason.
		--
		-- The grid wipe is normally started a moment EARLIER, off the
		-- intermission clock below. This is the backstop for the case
		-- that cannot be predicted — everyone readying up skips the rest
		-- of the countdown, so the teleport arrives without warning.
		if was ~= nil and phase == Shared.Phase.Grid and not gridWiped then
			gridWiped = true
			transition:Play()
		elseif was == Shared.Phase.Results then
			-- Results is an overlay, not a spatial cut. Cleanup is immediate
			-- so a busy grid wipe can never leave stale UI behind.
			finishAt, finishShown = nil, false
		end
	end

	-- COVER THE TELEPORT, DON'T CHASE IT.
	--
	-- Everyone is moved onto the start line as Grid begins, so a wipe
	-- triggered BY that phase change starts a frame after the cut it was
	-- meant to hide — the player sees the teleport, then the wipe, which
	-- is the wrong order and looks like a stutter rather than a
	-- transition.
	--
	-- The intermission clock is already on the client, so the band is
	-- launched to land exactly as the teleport does.
	if phase == Shared.Phase.Intermission then
		if not gridWiped and match:TimeLeft() <= Config.Rewards.WipeTime and not transition.busy then
			gridWiped = true
			transition:Play()
		end
	end

	matchHud:Update(match)
	feedHud:Update()
	rivalSpotlight:Update()
	xpHud:Update()
	if mainMenu and mainMenu:IsOpen() then
		music:Update(dt, match:Phase())
		crowd:Update(dt, match:Phase())
		return
	end
	-- OUTSIDE step(), which returns early the moment there is no
	-- simulation — finishing, spectating, or between rounds. Left in
	-- there the streaks and the blur would freeze at whatever intensity
	-- the last frame of the race had and stay on the screen. `sim` is
	-- nil in all those cases, which reads as zero and decays out.
	-- Outside step() because the map should keep showing the race while
	-- you spectate it, and step() returns the moment there is no kart.
	minimap:Update(dt, sim)
	questHud:Update()
	-- Lobby only, and nil everywhere else. Here rather than in step()
	-- for the same reason as the music: in a hub there is usually no
	-- kart at all, and step() returns the moment that is true — which
	-- is exactly when the button that calls one has to work.
	if vehicleHud then
		vehicleHud:Update(dt)
		queueHud:Update(dt)
	end
	-- Here rather than in step() because the soundtrack has to play in
	-- the lobby, and step() returns early whenever there is no kart.
	music:Update(dt, match:Phase())
	crowd:Update(dt, match:Phase())

	-- Spectating, once our own kart has crossed the line. Here rather
	-- than in step() because step() returns early the moment the AI takes
	-- the kart over, which is the exact instant this has to start.
	local mine = sim and sim.model
	-- WATCHING, not driving. True once you have finished — and also for
	-- everybody at the flag, because by then the AI has taken every kart
	-- and there is nothing left to steer.
	--
	-- Without the second half, a racer who never crossed the line kept a
	-- camera bolted to their own parked kart while the board covered it:
	-- a still photograph behind a results screen.
	local done = (mine ~= nil and mine:GetAttribute(Shared.FINISH_PLACE) ~= nil)
		or match:Phase() == Shared.Phase.Results
	-- Stick look is applied here, per frame, because a held stick is a
	-- rate and not a delta.
	if spectate:IsActive() and padLook.Magnitude > 0.15 then
		spectate:Look(padLook * PAD_LOOK_RATE * dt)
	end
	spectate:Update(dt, match:Phase(), done, readSpectateMove())
	matchHud:SetSpectating(spectate:StatusText())
	-- MatchHud is the sole lightweight results presentation.
	matchHud:SuppressResults(false)
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
	if not processed and input.KeyCode == Config.Match.ReadyKey and not (mainMenu and mainMenu:IsOpen()) then
		match:SetReady()
	end
end)
