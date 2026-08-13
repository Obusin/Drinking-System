--[[
	RivalSpotlight — brief, personal feedback for a place change.

	The server names the racer and change in rank. The card does not infer an
	overtake from locally visible karts, because streaming can remove the most
	important opponent from this client exactly when they are far ahead.
	A later ViewportFrame kart preview can attach to this same card without
	changing its event contract.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Device = require(BloxKart:WaitForChild("Device"))
local Names = require(BloxKart:WaitForChild("Names"))
local Util = require(BloxKart:WaitForChild("Util"))

local H = Config.Hud
local R = Config.Rewards
local FONT = Util.font(H.FontName, H.FontWeight)

local RivalSpotlight = {}
RivalSpotlight.__index = RivalSpotlight

local function sourceKartFor(opponent: any): Model?
	for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
		if kart:IsA("Model") and kart.Parent then
			if type(opponent.userId) == "number" and kart:GetAttribute(Names.OWNER) == opponent.userId then
				return kart
			end
			if type(opponent.name) == "string" and kart:GetAttribute(Names.RACER_NAME) == opponent.name then
				return kart
			end
		end
	end
	return nil
end

local function cloneForViewport(source: Model): Model?
	local wasArchivable = source.Archivable
	source.Archivable = true
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	source.Archivable = wasArchivable
	if not ok or not clone or not clone:IsA("Model") then
		return nil
	end
	for _, item in clone:GetDescendants() do
		if item:IsA("BaseScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	return clone
end

local function motorPairs(source: Instance, clone: Instance): { { Motor6D } }
	local originals, copies = {}, {}
	for _, item in source:GetDescendants() do
		if item:IsA("Motor6D") then
			table.insert(originals, item)
		end
	end
	for _, item in clone:GetDescendants() do
		if item:IsA("Motor6D") then
			table.insert(copies, item)
		end
	end
	local pairs = {}
	for i = 1, math.min(#originals, #copies) do
		table.insert(pairs, { originals[i], copies[i] })
	end
	return pairs
end

local function ordinal(n: number): string
	local mod100 = n % 100
	local suffix = if mod100 >= 11 and mod100 <= 13
		then "TH"
		else if n % 10 == 1 then "ST" else if n % 10 == 2 then "ND" else if n % 10 == 3 then "RD" else "TH"
	return tostring(n) .. suffix
end

function RivalSpotlight.new()
	local mobile = Device.touchLayout()
	local width = if mobile then H.MobileRivalWidth else H.RivalWidth
	local height = if mobile then H.MobileRivalHeight else H.RivalHeight
	local position = if mobile then H.MobileRivalPosition else H.RivalPosition
	local headlineSize = if mobile then 10 else 13
	local nameSize = if mobile then 13 else 18
	local changeSize = if mobile then 9 else 12
	local visualSize = height - 10

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartRival"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local card = Instance.new("Frame")
	card.Name = "Spotlight"
	card.AnchorPoint = Vector2.new(1, 0)
	card.Position = position
	card.Size = UDim2.fromOffset(width, height)
	card.BackgroundColor3 = R.PanelColor
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Rotation = R.PanelTilt
	card.ClipsDescendants = true
	card.Visible = false
	card.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Name = "FineEdge"
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = card

	-- The same clipped diagonal geometry as the results panels and transition
	-- wipe. It says "race event" at a glance without turning a brief report
	-- into another large HUD panel.
	local accentSlab = Instance.new("Frame")
	accentSlab.Name = "DiagonalAccent"
	accentSlab.AnchorPoint = Vector2.new(0.5, 0.5)
	accentSlab.Position = UDim2.fromOffset(3, height / 2)
	accentSlab.Size = UDim2.fromOffset(15, height + 34)
	accentSlab.Rotation = R.WipeAngle
	accentSlab.BackgroundTransparency = 1
	accentSlab.BorderSizePixel = 0
	accentSlab.Parent = card
	local accentGlow = Instance.new("UIGradient")
	accentGlow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.58),
	})
	accentGlow.Rotation = 90
	accentGlow.Parent = accentSlab

	local topRule = Instance.new("Frame")
	topRule.Name = "TopRule"
	topRule.Position = UDim2.fromOffset(0, 0)
	topRule.Size = UDim2.new(1, 0, 0, 2)
	topRule.BackgroundTransparency = 1
	topRule.BorderSizePixel = 0
	topRule.Parent = card

	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.BackgroundColor3 = Color3.fromRGB(59, 87, 126)
	portrait.BackgroundTransparency = 1
	portrait.BorderSizePixel = 0
	portrait.Position = UDim2.fromOffset(height - 28, height - 28)
	portrait.Size = UDim2.fromOffset(23, 23)
	portrait.Image = ""
	portrait.Parent = card
	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(1, 0)
	portraitCorner.Parent = portrait

	-- A local scene, never the real world model. It is deliberately small:
	-- the card is a moment of recognition, not a second camera competing
	-- with the road. When streaming has the source kart, we clone its art
	-- and mirror visual joints; otherwise the portrait remains the fallback.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "KartPreview"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Position = UDim2.fromOffset(5, 5)
	viewport.Size = UDim2.fromOffset(visualSize, visualSize)
	viewport.Ambient = Color3.fromRGB(210, 220, 255)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Visible = false
	viewport.Parent = card
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 38
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local headline = Instance.new("TextLabel")
	headline.Name = "Headline"
	headline.BackgroundTransparency = 1
	headline.Position = UDim2.fromOffset(height, if mobile then 4 else 7)
	headline.Size = UDim2.new(1, -height - 9, 0, if mobile then 11 else 16)
	headline.FontFace = FONT
	headline.TextSize = headlineSize
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.TextStrokeColor3 = Color3.new(0, 0, 0)
	headline.TextStrokeTransparency = 1
	headline.Parent = card

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(height, if mobile then 15 else 23)
	name.Size = UDim2.new(1, -height - 9, 0, if mobile then 14 else 19)
	name.FontFace = FONT
	name.TextSize = nameSize
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeColor3 = Color3.new(0, 0, 0)
	name.TextStrokeTransparency = 1
	name.Parent = card

	local change = Instance.new("TextLabel")
	change.Name = "Change"
	change.BackgroundTransparency = 1
	change.Position = UDim2.fromOffset(height, if mobile then 30 else 43)
	change.Size = UDim2.new(1, -height - 9, 0, if mobile then 11 else 13)
	change.FontFace = FONT
	change.TextSize = changeSize
	change.TextXAlignment = Enum.TextXAlignment.Left
	change.TextColor3 = Color3.fromRGB(182, 194, 215)
	change.TextStrokeColor3 = Color3.new(0, 0, 0)
	change.TextStrokeTransparency = 1
	change.Parent = card

	return setmetatable({
		gui = gui,
		card = card,
		stroke = stroke,
		accentSlab = accentSlab,
		topRule = topRule,
		portrait = portrait,
		viewport = viewport,
		world = world,
		camera = camera,
		headline = headline,
		name = name,
		change = change,
		untilAt = 0,
		previewOpponent = nil,
		previewKart = nil,
		previewPairs = {},
		nextPreviewAt = 0,
		basePosition = position,
	}, RivalSpotlight)
end

function RivalSpotlight:_clearPreview()
	self.world:ClearAllChildren()
	self.previewKart = nil
	self.previewPairs = {}
	self.viewport.Visible = false
end

function RivalSpotlight:_tryPreview()
	local opponent = self.previewOpponent
	if type(opponent) ~= "table" then
		return
	end
	local source = sourceKartFor(opponent)
	if not source then
		return
	end
	if source == self.previewKart then
		return
	end

	self:_clearPreview()
	local clone = cloneForViewport(source)
	if not clone then
		return
	end
	clone:PivotTo(CFrame.new())
	clone.Parent = self.world
	local pairs = motorPairs(source, clone)

	-- If the remote character is streamed too, include its seated avatar.
	-- It inherits the exact kart-relative pose at clone time, while the
	-- joint copy below keeps visible hand/wheel movement in sync.
	local seat = source:FindFirstChild("Seat")
	local occupant = seat and seat:IsA("VehicleSeat") and seat.Occupant
	local character = occupant and occupant.Parent
	if character and character:IsA("Model") then
		local rider = cloneForViewport(character)
		if rider then
			local relative = source:GetPivot():ToObjectSpace(character:GetPivot())
			rider:PivotTo(clone:GetPivot() * relative)
			rider.Parent = self.world
			for _, pair in motorPairs(character, rider) do
				table.insert(pairs, pair)
			end
		end
	end

	local _, size = clone:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.62
	local focus = Vector3.new(0, math.max(size.Y * 0.08, 0), 0)
	self.camera.CFrame = CFrame.lookAt(
		focus + Vector3.new(radius * 1.45, radius * 0.8, radius * 1.75),
		focus
	)
	self.previewKart = source
	self.previewPairs = pairs
	self.viewport.Visible = true
end

function RivalSpotlight:Show(message: any)
	if type(message) ~= "table" then
		return
	end
	local hit = message.kind == "hit"
	if not hit and (type(message.from) ~= "number" or type(message.to) ~= "number") then
		return
	end
	local lost = message.kind == "overtaken"
	local opponent = type(message.opponent) == "table" and message.opponent or {}
	self.previewOpponent = opponent
	self.nextPreviewAt = 0
	self:_clearPreview()
	self.headline.Text = if hit then "HIT BY" else if lost then "OVERTAKEN BY" else "POSITION GAINED"
	self.headline.TextColor3 = if hit or lost then Color3.fromRGB(255, 125, 115) else Color3.fromRGB(120, 224, 168)
	self.stroke.Color = self.headline.TextColor3
	self.accentSlab.BackgroundColor3 = self.headline.TextColor3
	self.topRule.BackgroundColor3 = self.headline.TextColor3
	self.name.Text = tostring(opponent.name or "Rival")
	self.change.Text = if hit then string.upper(tostring(message.item or "POWER-UP")) else ("%s  →  %s"):format(ordinal(message.from), ordinal(message.to))
	self.portrait.Image = ""
	self.portrait.BackgroundColor3 = if lost then Color3.fromRGB(122, 59, 66) else Color3.fromRGB(47, 105, 83)
	self.card.Position = self.basePosition + UDim2.fromOffset(32, 0)
	self.card.Visible = true
	TweenService:Create(
		self.card,
		TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = self.basePosition }
	):Play()
	self.untilAt = os.clock() + H.RivalHold

	local userId = opponent.userId
	if type(userId) == "number" and userId > 0 then
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			if ok and type(image) == "string" and self.card.Visible then
				self.portrait.Image = image
			end
		end)
	end
end

function RivalSpotlight:Update()
	if not self.card.Visible then
		return
	end
	local remaining = self.untilAt - os.clock()
	if remaining <= 0 then
		self.card.Visible = false
		self:_clearPreview()
		return
	end
	if not self.previewKart and os.clock() >= self.nextPreviewAt then
		self.nextPreviewAt = os.clock() + 0.25
		self:_tryPreview()
	end
	if self.previewKart and not self.previewKart.Parent then
		self:_clearPreview()
	end
	for _, pair in self.previewPairs do
		local source, clone = pair[1], pair[2]
		if source.Parent and clone.Parent then
			clone.Transform = source.Transform
		end
	end
	local fade = math.clamp(remaining / H.RivalFade, 0, 1)
	self.card.BackgroundTransparency = 0.14 + (1 - fade) * 0.86
	self.stroke.Transparency = 1 - fade
	self.accentSlab.BackgroundTransparency = 1 - fade
	self.topRule.BackgroundTransparency = 1 - fade
	self.portrait.BackgroundTransparency = 1 - fade
	self.portrait.ImageTransparency = 1 - fade
	self.viewport.ImageTransparency = 1 - fade
	self.headline.TextTransparency = 1 - fade
	self.name.TextTransparency = 1 - fade
	self.change.TextTransparency = 1 - fade
	self.headline.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * (1 - fade)
	self.name.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * (1 - fade)
	self.change.TextStrokeTransparency = H.StrokeTransparency + (1 - H.StrokeTransparency) * (1 - fade)
end

return RivalSpotlight
