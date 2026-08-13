--[[
	LiveStandingsHud — authoritative top-five running order.

	The server sends a compact ordered snapshot rather than asking each client
	to enumerate streamed karts. A row belongs to a racer, not a rank: when the
	order changes that same row tweens into its new slot and gets a small bounce.
	That makes an overtake read as movement, not five names being replaced.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Device = require(BloxKart:WaitForChild("Device"))
local Util = require(BloxKart:WaitForChild("Util"))

local H = Config.Hud
local FONT = Util.font(H.FontName, H.FontWeight)

local LiveStandingsHud = {}
LiveStandingsHud.__index = LiveStandingsHud

local function makeText(parent: Instance, size: UDim2, pos: UDim2, textSize: number, align: Enum.TextXAlignment)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(232, 238, 250)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.6
	label.TextXAlignment = align
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

function LiveStandingsHud.new()
	local mobile = Device.touchLayout()
	local width = if mobile then H.MobileStandingsWidth else H.StandingsWidth
	local rowHeight = if mobile then H.MobileStandingsRowHeight else H.StandingsRowHeight
	local titleSize = if mobile then H.MobileStandingsTitleSize else H.StandingsTitleSize
	local nameSize = if mobile then H.MobileStandingsNameSize else H.StandingsNameSize
	local titleHeight = if mobile then 18 else 22
	local selfHeight = if mobile then 27 else 34

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartLiveStandings"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "TopFive"
	panel.AnchorPoint = H.StandingsAnchor
	panel.Position = if mobile then H.MobileStandingsPosition else H.StandingsPosition
	panel.Size = UDim2.fromOffset(width, titleHeight + rowHeight * H.StandingsRows + selfHeight + 8)
	-- The race instruments are text floating over the track. Keep the
	-- standings in that same language: this frame only anchors labels.
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local title = makeText(panel, UDim2.new(1, -16, 0, titleHeight), UDim2.fromOffset(8, 0), titleSize, Enum.TextXAlignment.Left)
	title.Text = "LIVE ORDER"
	title.TextColor3 = H.RaceLabelColor

	-- Your rank remains readable even outside the displayed top five.
	-- It is text, not a second card, so the complete readout stays quiet.
	local selfBar = Instance.new("Frame")
	selfBar.Name = "YourPlace"
	selfBar.Size = UDim2.new(1, -10, 0, selfHeight - 3)
	selfBar.Position = UDim2.fromOffset(5, titleHeight + rowHeight * H.StandingsRows + 3)
	selfBar.BackgroundTransparency = 1
	selfBar.BorderSizePixel = 0
	selfBar.Parent = panel
	local selfScale = Instance.new("UIScale")
	selfScale.Parent = selfBar

	local selfCaption = makeText(selfBar, UDim2.new(0.4, 0, 1, 0), UDim2.fromOffset(7, 0), if mobile then 9 else 11, Enum.TextXAlignment.Left)
	selfCaption.Text = "YOU"
	selfCaption.TextColor3 = Color3.fromRGB(183, 232, 248)
	local selfPlace = makeText(selfBar, UDim2.new(0.32, 0, 1, 0), UDim2.new(0.42, 0, 0, 0), if mobile then 15 else 19, Enum.TextXAlignment.Right)
	selfPlace.Text = "—"
	local selfField = makeText(selfBar, UDim2.new(0.22, -4, 1, 0), UDim2.new(0.76, 0, 0, 0), if mobile then 9 else 11, Enum.TextXAlignment.Right)
	selfField.Text = ""
	selfField.TextColor3 = Color3.fromRGB(183, 232, 248)

	return setmetatable({
		gui = gui,
		panel = panel,
		rows = {},
		rowHeight = rowHeight,
		titleHeight = titleHeight,
		width = width,
		nameSize = nameSize,
		selfPlace = selfPlace,
		selfField = selfField,
		selfScale = selfScale,
		myPlace = 0,
		myField = 0,
		visible = true,
	}, LiveStandingsHud)
end

function LiveStandingsHud:_makeRow(data)
	local row = Instance.new("Frame")
	row.Name = "Racer_" .. data.id
	row.Size = UDim2.new(1, -10, 0, self.rowHeight - 2)
	row.AnchorPoint = Vector2.new(0, 0)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Parent = self.panel
	local scale = Instance.new("UIScale")
	scale.Parent = row

	local rank = makeText(row, UDim2.fromOffset(29, self.rowHeight - 2), UDim2.fromOffset(6, 0), self.nameSize, Enum.TextXAlignment.Left)
	local name = makeText(row, UDim2.new(1, -46, 1, 0), UDim2.fromOffset(37, 0), self.nameSize, Enum.TextXAlignment.Left)

	local entry = { frame = row, rank = rank, name = name, scale = scale, place = 0 }
	self.rows[data.id] = entry
	return entry
end

function LiveStandingsHud:_apply(entry, data, moved: boolean)
	entry.rank.Text = "#" .. data.place
	entry.name.Text = data.name
	local ours = typeof(data.userId) == "number" and data.userId == Players.LocalPlayer.UserId
	local colour = if ours
		then Color3.fromRGB(135, 224, 255)
		elseif data.place == 1 then Color3.fromRGB(255, 210, 110)
		else Color3.fromRGB(232, 238, 250)
	entry.rank.TextColor3 = colour
	entry.name.TextColor3 = colour

	local target = UDim2.fromOffset(5, self.titleHeight + (data.place - 1) * self.rowHeight + 3)
	if moved then
		TweenService:Create(entry.frame, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
		entry.scale.Scale = 1
		TweenService:Create(entry.scale, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.07 }):Play()
		task.delay(0.13, function()
			if entry.scale.Parent then
				TweenService:Create(entry.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end)
	else
		entry.frame.Position = target
	end
	entry.place = data.place
end

function LiveStandingsHud:Update(entries)
	if typeof(entries) ~= "table" then
		return
	end
	local seen = {}
	for _, data in entries do
		if typeof(data) == "table" and typeof(data.id) == "string" and typeof(data.place) == "number" then
			seen[data.id] = true
			local entry = self.rows[data.id]
			local created = entry == nil
			entry = entry or self:_makeRow(data)
			self:_apply(entry, data, not created and entry.place ~= data.place)
		end
	end
	for id, entry in self.rows do
		if not seen[id] then
			self.rows[id] = nil
			entry.frame:Destroy()
		end
	end
end

function LiveStandingsHud:SetMyPlace(place: number, field: number)
	if typeof(place) ~= "number" or place < 1 then
		return
	end
	field = if typeof(field) == "number" and field > 0 then field else 0
	if place == self.myPlace and field == self.myField then
		return
	end

	local changed = place ~= self.myPlace and self.myPlace > 0
	self.myPlace = place
	self.myField = field
	self.selfPlace.Text = "P" .. place
	self.selfField.Text = if field > 0 then "/ " .. field else ""

	if changed then
		self.selfScale.Scale = 1
		TweenService:Create(self.selfScale, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
		task.delay(0.13, function()
			if self.selfScale.Parent then
				TweenService:Create(self.selfScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end)
	end
end

function LiveStandingsHud:SetVisible(on: boolean)
	self.visible = on
	self.gui.Enabled = on
end

function LiveStandingsHud:Destroy()
	self.gui:Destroy()
end

return LiveStandingsHud
