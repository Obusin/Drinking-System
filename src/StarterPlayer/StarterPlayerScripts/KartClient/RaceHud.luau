--[[
	RaceHud — lap counter and timer, bottom right.

	Placeholder styling: readable first, pretty later. Built in code so
	there's nothing to wire up in StarterGui.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))
local R = Config.Race
local H = Config.Hud

local RaceHud = {}
RaceHud.__index = RaceHud

-- m:ss.cc — centiseconds, because tenths feel imprecise for a racer and
-- milliseconds are unreadable at a glance.
local function formatTime(t: number): string
	if t <= 0 then
		return "0:00.00"
	end
	local minutes = math.floor(t / 60)
	local seconds = t % 60
	return ("%d:%05.2f"):format(minutes, seconds)
end

local FONT = Util.font(H.FontName, H.FontWeight)

local function label(parent: Instance, name: string, size: UDim2, pos: UDim2, textSize: number, colour: Color3)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = textSize
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.Text = ""
	-- No panel behind the text any more, so it needs its own contrast
	-- against whatever track happens to be underneath.
	l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	l.TextStrokeTransparency = H.StrokeTransparency
	l.Parent = parent
	return l
end

function RaceHud.new()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Top right, mirroring the reference: a small blue caption above a
	-- big white value, twice — time, then laps.
	local panel = Instance.new("Frame")
	panel.Name = "Race"
	panel.AnchorPoint = H.RaceAnchor
	panel.Position = H.RacePosition
	panel.Size = UDim2.fromOffset(230, 132)
	-- Text only. Kept as a Frame purely to anchor and lay out the labels.
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local caption = label(panel, "TimeCaption", UDim2.new(1, 0, 0, 17), UDim2.fromOffset(0, 0), H.RaceSmallSize, H.RaceLabelColor)
	caption.Text = "TIME"

	local time = label(panel, "Time", UDim2.new(1, 0, 0, 38), UDim2.fromOffset(0, 16), H.RaceTimeSize, H.RaceValueColor)
	local lap = label(panel, "Lap", UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 54), H.RaceLapSize, H.RaceValueColor)

	-- Best-lap and checkpoint progress are ours, not the reference's,
	-- but they're the two things worth knowing mid-lap.
	local total = label(panel, "Total", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 98), 14, Color3.fromRGB(150, 158, 178))
	local checks = label(panel, "Checks", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 114), 14, Color3.fromRGB(130, 138, 158))

	----------------------------------------------------------------
	-- WRONG WAY
	--
	-- Centre screen, above the middle. Deliberately the loudest thing
	-- the HUD ever shows: the point is that you notice it without
	-- looking for it, and it's the one message meaning "stop doing what
	-- you're doing".
	--
	-- Sits above the countdown's slot rather than on it, so the two can
	-- never overlap into an unreadable pile.
	----------------------------------------------------------------
	local wrong = Instance.new("TextLabel")
	wrong.Name = "WrongWay"
	wrong.AnchorPoint = Vector2.new(0.5, 0.5)
	wrong.Position = H.WrongWayPosition
	wrong.Size = UDim2.fromOffset(520, 70)
	wrong.BackgroundTransparency = 1
	wrong.FontFace = FONT
	wrong.TextSize = H.WrongWaySize
	wrong.TextColor3 = H.WrongWayColor
	wrong.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	-- Heavier stroke than the rest of the HUD: it has to stay legible
	-- over a bright skybox, which is exactly where you end up when
	-- you're facing the wrong way off the edge of a track.
	wrong.TextStrokeTransparency = 0.15
	wrong.Text = H.WrongWayText
	wrong.Visible = false
	wrong.Parent = gui

	-- The item's own picture, beside the words. Sized and placed each
	-- time the alert is set, since which item it is decides both.
	local alertIcon = Instance.new("ImageLabel")
	alertIcon.Name = "AlertIcon"
	alertIcon.AnchorPoint = Vector2.new(1, 0.5)
	alertIcon.Position = H.WrongWayPosition
	alertIcon.Size = UDim2.fromOffset(H.AlertIconSize, H.AlertIconSize)
	alertIcon.BackgroundTransparency = 1
	alertIcon.Visible = false
	alertIcon.Parent = gui

	return setmetatable({
		gui = gui,
		alertIcon = alertIcon,
		lap = lap,
		time = time,
		total = total,
		checks = checks,
		wrong = wrong,
		wrongPhase = 0,
		rejectUntil = 0,
	}, RaceHud)
end

-- One pulsing alert slot, shared by everything that needs to shout at
-- the player. Pass nil to clear it.
--
-- Deliberately ONE slot rather than a label per condition: two alarms
-- stacked in the centre of the screen is worse than either alone, so the
-- caller has to decide what matters most and say only that.
--
-- Pulsed rather than static. A steady label reads as HUD furniture you
-- learn to ignore; a pulse reads as an alarm.
-- `urgency` is 0..1 and drives the BLINK RATE: 0 blinks slowly, 1 blinks
-- hard. That is the time remaining, carried by the thing that is already
-- flashing rather than by another readout on a racing screen.
--
-- The phase is ACCUMULATED, not recomputed from a clock, so a rate that
-- changes speeds the blinking up smoothly instead of jumping the wave
-- to a new position every time the urgency moves.
-- `icon` is an item image id, or nil. Shown to the LEFT of the words and
-- fading with them, so a glance says what is coming before the text has
-- been read — which at racing speed is most glances.
function RaceHud:SetAlert(text: string?, colour: Color3?, dt: number, urgency: number?, icon: string?)
	if not text then
		self.wrong.Visible = false
		self.alertIcon.Visible = false
		self.wrongPhase = 0
		return
	end

	local hasIcon = icon ~= nil and icon ~= ""
	self.alertIcon.Visible = hasIcon
	if hasIcon then
		if self.alertIcon.Image ~= icon then
			self.alertIcon.Image = icon
			Util.verifyImage(self.alertIcon, icon, "RaceHud")
		end
		-- Sat off the left edge of the text rather than centred with it,
		-- so adding an icon never moves the words.
		self.alertIcon.Position = H.WrongWayPosition
			- UDim2.fromOffset(self.wrong.TextBounds.X * 0.5 + H.AlertIconGap, 0)
	end
	self.wrong.Visible = true
	self.wrong.Text = text
	self.wrong.TextColor3 = colour or H.WrongWayColor
	local u = math.clamp(urgency or 0, 0, 1)

	if u < H.AlertBlinkFrom then
		-- SOLID. There is time; the alert is information, not an alarm.
		-- Blinking from the moment it appears leaves nothing to escalate
		-- to when the situation actually gets urgent.
		self.wrongPhase = 0
		self.wrong.TextTransparency = 0
		self.alertIcon.ImageTransparency = 0
		return
	end

	-- Past the threshold it starts blinking, from slow to frantic across
	-- the REMAINING range rather than the whole one — so the first blink
	-- is a slow blink, not a mid-speed one.
	local t = (u - H.AlertBlinkFrom) / math.max(1 - H.AlertBlinkFrom, 1e-3)
	local rate = H.AlertPulseSlow + (H.AlertPulseFast - H.AlertPulseSlow) * t
	self.wrongPhase += dt * rate
	-- Biased into 0..1 and scaled, so it never fades to fully invisible —
	-- a warning that blinks off entirely is easy to miss between blinks.
	local pulse = (math.sin(self.wrongPhase * math.pi * 2) + 1) * 0.5
	self.wrong.TextTransparency = pulse * H.WrongWayFade
	self.alertIcon.ImageTransparency = pulse * H.WrongWayFade
end

-- Flash the checkpoint line when a lap is refused, so a rejected lap
-- reads as "you missed a checkpoint" rather than "the timer is broken".
function RaceHud:FlashRejected()
	self.rejectUntil = os.clock() + 1.5
end

function RaceHud:Update(race)
	-- "2/3 LAP", matching the reference's ordering.
	self.lap.Text = ("%d/%d LAP"):format(race:CurrentLap(), R.TotalLaps)
	self.time.Text = formatTime(race:LapElapsed())

	if race.finished then
		self.lap.Text = "FINISHED"
		self.lap.TextColor3 = Color3.fromRGB(120, 230, 140)
		self.time.TextColor3 = Color3.fromRGB(120, 230, 140)
		self.total.Text = "TOTAL " .. formatTime(race:TotalElapsed())
	elseif race.bestLap then
		self.total.Text = "BEST " .. formatTime(race.bestLap)
	else
		self.total.Text = "TOTAL " .. formatTime(race:TotalElapsed())
	end

	local passed, count = race:CheckpointProgress()
	if count == 0 then
		self.checks.Text = ""
	elseif os.clock() < self.rejectUntil then
		self.checks.Text = ("MISSED — CP %d/%d"):format(passed, count)
		self.checks.TextColor3 = Color3.fromRGB(240, 110, 110)
	else
		self.checks.Text = ("CP %d/%d"):format(passed, count)
		self.checks.TextColor3 = if passed >= count
			then Color3.fromRGB(120, 230, 140)
			else Color3.fromRGB(120, 128, 148)
	end
end

-- Off in a lobby: laps, position and the alert slot are all race
-- readings. See MatchHud:SetVisible.
function RaceHud:SetVisible(on: boolean)
	self.gui.Enabled = on
end

function RaceHud:Destroy()
	self.gui:Destroy()
end

return RaceHud
