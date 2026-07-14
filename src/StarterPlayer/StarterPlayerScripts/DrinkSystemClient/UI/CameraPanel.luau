--[[
	CameraPanel - a camera-space "3D UI" panel: a real Part parented to the
	local camera with a SurfaceGui on it. Opening flips the panel into the
	player's view, then hover adds small parallax/tilt so it feels physical.
--]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraPanel = {}
CameraPanel.__index = CameraPanel

export type Config = {
	SizeStuds: Vector2?,
	Offset: CFrame?,
	ClosedOffset: CFrame?,
	Lag: number?,
	ImageId: (number | string)?,
	PixelsPerStud: number?,
	OpenDuration: number?,
	CloseDuration: number?,
	HoverTiltDegrees: number?,
	ContentFadeDuration: number?,
}

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

local function smoothStep(value: number): number
	local t = clamp01(value)
	return t * t * (3 - 2 * t)
end

local function easeOutBack(value: number): number
	local t = clamp01(value) - 1
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * t * t * t + c1 * t * t
end

local function moveTowards(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

local function buildSurface(part: BasePart, face: EnumItem, config: Config, images: { ImageLabel }): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = face == Enum.NormalId.Back and "Panel" or "PanelReverse"
	gui.Face = face
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.PixelsPerStud = config.PixelsPerStud or 180
	gui.Enabled = false
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.Name = "Surface"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = false
	frame.Parent = gui

	if config.ImageId then
		-- Glass card: rounded backing panel + the menu image on top, framed
		-- by a translucent "glassy" stroke and a soft top-down sheen.
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
		card.BackgroundTransparency = 0.15
		card.BorderSizePixel = 0
		card.ClipsDescendants = true
		card.Parent = frame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 28)
		corner.Parent = card

		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = "rbxassetid://" .. tostring(config.ImageId)
		image.ImageTransparency = 1
		-- Fit preserves the image's aspect ratio (no stretching/distortion)
		image.ScaleType = Enum.ScaleType.Fit
		image.ResampleMode = Enum.ResamplerMode.Default
		image.Parent = card
		table.insert(images, image)

		-- Glassy sheen: subtle light-to-transparent gradient across the card
		local sheen = Instance.new("Frame")
		sheen.Name = "Sheen"
		sheen.Size = UDim2.fromScale(1, 1)
		sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		sheen.BackgroundTransparency = 0.92
		sheen.BorderSizePixel = 0
		sheen.Parent = card
		local sheenGrad = Instance.new("UIGradient")
		sheenGrad.Rotation = 115
		sheenGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.35, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sheenGrad.Parent = sheen

		-- Glassy stroke: translucent white edge with a light-catching gradient
		local stroke = Instance.new("UIStroke")
		stroke.Name = "GlassStroke"
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.35
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
		local strokeGrad = Instance.new("UIGradient")
		strokeGrad.Rotation = 90
		strokeGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 0.7),
		})
		strokeGrad.Parent = stroke
	end

	return gui
end

function CameraPanel.new(config: Config)
	local self = setmetatable({}, CameraPanel)

	self._offset = config.Offset or CFrame.new(0, -0.05, -4)
	self._closedOffset = config.ClosedOffset
		or CFrame.new(0, 0.05, -2.6) * CFrame.Angles(math.rad(-4), math.rad(82), math.rad(-4))
	self._lag = math.clamp(config.Lag or 0.18, 0, 1)
	self._openDuration = math.max(config.OpenDuration or 0.42, 0.01)
	self._closeDuration = math.max(config.CloseDuration or 0.2, 0.01)
	self._contentFadeDuration = math.max(config.ContentFadeDuration or 0.12, 0.01)
	self._hoverTiltDegrees = config.HoverTiltDegrees or 7
	self._visible = false
	self._targetVisible = false
	self._rendering = false
	self._openAlpha = 0
	self._hoverAlpha = 0
	self._hoverX = 0
	self._hoverY = 0

	-- Zoom/pan of the image inside the card (targets are what input sets;
	-- displayed values chase them each frame for smoothness)
	self._zoom = 1
	self._zoomTarget = 1
	self._panX = 0
	self._panY = 0
	self._panTargetX = 0
	self._panTargetY = 0

	local size = config.SizeStuds or Vector2.new(3, 2)
	self._baseSize = Vector3.new(size.X, size.Y, 0.05)

	local part = Instance.new("Part")
	part.Name = "DS_CameraPanel"
	part.Size = self._baseSize
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	self.Part = part

	self.Images = {}
	self.Gui = buildSurface(part, Enum.NormalId.Back, config, self.Images)
	self.ReverseGui = buildSurface(part, Enum.NormalId.Front, config, self.Images)
	self.Image = self.Images[1]

	-- Auto-fit the panel to the image's REAL resolution: once the asset loads,
	-- read its pixel size and reshape the part so the card matches the image's
	-- aspect ratio exactly (no letterboxing, no distortion). Height is kept
	-- from SizeStuds; width follows the image.
	if self.Image then
		task.spawn(function()
			local img = self.Image
			pcall(function()
				img:SetEnableContentImageSizeChangedEvents(true)
			end)
			local deadline = os.clock() + 20
			while os.clock() < deadline do
				local ok, pixels = pcall(function()
					if not img.IsLoaded then
						return nil
					end
					return img.ContentImageSize
				end)
				if ok and pixels and pixels.X > 1 and pixels.Y > 1 then
					local aspect = pixels.X / pixels.Y
					self._baseSize = Vector3.new(self._baseSize.Y * aspect, self._baseSize.Y, self._baseSize.Z)
					print(("[CameraPanel] image is %dx%d px — panel fitted to %.2f:1"):format(pixels.X, pixels.Y, aspect))
					return
				end
				task.wait(0.2)
			end
			warn("[CameraPanel] could not read image resolution; panel keeps its configured size")
		end)
	end

	self._currentCF = nil :: CFrame?
	self._conn = RunService.RenderStepped:Connect(function(dt)
		if not self._rendering then return end
		local cam = workspace.CurrentCamera
		if not cam then return end

		if part.Parent ~= cam then
			part.Parent = cam
		end

		local desiredAlpha = self._targetVisible and 1 or 0
		local duration = self._targetVisible and self._openDuration or self._closeDuration
		self._openAlpha = moveTowards(self._openAlpha, desiredAlpha, dt / duration)

		if not self._targetVisible and self._openAlpha <= 0 then
			self._rendering = false
			self._visible = false
			self.Gui.Enabled = false
			self.ReverseGui.Enabled = false
			part.Parent = nil
			self._currentCF = nil
			return
		end

		self:_updateHover(cam, dt)

		local openEase = smoothStep(self._openAlpha)
		local popEase = math.clamp(easeOutBack(self._openAlpha), 0, 1.06)
		local hoverScale = 1 + 0.035 * self._hoverAlpha
		local scale = (0.82 + 0.18 * popEase) * hoverScale
		part.Size = Vector3.new(self._baseSize.X * scale, self._baseSize.Y * scale, self._baseSize.Z)

		local tilt = math.rad(self._hoverTiltDegrees) * self._hoverAlpha
		local hoverOffset = CFrame.new(self._hoverX * 0.12 * self._hoverAlpha, -self._hoverY * 0.08 * self._hoverAlpha, -0.08 * self._hoverAlpha)
			* CFrame.Angles(-self._hoverY * tilt, self._hoverX * tilt, -self._hoverX * math.rad(1.5) * self._hoverAlpha)
		local targetOffset = self._offset * hoverOffset
		local animatedOffset = self._closedOffset:Lerp(targetOffset, openEase)
		local target = cam.CFrame * animatedOffset

		local followAlpha = self._openAlpha < 0.96 and 1 or self._lag
		if self._currentCF then
			self._currentCF = self._currentCF:Lerp(target, followAlpha)
		else
			self._currentCF = target
		end
		part.CFrame = self._currentCF
		self:_syncSurfaceVisibility(cam)

		local contentAlpha = math.clamp(self._openAlpha / self._contentFadeDuration, 0, 1)

		-- Smoothly chase zoom/pan targets; clamp pan so the image edge never
		-- pulls inside the card
		local chase = math.clamp(dt * 12, 0, 1)
		self._zoom += (self._zoomTarget - self._zoom) * chase
		local maxPan = math.max((self._zoom - 1) / 2, 0)
		self._panTargetX = math.clamp(self._panTargetX, -maxPan, maxPan)
		self._panTargetY = math.clamp(self._panTargetY, -maxPan, maxPan)
		self._panX = math.clamp(self._panX + (self._panTargetX - self._panX) * chase, -maxPan, maxPan)
		self._panY = math.clamp(self._panY + (self._panTargetY - self._panY) * chase, -maxPan, maxPan)

		for _, image in ipairs(self.Images) do
			image.ImageTransparency = 1 - contentAlpha
			image.Size = UDim2.fromScale(self._zoom, self._zoom)
			image.Position = UDim2.fromScale(0.5 + self._panX, 0.5 + self._panY)
		end
	end)

	return self
end

function CameraPanel:_syncSurfaceVisibility(cam)
	local toCamera = cam.CFrame.Position - self.Part.Position
	if toCamera.Magnitude <= 0.001 then
		self.Gui.Enabled = true
		self.ReverseGui.Enabled = false
		return
	end

	local frontFacesCamera = self.Part.CFrame.LookVector:Dot(toCamera.Unit) > 0
	self.Gui.Enabled = not frontFacesCamera
	self.ReverseGui.Enabled = frontFacesCamera
end

function CameraPanel:_getScreenBounds(cam)
	if not self.Part.Parent then return nil end

	local cf = self.Part.CFrame
	local size = self.Part.Size
	local corners = {
		Vector3.new(-size.X / 2, -size.Y / 2, 0),
		Vector3.new(size.X / 2, -size.Y / 2, 0),
		Vector3.new(-size.X / 2, size.Y / 2, 0),
		Vector3.new(size.X / 2, size.Y / 2, 0),
	}

	local minX = math.huge
	local minY = math.huge
	local maxX = -math.huge
	local maxY = -math.huge
	local hasPoint = false

	for _, corner in ipairs(corners) do
		local point = cam:WorldToViewportPoint((cf * CFrame.new(corner)).Position)
		if point.Z > 0 then
			hasPoint = true
			minX = math.min(minX, point.X)
			minY = math.min(minY, point.Y)
			maxX = math.max(maxX, point.X)
			maxY = math.max(maxY, point.Y)
		end
	end

	if not hasPoint then
		return nil
	end

	return minX - 12, minY - 12, maxX + 12, maxY + 12
end

function CameraPanel:_updateHover(cam, dt: number)
	local targetHover = 0
	local targetX = 0
	local targetY = 0

	-- Hover tilt pauses while zoomed in — it would fight the pan gesture
	if self._openAlpha > 0.8 and self._zoomTarget <= 1.02 then
		local minX, minY, maxX, maxY = self:_getScreenBounds(cam)
		if minX then
			local mouse = UserInputService:GetMouseLocation()
			if mouse.X >= minX and mouse.X <= maxX and mouse.Y >= minY and mouse.Y <= maxY then
				targetHover = 1
				local centerX = (minX + maxX) / 2
				local centerY = (minY + maxY) / 2
				targetX = math.clamp((mouse.X - centerX) / math.max((maxX - minX) / 2, 1), -1, 1)
				targetY = math.clamp((mouse.Y - centerY) / math.max((maxY - minY) / 2, 1), -1, 1)
			end
		end
	end

	local hoverSpeed = math.clamp(dt * 10, 0, 1)
	self._hoverAlpha = self._hoverAlpha + (targetHover - self._hoverAlpha) * hoverSpeed
	self._hoverX = self._hoverX + (targetX - self._hoverX) * hoverSpeed
	self._hoverY = self._hoverY + (targetY - self._hoverY) * hoverSpeed
end

-- Zoom around the card center. delta > 0 zooms in. Clamped 1x–3x.
function CameraPanel:ZoomBy(delta: number)
	self._zoomTarget = math.clamp(self._zoomTarget + delta, 1, 3)
end

-- Pan by a screen-pixel delta (drag). Converted to card-relative units so a
-- drag moves the image 1:1 with the cursor/finger.
function CameraPanel:PanByPixels(dx: number, dy: number)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local minX, minY, maxX, maxY = self:_getScreenBounds(cam)
	if not minX then return end
	local width = math.max(maxX - minX, 1)
	local height = math.max(maxY - minY, 1)
	self._panTargetX += dx / width
	self._panTargetY += dy / height
end

function CameraPanel:ResetView()
	self._zoomTarget = 1
	self._panTargetX = 0
	self._panTargetY = 0
end

function CameraPanel:IsZoomed(): boolean
	return self._zoomTarget > 1.02
end

-- True if a screen point is over the panel (used for scroll-zoom targeting
-- and click-outside-to-close)
function CameraPanel:ContainsScreenPoint(x: number, y: number): boolean
	local cam = workspace.CurrentCamera
	if not cam or not self._visible then return false end
	local minX, minY, maxX, maxY = self:_getScreenBounds(cam)
	if not minX then return false end
	return x >= minX and x <= maxX and y >= minY and y <= maxY
end

function CameraPanel:SetVisible(visible: boolean)
	self._targetVisible = visible
	if not visible then
		self:ResetView()
	end
	if visible then
		local cam = workspace.CurrentCamera
		if cam then
			self.Part.Parent = cam
			if not self._visible then
				self.Part.CFrame = cam.CFrame * self._closedOffset
				self._currentCF = nil
				self._openAlpha = math.max(self._openAlpha, 0.08)
			end
		end
		self.Gui.Enabled = true
		self.ReverseGui.Enabled = true
		self._visible = true
		self._rendering = true
	end
end

function CameraPanel:SetOffset(offset: CFrame)
	self._offset = offset
end

function CameraPanel:Destroy()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self.Part:Destroy()
end

return CameraPanel
