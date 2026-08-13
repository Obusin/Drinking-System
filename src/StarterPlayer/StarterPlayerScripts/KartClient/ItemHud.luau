--[[
	ItemHud — held items.

	Top left because that's where the reference puts the item slot, and
	because the speedo cluster already owns bottom right.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Device = require(BloxKart:WaitForChild("Device"))
local Util = require(BloxKart:WaitForChild("Util"))
local H = Config.Hud

local ItemHud = {}
ItemHud.__index = ItemHud

-- Bad image ids fail silently; Util.verifyImage says which one did.
local function verify(label: ImageLabel, id: string)
	Util.verifyImage(label, id, "ItemHud")
end

local FONT = Util.font(H.FontName, H.FontWeight)

function ItemHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartItem"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local MAX = Config.Items.MaxHeld

	-- Same Device answer every other HUD uses. On touch the cluster sits
	-- beside the centred speed readout rather than beside the nitro bar,
	-- because the mobile layout stacks those two differently.
	local mobile = Device.touchLayout()
	local SLOT = if mobile then H.MobileItemSlotSize else H.ItemSlotSize
	local GAP = if mobile then H.MobileItemSlotGap else H.ItemSlotGap

	local panel = Instance.new("Frame")
	panel.AnchorPoint = if mobile then H.MobileItemAnchor else H.ItemAnchor
	panel.Position = if mobile then H.MobileItemPosition else H.ItemPosition
	panel.Size = UDim2.fromOffset(MAX * SLOT + (MAX - 1) * GAP, SLOT)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	-- One box per slot. Front of the queue is leftmost, and it's the one
	-- that fires next — reading left to right is reading your spend order.
	local slots = {}
	for i = 1, MAX do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.fromOffset(SLOT, SLOT)
		slot.Position = UDim2.fromOffset((i - 1) * (SLOT + GAP), 0)
		slot.BackgroundTransparency = 1
		slot.Parent = panel

		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 10)
		round.Parent = slot

		local stroke = Instance.new("UIStroke")
		stroke.Color = H.NitroRimColor
		stroke.Thickness = H.DialRimThickness
		-- Empty slots sit back so a full stack reads as brighter, not just
		-- more text.
		stroke.Transparency = H.DialRimTransparency
		stroke.Parent = slot

		table.insert(slots, { frame = slot, stroke = stroke })
	end

	local function text(parent, size, colour, pos, height, align)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, 0, height)
		l.Position = pos
		l.BackgroundTransparency = 1
		l.FontFace = FONT
		l.TextSize = size
		l.TextColor3 = colour
		l.TextXAlignment = align or Enum.TextXAlignment.Center
		l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		l.TextStrokeTransparency = H.StrokeTransparency
		l.Text = ""
		l.Parent = parent
		return l
	end

	for _, entry in slots do
		-- Icon fills the slot; the name is a caption under it. Icons read
		-- at a glance mid-corner, names confirm what you're looking at.
		-- Tinted tile UNDER the icon. Normally hidden behind the artwork;
		-- if an image never loads it's what you see instead, so a bad
		-- asset degrades to a coloured chip rather than an empty box.
		local tile = Instance.new("Frame")
		tile.Name = "Tile"
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = UDim2.fromScale(0.5, 0.42)
		tile.Size = UDim2.fromScale(0.5, 0.5)
		tile.BackgroundTransparency = 1
		tile.BorderSizePixel = 0
		tile.ZIndex = 1
		tile.Parent = entry.frame
		local tileRound = Instance.new("UICorner")
		tileRound.CornerRadius = UDim.new(0, 6)
		tileRound.Parent = tile
		entry.tile = tile

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromScale(0.78, 0.78)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.42)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 2
		icon.Image = ""
		icon.Parent = entry.frame
		entry.icon = icon

		entry.label = text(entry.frame, 9, H.SpeedUnitColor, UDim2.new(0, 0, 1, -15), 14)
	end

	return setmetatable({ gui = gui, slots = slots }, ItemHud)
end

function ItemHud:Update(slots)
	for i, entry in self.slots do
		local data = slots[i]
		entry.label.Text = if data then data.name else ""

		local wanted = if data then data.icon else ""
		if entry.icon.Image ~= wanted then
			entry.icon.Image = wanted
			verify(entry.icon, wanted)
		end

		-- Tile shows only when the artwork isn't there to cover it.
		local loaded = wanted ~= "" and entry.icon.IsLoaded
		entry.tile.BackgroundColor3 = (data and data.tint) or H.NitroEmptyColor
		entry.tile.BackgroundTransparency = if data and not loaded then 0.15 else 1

		if not data then
			entry.stroke.Transparency = H.DialRimTransparency
			entry.label.TextColor3 = H.SpeedUnitColor
			entry.icon.ImageTransparency = 1
		elseif data.rolling then
			-- Dimmed while spinning, so a slot you can't fire yet doesn't
			-- look like one you can.
			entry.stroke.Transparency = 0.5
			entry.label.TextColor3 = H.SpeedUnitColor
			entry.icon.ImageTransparency = 0.45
		else
			entry.stroke.Transparency = 0
			entry.label.TextColor3 = H.SpeedTextColor
			entry.icon.ImageTransparency = 0
		end
	end

end

-- Off when there is no kart. The slots describe what you are holding,
-- and on foot you are holding nothing — three empty boxes in the corner
-- of a hub is furniture that means nothing.
function ItemHud:SetVisible(on: boolean)
	self.gui.Enabled = on
end

function ItemHud:Destroy()
	self.gui:Destroy()
end

return ItemHud
