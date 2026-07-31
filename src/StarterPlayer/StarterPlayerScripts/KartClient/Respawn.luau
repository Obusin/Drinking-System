--[[
	Respawn — puts a fallen kart back on the track.

	Three ways to trigger, because a tag alone isn't enough:

	  1. VoidZone tag   drove into a pit, water, lava
	  2. Freefall       falling continuously for FreefallTime. By TIME,
	                    not height: any height threshold has to guess
	                    where the track is, and misfires while you're
	                    driving normally when it guesses wrong
	  3. Manual reset   OFFERED only once you're demonstrably stuck, not
	                    always available — an always-on reset key is a
	                    shortcut past any corner you keep failing

	The button lives in here rather than in its own HUD module because
	it has exactly one consumer and no styling of its own worth sharing.
	Splitting forty lines out for symmetry alone isn't worth the file.

	Where you land comes from Race: last checkpoint, else the start line,
	else the grid slot the kart spawned on.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Players = game:GetService("Players")

local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))
local TagZones = require(BloxKart:WaitForChild("TagZones"))
local Shared = require(BloxKart:WaitForChild("Match"))

local RS = Config.Respawn
local H = Config.Hud

local Respawn = {}
Respawn.__index = Respawn

-- Resolved once, lazily, rather than waited for at require time: this
-- module loads before the server has finished building its remotes.
Respawn.voidRemote = BloxKart:FindFirstChild(Shared.VOID_REMOTE)
task.spawn(function()
	Respawn.voidRemote = BloxKart:WaitForChild(Shared.VOID_REMOTE, 20)
end)

function Respawn.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartStuck"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Centred and low, out of the racing line of sight but impossible to
	-- miss once it appears.
	local button = Instance.new("TextButton")
	button.Name = "Reset"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -150)
	button.Size = UDim2.fromOffset(220, 44)
	button.BackgroundTransparency = 1
	button.FontFace = Util.font(H.FontName, H.FontWeight)
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = H.StrokeTransparency
	button.Text = ("%s   [%s]"):format(RS.ButtonText, RS.ButtonHint)
	button.AutoButtonColor = false
	button.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Parent = button
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 10)
	round.Parent = button

	local self = setmetatable({
		void = TagZones.new(RS.VoidTag, { cooldown = RS.Cooldown, forceQueryable = true }),
		lastAt = 0,
		stuckFor = 0,
		offered = false,
		clicked = false,
		gui = gui,
		button = button,
	}, Respawn)

	button.Activated:Connect(function()
		self.clicked = true
	end)
	return self
end

-- Trying to move and not moving, or falling with nothing under you.
-- Coasting to a stop isn't stuck — the throttle test is what separates
-- "wedged against a wall" from "parked".
function Respawn:_updateStuck(sim, dt: number)
	local trying = math.abs(sim.seat.ThrottleFloat) > 0.1
	local notMoving = math.abs(sim.speed) < RS.StuckSpeed
	local falling = sim.airTime >= RS.StuckAirTime

	if (trying and notMoving) or falling then
		self.stuckFor += dt
	else
		self.stuckFor = 0
	end

	self.offered = self.stuckFor >= RS.StuckTime or falling
	self.gui.Enabled = self.offered
end

-- Returns a reason string if it fired, nil otherwise.
function Respawn:Check(sim, race, input, dt: number): string?
	self:_updateStuck(sim, dt or 0)

	local now = os.clock()
	local pressedReset = input.consumeReset()
	local tappedButton = self.clicked
	self.clicked = false

	if now - self.lastAt < RS.Cooldown then
		return nil
	end

	local reason: string? = nil

	-- Both routes require the offer to be up, so neither is a shortcut.
	if self.offered and (pressedReset or tappedButton) then
		reason = "manual"
	elseif self.void:Touch(sim.hitbox.CFrame, sim.hitbox.Size) then
		reason = "void"
	elseif RS.FreefallTime > 0 and sim.airTime >= RS.FreefallTime and sim.vertVel < 0 then
		-- Still falling, and has been for a while. No height involved, so
		-- this can't misfire on a high track or a tall checkpoint gate.
		reason = "fell"
	elseif sim.pos.Y < RS.FallFloor then
		reason = "void"
	elseif race:IsLost() then
		-- Driven the wrong way long past the warning. Put back at the LAST
		-- checkpoint they banked, not the one they missed: from there they
		-- drive forward through the missed gate and take it properly,
		-- rather than being placed on top of it and hoping the trigger
		-- fires.
		reason = "lost"
	end

	if not reason then
		return nil
	end

	-- TELL THE SERVER, AND RESPAWN ANYWAY.
	--
	-- Only the client can see this fall, but it gets no vote on the
	-- verdict — the server owns the hit clock and decides whether this
	-- was an elimination. So the report goes up and the respawn happens
	-- regardless: if it was an elimination the kart is about to be
	-- removed and the respawn is harmless, and if it was not, waiting
	-- for a round trip would leave the player sitting in the void.
	if reason == "void" and Respawn.voidRemote then
		Respawn.voidRemote:FireServer()
	end

	local target = race:RespawnCFrame() or sim.spawnCF
	-- Lift along the target's own up, so this still works on a loop.
	sim:RespawnAt(target + target.UpVector * RS.RespawnLift)
	self.lastAt = now
	self.stuckFor, self.offered = 0, false
	self.gui.Enabled = false
	return reason
end

function Respawn:Destroy()
	self.void:Destroy()
	self.gui:Destroy()
end

return Respawn
