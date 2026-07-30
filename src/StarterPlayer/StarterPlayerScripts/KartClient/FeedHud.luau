--[[
	FeedHud — "MISSILE hit Obus1n", top centre.

	Landing an item is the most satisfying thing in the game and until now
	it was completely silent to everyone except the victim, who only knew
	because they span. The attacker got no confirmation at all.

	WHY EVERYONE SEES EVERY HIT
	---------------------------
	A hit is a spectacle. Half the value of a well-timed missile is the
	lobby watching it land — and in a race where you rarely see the
	person you hit, the feed IS the feedback.

	Lines are tinted rather than prefixed: your own name in gold tells you
	at a glance whether a line involves you, without reading it.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local H = Config.Hud
local FONT = Util.font(H.FontName, H.FontWeight)

local FeedHud = {}
FeedHud.__index = FeedHud

function FeedHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartFeed"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = H.FeedPosition
	panel.Size = UDim2.fromOffset(560, H.FeedRows * H.FeedRowHeight)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	-- Rows are made once and reused. A feed that creates and destroys
	-- labels churns instances every time anybody is hit, which in a
	-- busy race is constantly.
	local rows = {}
	for i = 1, H.FeedRows do
		local l = Instance.new("TextLabel")
		l.Name = "Row" .. i
		l.Size = UDim2.new(1, 0, 0, H.FeedRowHeight)
		l.Position = UDim2.fromOffset(0, (i - 1) * H.FeedRowHeight)
		l.BackgroundTransparency = 1
		l.FontFace = FONT
		l.TextSize = H.FeedSize
		l.TextColor3 = H.FeedColor
		l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		l.TextStrokeTransparency = H.StrokeTransparency
		l.RichText = true -- so one line can tint attacker, item and victim
		l.Text = ""
		l.Parent = panel
		table.insert(rows, l)
	end

	return setmetatable({ gui = gui, rows = rows, lines = {} }, FeedHud)
end

local function hex(c: Color3): string
	return ("#%02X%02X%02X"):format(c.R * 255, c.G * 255, c.B * 255)
end

-- `by` may be nil: a mine kills long after its owner has driven off, and
-- a missile fired at nobody still hits whoever it runs into.
function FeedHud:Add(item: string, by: string?, victim: string)
	local me = Players.LocalPlayer.Name
	local function who(name: string): string
		local colour = if name == me then H.FeedSelfColor else H.FeedColor
		return ('<font color="%s">%s</font>'):format(hex(colour), name)
	end

	local tag = ('<font color="%s">%s</font>'):format(hex(H.FeedItemColor), item:upper())
	local text = if by then ("%s  %s  %s"):format(who(by), tag, who(victim)) else ("%s  %s"):format(tag, who(victim))

	table.insert(self.lines, 1, { text = text, at = os.clock() })
	-- Oldest off the end rather than growing forever.
	while #self.lines > H.FeedRows do
		table.remove(self.lines)
	end
end

function FeedHud:Update()
	local now = os.clock()
	for i, row in self.rows do
		local line = self.lines[i]
		if not line then
			row.Text = ""
			continue
		end
		local age = now - line.at
		if age > H.FeedHold + H.FeedFade then
			row.Text = ""
			continue
		end
		row.Text = line.text
		-- Held at full strength, then faded — a feed that starts fading
		-- immediately is hard to read at exactly the moment you want to.
		local fade = math.clamp((age - H.FeedHold) / math.max(H.FeedFade, 0.01), 0, 1)
		row.TextTransparency = fade
		row.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * fade
	end
end

function FeedHud:Destroy()
	self.gui:Destroy()
end

return FeedHud
