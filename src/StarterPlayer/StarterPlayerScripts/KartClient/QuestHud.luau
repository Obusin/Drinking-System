--[[
	QuestHud — the challenge list, left edge.

	Follows the reference: a header with the time left in the period,
	then a row per quest carrying its own reward, progress bar and
	count. Rows that are complete turn green and can be claimed.

	IT DRAWS A SNAPSHOT AND NOTHING ELSE.
	-------------------------------------
	The server sends the whole list — text, target, progress, claimed —
	and this renders it. No local counting, no predicting, no deciding
	whether something is done. A client that works out its own quest
	progress is a client that can be wrong about it, and being wrong
	about a reward is the one place it matters.

	Rows are pooled and rebuilt in place, because the panel is redrawn
	whenever the server pushes and creating a dozen instances per push
	is churn for a screen that mostly does not change.
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

function QuestHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartQuests"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.BackgroundTransparency = 1
	root.Position = L.QuestPosition
	root.Size = UDim2.fromOffset(L.QuestWidth, 10)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local self = setmetatable({
		gui = gui,
		root = root,
		sections = {},
		snapshot = nil,
		remote = nil,
	}, QuestHud)

	task.spawn(function()
		local remote = BloxKart:WaitForChild(Names.QUEST_REMOTE, 20)
		if not remote then
			return
		end
		self.remote = remote
		remote.OnClientEvent:Connect(function(snap)
			self:Apply(snap)
		end)
		-- Ask, rather than wait to be told. The server pushes on join,
		-- but a client that reloads its GUI would otherwise sit empty
		-- until the next claim.
		remote:FireServer("refresh")
	end)

	return self
end

--=====================================================================
--  BUILD
--=====================================================================
function QuestHud:_section(layer: string, order: number)
	local section = self.sections[layer]
	if section then
		return section
	end

	local frame = Instance.new("Frame")
	frame.Name = layer
	frame.BackgroundColor3 = L.QuestPanelColor
	frame.BackgroundTransparency = L.QuestPanelTransparency
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, L.QuestHeaderHeight)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	frame.Parent = self.root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = frame

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame

	local title = text(frame, L.QuestTitleSize, R.DimTextColor)
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, L.QuestHeaderHeight - 8)
	title.LayoutOrder = 0

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.new(1, 0, 0, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.LayoutOrder = 1
	rows.Parent = frame

	local rowList = Instance.new("UIListLayout")
	rowList.Padding = UDim.new(0, 4)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = rows

	section = { frame = frame, title = title, rows = rows, pool = {}, endsAt = 0 }
	self.sections[layer] = section
	return section
end

function QuestHud:_row(section, i: number)
	local row = section.pool[i]
	if row then
		return row
	end

	local frame = Instance.new("TextButton")
	frame.Name = "Row" .. i
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.AutoButtonColor = false
	frame.Text = ""
	frame.Size = UDim2.new(1, 0, 0, L.QuestRowHeight)
	frame.LayoutOrder = i
	frame.Parent = section.rows

	local what = text(frame, L.QuestTextSize, R.TextColor)
	what.Name = "What"
	what.Position = UDim2.fromOffset(10, 6)
	what.Size = UDim2.new(1, -20, 0, 20)

	local reward = text(frame, L.QuestSmallSize, R.AccentColor)
	reward.Name = "Reward"
	reward.Position = UDim2.fromOffset(10, 26)
	reward.Size = UDim2.new(0.6, -10, 0, 18)

	local count = text(frame, L.QuestSmallSize, R.DimTextColor)
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
	barBack.Parent = frame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = R.AccentColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = barBack

	section.pool[i] = frame
	return frame
end

--=====================================================================
--  APPLY
--=====================================================================
function QuestHud:Apply(snap)
	if typeof(snap) ~= "table" then
		return
	end
	self.snapshot = snap

	for order, layer in L.QuestLayers do
		local data = snap[layer]
		local section = self:_section(layer, order)
		section.frame.Visible = data ~= nil
		if not data then
			continue
		end
		section.endsAt = data.endsAt or 0

		local rows = data.rows or {}
		for i, row in section.pool do
			row.Visible = i <= #rows
		end

		for i, quest in rows do
			local row = self:_row(section, i)
			row.Visible = true
			row.What.Text = quest.text
			row.Count.Text = ("%d / %d"):format(quest.have, quest.target)

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
			row.Reward.Text = table.concat(bits, "  ·  ")

			local frac = if quest.target > 0 then quest.have / quest.target else 0
			row.Bar.Fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)

			if quest.claimed then
				row.Bar.Fill.BackgroundColor3 = L.QuestDoneColor
				row.What.TextColor3 = R.DimTextColor
				row.Reward.Text = "CLAIMED"
				row.Reward.TextColor3 = L.QuestDoneColor
			elseif quest.done then
				row.Bar.Fill.BackgroundColor3 = L.QuestDoneColor
				row.What.TextColor3 = R.TextColor
				row.Reward.Text = "CLAIM  ▸  " .. row.Reward.Text
				row.Reward.TextColor3 = L.QuestDoneColor
			else
				row.Bar.Fill.BackgroundColor3 = R.AccentColor
				row.What.TextColor3 = R.TextColor
				row.Reward.TextColor3 = R.AccentColor
			end

			-- Rebound every apply, because the slot a row shows can
			-- change. A connection made once would claim whatever quest
			-- happened to be in that row when the panel was built.
			if row._conn then
				row._conn:Disconnect()
			end
			local slot, layerName = quest.slot, layer
			row._conn = row.Activated:Connect(function()
				if self.remote and quest.done and not quest.claimed then
					self.remote:FireServer("claim", layerName, slot)
				end
			end)
		end
	end
end

-- Only the countdown ticks. Everything else changes when the server
-- says so, and redrawing a static list every frame is waste.
function QuestHud:Update()
	local now = os.time()
	for _, layer in L.QuestLayers do
		local section = self.sections[layer]
		if section and section.frame.Visible then
			section.title.Text = ("%s CHALLENGES     %s"):format(
				string.upper(layer),
				clockText(section.endsAt - now)
			)
		end
	end
end

function QuestHud:Destroy()
	self.gui:Destroy()
end

return QuestHud
