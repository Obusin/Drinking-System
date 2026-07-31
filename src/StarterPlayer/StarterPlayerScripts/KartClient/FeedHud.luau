--[[
	FeedHud — the kill feed. "<attacker>  [icon]  <victim>", top centre.

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

	THE ICON CARRIES THE VERB
	-------------------------
	An icon between two names reads as "did this to" in every game that
	has ever shipped a kill feed, and unlike a word it survives
	translation and never wraps. The item name is gone from the line for
	the same reason: it was saying in text what the picture says better.

	A row is a Frame and not a label, because centring an image between
	two independently-sized names is a layout problem and RichText has no
	answer to it. The attacker is right-aligned into the left half, the
	victim left-aligned into the right, and the icon sits on the middle —
	so the line grows outward from the icon and the icon never moves.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local H = Config.Hud
local L = Config.Level
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
	local function side(parent: Instance, right: boolean): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = if right then "By" else "Victim"
		l.BackgroundTransparency = 1
		l.FontFace = FONT
		l.TextSize = H.FeedSize
		l.TextColor3 = H.FeedColor
		l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		l.TextStrokeTransparency = H.StrokeTransparency
		l.TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		l.Size = UDim2.new(0.5, -(L.FeedIconSize / 2 + L.FeedGap), 1, 0)
		l.Position = if right then UDim2.fromScale(0, 0) else UDim2.new(0.5, L.FeedIconSize / 2 + L.FeedGap, 0, 0)
		l.Text = ""
		l.Parent = parent
		return l
	end

	local rows = {}
	for i = 1, H.FeedRows do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, H.FeedRowHeight)
		row.Position = UDim2.fromOffset(0, (i - 1) * H.FeedRowHeight)
		row.Parent = panel

		local by = side(row, true)
		local victim = side(row, false)

		local ic = Instance.new("ImageLabel")
		ic.Name = "Icon"
		ic.BackgroundTransparency = 1
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Size = UDim2.fromOffset(L.FeedIconSize, L.FeedIconSize)
		ic.Image = ""
		ic.Parent = row

		table.insert(rows, { frame = row, by = by, victim = victim, icon = ic })
	end

	return setmetatable({ gui = gui, rows = rows, lines = {} }, FeedHud)
end

-- `by` may be nil: a mine kills long after its owner has driven off, and
-- a missile fired at nobody still hits whoever it runs into. With no
-- attacker the icon slides left and the victim stands alone, which is
-- the truthful rendering — something hit them, and nobody did it.
--
-- `icon` may be "" — FakeBox still has no art. The item name is the
-- fallback rather than an empty gap, so a line never silently loses its
-- verb.
function FeedHud:Add(item: string, by: string?, victim: string, icon: string?)
	table.insert(self.lines, 1, {
		by = by,
		victim = victim,
		icon = icon or "",
		item = item,
		at = os.clock(),
	})
	-- Oldest off the end rather than growing forever.
	while #self.lines > H.FeedRows do
		table.remove(self.lines)
	end
end

local function blank(row)
	row.by.Text = ""
	row.victim.Text = ""
	row.icon.Image = ""
end

function FeedHud:Update()
	local now = os.clock()
	local me = Players.LocalPlayer.DisplayName

	for i, row in self.rows do
		local line = self.lines[i]
		if not line then
			blank(row)
			continue
		end
		local age = now - line.at
		if age > H.FeedHold + H.FeedFade then
			blank(row)
			continue
		end

		row.by.Text = line.by or ""
		row.by.TextColor3 = if line.by == me then H.FeedSelfColor else H.FeedColor
		row.victim.Text = line.victim
		row.victim.TextColor3 = if line.victim == me then H.FeedSelfColor else H.FeedColor

		if line.icon ~= "" then
			row.icon.Image = line.icon
			Util.verifyImage(row.icon, line.icon, "FeedHud")
			row.victim.Text = line.victim
		else
			-- No art for this item yet: name it rather than leaving the
			-- middle of the line empty.
			row.icon.Image = ""
			row.victim.Text = ("%s  %s"):format(string.upper(line.item), line.victim)
		end

		-- Held at full strength, then faded — a feed that starts fading
		-- immediately is hard to read at exactly the moment you want to.
		local fade = math.clamp((age - H.FeedHold) / math.max(H.FeedFade, 0.01), 0, 1)
		row.by.TextTransparency = fade
		row.victim.TextTransparency = fade
		row.icon.ImageTransparency = fade
		row.by.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * fade
		row.victim.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * fade
	end
end

function FeedHud:Destroy()
	self.gui:Destroy()
end

return FeedHud
