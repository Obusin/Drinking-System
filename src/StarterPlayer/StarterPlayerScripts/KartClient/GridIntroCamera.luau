--[[
	GridIntroCamera — a short cinematic handoff from Intermission to driving.

	The intermission rail is a wide track presentation. Grid is the moment the
	game says "this is your kart": cut to its own wide player shot, then make a
	smooth player-only dolly into chase-camera composition during 3-2-1. It is deliberately
	client presentation only; Match still holds the kart and owns the start.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local INTRO = Config.Match.GridCamera
local CHASE = Config.Camera

local GridIntroCamera = {}
GridIntroCamera.__index = GridIntroCamera

local function chaseShot(sim): CFrame
	local up = sim.visualNormal.Unit
	local forward = sim.forward
	local eye = sim.pos - forward * CHASE.Distance + up * CHASE.Height
	local aim = sim.pos + forward * CHASE.LookAhead + up * CHASE.LookHeight
	return CFrame.lookAt(eye, aim, up)
end

local function wideShot(sim): CFrame
	local up = sim.visualNormal.Unit
	local forward = sim.forward
	local eye = sim.pos - forward * INTRO.StartDistance + up * INTRO.StartHeight
	local aim = sim.pos + up * INTRO.StartLookHeight
	return CFrame.lookAt(eye, aim, up)
end

function GridIntroCamera.new()
	return setmetatable({
		armed = false,
		active = false,
		finished = false,
		elapsed = 0,
		from = nil,
		fromFov = nil,
	}, GridIntroCamera)
end

-- Called on the exact frame Match consumes the locally-owned GridCF. This is
-- the only trustworthy visual boundary: waiting for the shared countdown
-- leaves a visible beat where CameraRig has already snapped to the player.
function GridIntroCamera:Arm()
	self.armed = true
	self.active = false
	self.finished = false
	self.elapsed = 0
	self.from = nil
	self.fromFov = nil
end

function GridIntroCamera:Update(dt: number, shouldPlay: boolean, sim)
	if not INTRO.Enabled then
		shouldPlay = false
	end
	if not shouldPlay or not sim then
		self.active = false
		self.armed = false
		self.finished = false
		self.elapsed = 0
		self.from = nil
		self.fromFov = nil
		return
	end
	if not self.armed then
		return
	end
	if self.finished then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if not self.active then
		self.active = true
		self.elapsed = 0
		-- Intermission is over: cut once into a player-specific composition.
		-- Do NOT use the previous scene's CFrame here; doing so makes the
		-- camera fly back across the map after the rail has already ended.
		self.from = wideShot(sim)
		self.fromFov = INTRO.StartFov
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = self.from
		camera.FieldOfView = self.fromFov
	end

	self.elapsed += dt
	local duration = math.max(INTRO.Duration, 0.05)
	local t = math.clamp(self.elapsed / duration, 0, 1)
	-- Cubic ease-out: it moves decisively toward the player, then settles
	-- gently into the normal chase camera so handoff has no visible snap.
	local eased = 1 - (1 - t) ^ 3
	camera.CFrame = self.from:Lerp(chaseShot(sim), eased)
	camera.FieldOfView = self.fromFov + (CHASE.FovBase - self.fromFov) * eased
	if t >= 1 then
		self.active = false
		self.finished = true
	end
end

return GridIntroCamera
