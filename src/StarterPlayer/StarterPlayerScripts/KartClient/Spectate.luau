--[[
	Spectate — watching once you're out of the race.

	TWO MODES, and they answer different questions:

	  FOLLOW  orbit a racer who is still fighting for a place. Cycle
	          between them. This is what you want 95% of the time.
	  FREE    fly the camera anywhere. For looking at the track, watching
	          a corner rather than a driver, or getting a shot.

	WHY THE FIRST VERSION WAS BUGGY, since it's instructive:

	  It tracked its subject by INDEX into a list re-sorted by race
	  position every frame. Positions change constantly, so the index
	  pointed at a different kart from one frame to the next and cycling
	  landed somewhere arbitrary. It now holds the Model and cycles by
	  finding that model's place in a STABLE order.

	  It also stopped dead the moment the phase left Racing, so the
	  results screen — the part you most want to watch the end of — cut
	  back to a camera pointed at your own parked kart.

	  And with nobody left to watch it simply froze, still Scriptable,
	  with no way out.

	CAMERA OWNERSHIP
	----------------
	Takes the camera outright while active and gives it back exactly as
	found. It deliberately does not go through CameraRig: that is built
	around a Simulation it can read every frame, and a kart somebody else
	drives gives us nothing but a CFrame.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Shared = require(BloxKart:WaitForChild("Match"))
local Standings = require(BloxKart:WaitForChild("Standings"))
local Input = require(script.Parent.Input)

local SP = Config.Spectate
local P = Shared.Phase

local Spectate = {}
Spectate.__index = Spectate

-- `humanoidGetter` is handed straight back to Input.bind when spectating
-- ends, because that is what it wants and this module has no other use
-- for it.
function Spectate.new(humanoidGetter)
	return setmetatable({
		humanoidGetter = humanoidGetter,
		active = false,
		free = false,
		-- The kart itself, never an index. See the header.
		target = nil :: Model?,
		pos = nil :: Vector3?,
		-- The point the camera aims at, smoothed separately from where
		-- the camera IS. See Update for why both are needed.
		focus = nil :: Vector3?,
		yaw = 0,
		pitch = math.rad(-12),
		dist = SP.Distance,
		-- Free-cam state, kept separate so switching modes and back
		-- returns you where you were rather than snapping.
		freePos = nil :: Vector3?,
		saved = nil :: Enum.CameraType?,
		looking = false,
	}, Spectate)
end

--=====================================================================
--  WHO THERE IS TO WATCH
--
--  Sorted by NAME, not by race position. Position changes every frame,
--  and a cycle order that reshuffles under you sends "next" somewhere
--  unpredictable — which was most of what made the first version feel
--  broken.
--=====================================================================
local function candidates(): { Model }
	local out = {}
	for _, kart in Standings.allKarts() do
		if kart:GetAttribute(Names.OWNER) == Players.LocalPlayer.UserId then
			continue -- your own kart isn't spectating, it's the game you just played
		end
		table.insert(out, kart)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

-- Still racing, so worth defaulting to.
local function racing(kart: Model): boolean
	return kart:GetAttribute(Shared.FINISH_PLACE) == nil
end

function Spectate:_cycle(step: number)
	local list = candidates()
	if #list == 0 then
		self.target = nil
		return
	end
	local at = 0
	for i, kart in list do
		if kart == self.target then
			at = i
			break
		end
	end
	self.target = list[(at + step - 1) % #list + 1]
	self.pos, self.focus = nil, nil -- cut rather than sweep across the map
end

-- Prefer somebody still in the race; fall back to anyone at all so the
-- camera always has a subject rather than freezing.
function Spectate:_pickBest()
	local list = candidates()
	for _, kart in list do
		if racing(kart) then
			self.target = kart
			self.pos, self.focus = nil, nil
			return
		end
	end
	self.target = list[1]
	self.pos, self.focus = nil, nil
end

--=====================================================================
--  MODE
--=====================================================================
function Spectate:_start()
	self.active = true

	-- RELEASE THE DRIVING CONTROLS.
	--
	-- This is what made switching and free look "not work", and neither
	-- was a bug in this module: the driving bindings were still live.
	-- ContextActionService sinks what it binds, so every key spectating
	-- wanted was already taken —
	--
	--   E            exit           swallowed "next racer"
	--   MouseButton2 free-look      swallowed the orbit
	--   R1 / L1      drift          swallowed the gamepad cycle
	--   ButtonY      exit           swallowed the free-cam toggle
	--
	-- and each arrived at our handler with gameProcessedEvent already
	-- true. Rebinding spectating onto different keys would have worked
	-- and been wrong: you are not driving, so the driving controls have
	-- no business being bound at all. The AI has your kart.
	Input.unbind()
	local cam = workspace.CurrentCamera
	if cam then
		self.saved = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
		-- Start the free cam where the view already is, so toggling into
		-- it never teleports you somewhere disorienting.
		self.freePos = cam.CFrame.Position
	end
	self:_pickBest()
end

function Spectate:_stop()
	-- Driving controls come back with the camera. Guarded on `active` so
	-- a stop that isn't following a start can't bind them from nowhere.
	if self.active then
		Input.bind(self.humanoidGetter)
	end
	self.active = false
	self.free = false
	self.looking = false
	self.target = nil
	self.pos, self.focus = nil, nil
	local cam = workspace.CurrentCamera
	if cam and self.saved then
		cam.CameraType = self.saved
		self.saved = nil
	end
end

function Spectate:Next()
	if self.active and not self.free then
		self:_cycle(1)
	end
end

function Spectate:Prev()
	if self.active and not self.free then
		self:_cycle(-1)
	end
end

function Spectate:ToggleFree()
	if not self.active then
		return
	end
	self.free = not self.free
	if self.free then
		local cam = workspace.CurrentCamera
		self.freePos = cam and cam.CFrame.Position or self.freePos
	else
		-- Both, or coming back from free cam aims at a stale point and
		-- sweeps onto the subject instead of cutting to it.
		self.pos, self.focus = nil, nil
	end
end

-- Mouse or right-stick look. Fed in from the client so this module owns
-- no input bindings of its own.
function Spectate:Look(delta: Vector2)
	if not self.active then
		return
	end
	self.yaw -= delta.X * SP.LookSensitivity
	self.pitch = math.clamp(self.pitch - delta.Y * SP.LookSensitivity, math.rad(SP.PitchMin), math.rad(SP.PitchMax))
end

function Spectate:Zoom(amount: number)
	if self.active and not self.free then
		self.dist = math.clamp(self.dist - amount * SP.ZoomStep, SP.DistanceMin, SP.DistanceMax)
	end
end

-- Held right-mouse look. Owned here rather than by the caller so the
-- flag can't be left true after spectating ends.
function Spectate:SetLooking(on: boolean)
	self.looking = on and self.active
end

function Spectate:IsLooking(): boolean
	return self.active and self.looking
end

function Spectate:IsActive(): boolean
	return self.active
end

function Spectate:IsFree(): boolean
	return self.active and self.free
end

--=====================================================================
--  FRAME
--=====================================================================
function Spectate:Update(dt: number, phase: string?, finished: boolean, move: Vector3)
	-- Racing AND Results. The end of the round is the part most worth
	-- watching, and cutting away at the flag was the single worst thing
	-- about the first version.
	local want = finished and (phase == P.Racing or phase == P.Results)
	if want ~= self.active then
		if want then
			self:_start()
		else
			self:_stop()
		end
	end
	if not self.active then
		return
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	----------------------------------------------------------------
	-- FREE CAM
	----------------------------------------------------------------
	if self.free then
		local look = CFrame.fromEulerAnglesYXZ(self.pitch, self.yaw, 0)
		local speed = SP.FreeSpeed * (if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then SP.FreeBoost else 1)
		local world = look:VectorToWorldSpace(move)
		self.freePos = (self.freePos or cam.CFrame.Position) + world * speed * dt
		cam.CFrame = CFrame.new(self.freePos) * look
		return
	end

	----------------------------------------------------------------
	-- FOLLOW
	----------------------------------------------------------------
	-- Subject gone, destroyed, or we never had one.
	if not (self.target and self.target.Parent and self.target.PrimaryPart) then
		self:_pickBest()
	end
	local kart = self.target
	local hitbox = kart and kart.PrimaryPart
	if not hitbox then
		-- Nothing at all to watch. Hold the last view rather than freezing
		-- at the origin, and stay usable — free cam still works from here.
		return
	end

	-- Orbit around the kart. Yaw is relative to the kart's own heading,
	-- so an untouched camera sits behind it and stays there through
	-- corners rather than being left facing a wall.
	local base = hitbox.CFrame
	local flat = Vector3.new(base.LookVector.X, 0, base.LookVector.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local heading = math.atan2(-flat.X, -flat.Z)

	-- SMOOTH THE AIM POINT TOO, not just the camera position.
	--
	-- A bot's kart is anchored and server-written, so it arrives in
	-- replication steps — RemoteKarts eases those out of the kart's own
	-- CFrame, but only for as long as it can see them. Aiming the camera
	-- straight at the raw position put every remaining step into the
	-- ROTATION, which is exactly where the eye notices it: the camera
	-- body was gliding while the subject twitched inside the frame.
	--
	-- Smoothing the focus faster than the position is deliberate. The
	-- aim has to stay locked on the kart or it lags behind through a
	-- corner and the subject slides toward the edge of frame; the body
	-- can afford to be lazy because nothing is being measured against it.
	local wantFocus = base.Position + Vector3.yAxis * SP.LookHeight
	self.focus = if self.focus then self.focus:Lerp(wantFocus, math.min(SP.FocusFollow * dt, 1)) else wantFocus

	local offset = CFrame.fromEulerAnglesYXZ(self.pitch, heading + self.yaw, 0)
	local want3 = self.focus - offset.LookVector * self.dist

	self.pos = if self.pos then self.pos:Lerp(want3, math.min(SP.Follow * dt, 1)) else want3
	cam.CFrame = CFrame.lookAt(self.pos, self.focus)
end

-- For the HUD. Nil when not spectating.
function Spectate:StatusText(): string?
	if not self.active then
		return nil
	end
	if self.free then
		return "FREE CAM   WASD move   RMB look   F follow"
	end
	local kart = self.target
	if not kart then
		return "SPECTATING   nobody left   F free cam"
	end
	local id = kart:GetAttribute(Names.OWNER)
	local player = id and Players:GetPlayerByUserId(id)
	local name = if player then player.DisplayName else kart:GetAttribute(Names.RACER_NAME)
	if typeof(name) ~= "string" or name == "" then
		name = "Racer"
	end
	local tag = if racing(kart) then "" else "  (finished)"
	return ("SPECTATING  %s%s   Q/E switch   F free cam"):format(name:upper(), tag)
end

function Spectate:Destroy()
	self:_stop()
end

return Spectate
