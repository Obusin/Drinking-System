--[[
	XpHud — TEMPORARY. XP as it is earned, and the level when it turns.

	Placeholder by intent, and it should be replaced wholesale by the
	real design. It exists because XP that only appears on the results
	screen is XP nobody can feel, and numbers you cannot feel cannot be
	tuned — you find out whether a takedown is worth 25 by landing one
	and seeing what 25 looks like.

	Two things, both bottom-of-screen furniture:

		toasts   "+25 XP  TAKEDOWN", stacking, oldest fading first
		banner   "LEVEL 4", once, when the bar turns over

	Everything is driven by the payload Progress already sends for its
	own audit line, so the label on screen and the reason in the log are
	the same string. They cannot drift because there is only one of them.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local L = Config.Level
local H = Config.Hud
local R = Config.Rewards

local FONT = Util.font(H.FontName, H.FontWeight)

local XpHud = {}
XpHud.__index = XpHud

local function label(parent: Instance, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = colour
	l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	l.TextStrokeTransparency = H.StrokeTransparency
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.Text = ""
	l.Parent = parent
	return l
end

function XpHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartXp"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Under the transition and the results panel. This is racing
	-- furniture and has no business over either.
	gui.DisplayOrder = 6
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local stack = Instance.new("Frame")
	stack.Name = "Toasts"
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = L.ToastPosition
	stack.Size = UDim2.fromOffset(420, L.ToastRows * L.ToastRowHeight)
	stack.BackgroundTransparency = 1
	stack.Parent = gui

	-- Pooled, like the hit feed. A toast per hit in a busy race is a lot
	-- of instances to create and throw away.
	local rows = {}
	for i = 1, L.ToastRows do
		local l = label(stack, L.ToastSize, R.AccentColor)
		l.Name = "Toast" .. i
		l.Size = UDim2.new(1, 0, 0, L.ToastRowHeight)
		l.Position = UDim2.fromOffset(0, (i - 1) * L.ToastRowHeight)
		table.insert(rows, l)
	end

	local banner = label(gui, L.BannerSize, R.AccentColor)
	banner.Name = "LevelUp"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = L.BannerPosition
	banner.Size = UDim2.fromOffset(560, 70)
	banner.TextTransparency = 1

	local bannerSub = label(gui, L.BannerSubSize, R.TextColor)
	bannerSub.Name = "LevelUpSub"
	bannerSub.AnchorPoint = Vector2.new(0.5, 0)
	bannerSub.Position = L.BannerPosition + UDim2.fromOffset(0, 40)
	bannerSub.Size = UDim2.fromOffset(560, 30)
	bannerSub.TextTransparency = 1

	return setmetatable({
		gui = gui,
		rows = rows,
		lines = {},
		banner = banner,
		bannerSub = bannerSub,
		bannerAt = -math.huge,
	}, XpHud)
end

-- `info` is the payload Progress sends: amount, reason, level,
-- leveledUp, bolt.
function XpHud:Award(info)
	if typeof(info) ~= "table" or (info.amount or 0) <= 0 then
		return
	end

	local reason = tostring(info.reason or "")
	-- A reason with no label shows the reason. Better a raw string than
	-- a blank line, and it makes a missing label obvious rather than
	-- invisible.
	local what = L.Labels[reason] or string.upper(reason)

	table.insert(self.lines, 1, {
		text = ("+%d XP   %s"):format(info.amount, what),
		at = os.clock(),
	})
	while #self.lines > L.ToastRows do
		table.remove(self.lines)
	end

	if info.leveledUp then
		self.banner.Text = ("LEVEL %d"):format(info.level or 0)
		-- The reward is stated, because a level that pays nothing and a
		-- level that pays 150 look identical otherwise.
		self.bannerSub.Text = if (info.bolt or 0) > 0 then ("+%d BOLT"):format(info.bolt) else ""
		self.bannerAt = os.clock()
	end
end

local function fadeOf(age: number, hold: number, fade: number): number
	return math.clamp((age - hold) / math.max(fade, 0.01), 0, 1)
end

function XpHud:Update()
	local now = os.clock()

	for i, row in self.rows do
		local line = self.lines[i]
		if not line then
			row.Text = ""
			continue
		end
		local age = now - line.at
		if age > L.ToastHold + L.ToastFade then
			row.Text = ""
			continue
		end
		row.Text = line.text
		local f = fadeOf(age, L.ToastHold, L.ToastFade)
		row.TextTransparency = f
		row.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * f
	end

	local age = now - self.bannerAt
	local shown = age <= L.BannerHold + L.BannerFade
	local f = if shown then fadeOf(age, L.BannerHold, L.BannerFade) else 1
	self.banner.TextTransparency = f
	self.bannerSub.TextTransparency = f
	self.banner.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * f
	self.bannerSub.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * f
end

function XpHud:Destroy()
	self.gui:Destroy()
end

return XpHud
