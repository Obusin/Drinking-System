--[[
	QuestHud — one panel, three tabs.

	DAILY / WEEKLY / MONTHLY switch the list below them. The previous
	version stacked all three, which was the same information in three
	times the height and pushed the monthly off the bottom of the screen.

	The whole thing lives behind a QUESTS tab and is closed by default. A
	racing HUD should show what you need while driving, and a quest list
	is not that — but collapsing it means you stop looking at it, so both
	the tab and each layer button carry a badge when something is
	finished and unclaimed. A reward you earned and did not notice is the
	same as no reward.

	IT DRAWS A SNAPSHOT AND NOTHING ELSE.
	-------------------------------------
	The server sends the whole list — text, target, progress, claimed —
	and this renders it. No local counting, no predicting, no deciding
	whether something is done. A client that works out its own quest
	progress can be wrong about it, and being wrong about a reward is the
	one place that matters.

	ONE ROW POOL, SHARED BY EVERY TAB. Only one layer is ever visible, so
	three pools would be two sets of instances sitting idle.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))
local Names = require(BloxKart:WaitForChild("Names"))

local L = Config.Level
local H = Config.Hud
local R = Config.Rewards

local FONT = Util.font(H.FontName, H.FontWeight)

local QuestHud = {}
QuestHud.__index = QuestHud

local function text(parent: Instance, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Text = ""
	l.Parent = parent
	return l
end

local function dot(parent: Instance): Frame
	local d = Instance.new("Frame")
	d.Name = "Badge"
	d.BackgroundColor3 = L.QuestBadgeColor
	d.BorderSizePixel = 0
	d.AnchorPoint = Vector2.new(1, 0.5)
	d.Position = UDim2.new(1, -6, 0.5, 0)
	d.Size = UDim2.fromOffset(8, 8)
	d.Visible = false
	d.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = d
	return d
end

local function clockText(seconds: number): string
	seconds = math.max(seconds, 0)
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = math.floor(seconds % 60)
	if h >= 24 then
		return ("%dd %02dh"):format(math.floor(h / 24), h % 24)
	end
	return ("%02d:%02d:%02d"):format(h, m, s)
end

--=====================================================================
--  BUILD
--=====================================================================
function QuestHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartQuests"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	----------------------------------------------------------------
	-- The open/close tab
	----------------------------------------------------------------
	local open = Instance.new("TextButton")
	open.Name = "Open"
	open.BackgroundColor3 = L.QuestPanelColor
	open.BackgroundTransparency = 0.15
	open.BorderSizePixel = 0
	open.Position = L.QuestButtonPosition
	open.Size = UDim2.fromOffset(L.QuestButtonSize.X, L.QuestButtonSize.Y)
	open.FontFace = FONT
	open.TextSize = L.QuestTitleSize
	open.TextColor3 = R.TextColor
	open.Text = L.QuestButtonText
	open.AutoButtonColor = true
	open.Parent = gui

	local openBadge = dot(open)

	----------------------------------------------------------------
	-- The panel
	----------------------------------------------------------------
	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.BackgroundColor3 = L.QuestPanelColor
	root.BackgroundTransparency = L.QuestPanelTransparency
	root.BorderSizePixel = 0
	root.Position = L.QuestButtonPosition + UDim2.fromOffset(0, L.QuestButtonSize.Y + 8)
	root.Size = UDim2.fromOffset(L.QuestWidth, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Visible = false
	root.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = root

	local stack = Instance.new("UIListLayout")
	stack.Padding = UDim.new(0, 8)
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Parent = root

	----------------------------------------------------------------
	-- Tabs
	----------------------------------------------------------------
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.new(1, 0, 0, L.QuestTabHeight)
	tabBar.LayoutOrder = 0
	tabBar.Parent = root

	local tabRow = Instance.new("UIListLayout")
	tabRow.FillDirection = Enum.FillDirection.Horizontal
	tabRow.Padding = UDim.new(0, 4)
	tabRow.SortOrder = Enum.SortOrder.LayoutOrder
	tabRow.Parent = tabBar

	local tabs = {}
	for i, layer in L.QuestLayers do
		local b = Instance.new("TextButton")
		b.Name = layer
		b.BackgroundColor3 = L.QuestTabIdle
		b.BorderSizePixel = 0
		b.Size = UDim2.new(1 / #L.QuestLayers, -3, 1, 0)
		b.FontFace = FONT
		b.TextSize = L.QuestSmallSize
		b.TextColor3 = R.DimTextColor
		b.Text = string.upper(layer)
		b.AutoButtonColor = true
		b.LayoutOrder = i
		b.Parent = tabBar
		tabs[layer] = { button = b, badge = dot(b) }
	end

	----------------------------------------------------------------
	-- Countdown for whichever tab is showing
	----------------------------------------------------------------
	local header = text(root, L.QuestSmallSize, R.DimTextColor)
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 16)
	header.LayoutOrder = 1

	----------------------------------------------------------------
	-- Rows
	----------------------------------------------------------------
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.new(1, 0, 0, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.LayoutOrder = 2
	rows.Parent = root

	local rowList = Instance.new("UIListLayout")
	rowList.Padding = UDim.new(0, 4)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = rows

	local self = setmetatable({
		gui = gui,
		open = open,
		openBadge = openBadge,
		root = root,
		tabs = tabs,
		header = header,
		rows = rows,
		pool = {},
		conns = {},
		active = L.QuestLayers[1],
		snapshot = nil,
		remote = nil,
		isOpen = false,
	}, QuestHud)

	open.Activated:Connect(function()
		self:Toggle()
	end)
	for layer, tab in tabs do
		tab.button.Activated:Connect(function()
			self:Select(layer)
		end)
	end

	task.spawn(function()
		local remote = BloxKart:WaitForChild(Names.QUEST_REMOTE, 20)
		if not remote then
			return
		end
		self.remote = remote
		remote.OnClientEvent:Connect(function(snap)
			self:Apply(snap)
		end)
		-- Asked for rather than waited on. The server pushes on join, but
		-- a client that rebuilt its GUI would otherwise sit empty.
		remote:FireServer("refresh")
	end)

	return self
end

--=====================================================================
--  OPEN / SELECT
--=====================================================================
function QuestHud:Toggle(force: boolean?)
	self.isOpen = if force ~= nil then force else not self.isOpen
	self.root.Visible = self.isOpen
	if self.isOpen and self.remote then
		-- The panel can have been closed through a whole race.
		self.remote:FireServer("refresh")
	end
end

function QuestHud:IsOpen(): boolean
	return self.isOpen
end

function QuestHud:Select(layer: string)
	self.active = layer
	self:_draw()
end

--=====================================================================
--  ROWS
--=====================================================================
function QuestHud:_row(i: number): TextButton
	local row = self.pool[i]
	if row then
		return row
	end

	row = Instance.new("TextButton")
	row.Name = "Row" .. i
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Text = ""
	row.Size = UDim2.new(1, 0, 0, L.QuestRowHeight)
	row.LayoutOrder = i
	row.Parent = self.rows

	local what = text(row, L.QuestTextSize, R.TextColor)
	what.Name = "What"
	what.Position = UDim2.fromOffset(10, 6)
	what.Size = UDim2.new(1, -20, 0, 20)

	local reward = text(row, L.QuestSmallSize, R.AccentColor)
	reward.Name = "Reward"
	reward.Position = UDim2.fromOffset(10, 26)
	reward.Size = UDim2.new(0.65, -10, 0, 18)

	local count = text(row, L.QuestSmallSize, R.DimTextColor)
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -10, 0, 26)
	count.Size = UDim2.fromOffset(90, 18)
	count.TextXAlignment = Enum.TextXAlignment.Right

	local barBack = Instance.new("Frame")
	barBack.Name = "Bar"
	barBack.BackgroundColor3 = Color3.fromRGB(60, 60, 66)
	barBack.BorderSizePixel = 0
	barBack.AnchorPoint = Vector2.new(0, 1)
	barBack.Position = UDim2.new(0, 10, 1, -8)
	barBack.Size = UDim2.new(1, -20, 0, L.QuestBarHeight)
	barBack.Parent = row

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = R.AccentColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = barBack

	self.pool[i] = row
	return row
end

--=====================================================================
--  DRAW
--=====================================================================
local function rewardText(quest): string
	local bits = {}
	if quest.bolt and quest.bolt > 0 then
		table.insert(bits, ("%d BOLT"):format(quest.bolt))
	end
	if quest.crystals and quest.crystals > 0 then
		table.insert(bits, ("%d NITRO"):format(quest.crystals))
	end
	if quest.xp and quest.xp > 0 then
		table.insert(bits, ("%d XP"):format(quest.xp))
	end
	return table.concat(bits, "  ·  ")
end

local function claimableIn(data): boolean
	for _, quest in (data and data.rows or {}) do
		if quest.done and not quest.claimed then
			return true
		end
	end
	return false
end

function QuestHud:_draw()
	local snap = self.snapshot
	if not snap then
		return
	end

	-- Tab appearance, and a badge per layer so a closed tab can still
	-- say it has something waiting.
	local anyClaimable = false
	for layer, tab in self.tabs do
		local claimable = claimableIn(snap[layer])
		anyClaimable = anyClaimable or claimable
		tab.badge.Visible = claimable
		local isActive = layer == self.active
		tab.button.BackgroundColor3 = if isActive then L.QuestTabActive else L.QuestTabIdle
		tab.button.TextColor3 = if isActive then Color3.fromRGB(20, 20, 20) else R.DimTextColor
	end
	self.openBadge.Visible = anyClaimable

	local data = snap[self.active]
	local list = data and data.rows or {}

	for i, row in self.pool do
		row.Visible = i <= #list
	end

	for i, quest in list do
		local row = self:_row(i)
		row.Visible = true
		row.What.Text = quest.text
		row.Count.Text = ("%d / %d"):format(quest.have, quest.target)

		local frac = if quest.target > 0 then quest.have / quest.target else 0
		row.Bar.Fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)

		if quest.claimed then
			row.Bar.Fill.BackgroundColor3 = L.QuestBadgeColor
			row.What.TextColor3 = R.DimTextColor
			row.Reward.Text = "CLAIMED"
			row.Reward.TextColor3 = L.QuestBadgeColor
		elseif quest.done then
			row.Bar.Fill.BackgroundColor3 = L.QuestBadgeColor
			row.What.TextColor3 = R.TextColor
			row.Reward.Text = "CLAIM  ▸  " .. rewardText(quest)
			row.Reward.TextColor3 = L.QuestBadgeColor
		else
			row.Bar.Fill.BackgroundColor3 = R.AccentColor
			row.What.TextColor3 = R.TextColor
			row.Reward.Text = rewardText(quest)
			row.Reward.TextColor3 = R.AccentColor
		end

		-- REBOUND EVERY DRAW. The pool is shared across tabs, so row 1 is
		-- a different quest depending on which layer is showing — a
		-- handler bound once would claim whatever was there when the row
		-- was created.
		--
		-- Held beside the instance rather than on it: Roblox objects
		-- reject unknown fields.
		local existing = self.conns[i]
		if existing then
			existing:Disconnect()
		end
		local slot, layer = quest.slot, self.active
		local canClaim = quest.done and not quest.claimed
		self.conns[i] = row.Activated:Connect(function()
			if self.remote and canClaim then
				self.remote:FireServer("claim", layer, slot)
			end
		end)
	end
end

function QuestHud:Apply(snap)
	if typeof(snap) ~= "table" then
		return
	end
	self.snapshot = snap
	self:_draw()
end

-- Only the countdown ticks. Everything else moves when the server says
-- so, and redrawing a static list every frame is waste.
function QuestHud:Update()
	if not self.isOpen or not self.snapshot then
		return
	end
	local data = self.snapshot[self.active]
	if not data then
		self.header.Text = ""
		return
	end
	self.header.Text = ("RESETS IN  %s"):format(clockText((data.endsAt or 0) - os.time()))
end

function QuestHud:Destroy()
	for _, c in self.conns do
		c:Disconnect()
	end
	self.gui:Destroy()
end

return QuestHud
