-- MenuPanelController: shows a decal image on a floating 3D camera panel.
-- The panel is real world geometry parented to the camera, so it has true
-- perspective and lags/drifts as you look around (the "3D HUD" feel).
-- Toggle with the M key or by clicking a DS_Menu world interactable.
-- Created by a LocalScript and parented to CurrentCamera, so only this client sees it.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer

local uiFolder = script.Parent
local CameraPanel = require(uiFolder:WaitForChild("CameraPanel"))
local MenuPanelBus = require(uiFolder:WaitForChild("MenuPanelBus"))

-- Must be an IMAGE asset ID (ImageLabels silently reject Decal IDs).
-- 122909089431068 = the Image inside decal "this is am enu" (103378244533780).
local MENU_IMAGE_ID = 122909089431068

local panel = CameraPanel.new({
	-- Height is what matters: width auto-fits the image's real aspect ratio
	-- once the asset loads (see CameraPanel ContentImageSize watcher)
	SizeStuds = Vector2.new(6.2, 6.2),
	Offset = CFrame.new(0, -0.02, -5.15),
	ClosedOffset = CFrame.new(0, 0.08, -2.9)
		* CFrame.Angles(math.rad(-4), math.rad(86), math.rad(-4)),
	Lag = 0.16,
	OpenDuration = 0.28,
	CloseDuration = 0.12,
	ContentFadeDuration = 0.08,
	HoverTiltDegrees = 7,
	ImageId = MENU_IMAGE_ID,
	PixelsPerStud = 280,
})

local blur = Lighting:FindFirstChild("DS_MenuPanelBlur")
if not blur or not blur:IsA("BlurEffect") then
	blur = Instance.new("BlurEffect")
	blur.Name = "DS_MenuPanelBlur"
	blur.Parent = Lighting
end
blur.Size = 0
blur.Enabled = false

local blurTween = nil
local function setBackgroundBlur(open: boolean)
	if blurTween then
		blurTween:Cancel()
	end

	blur.Enabled = true
	blurTween = TweenService:Create(
		blur,
		TweenInfo.new(open and 0.28 or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = open and 18 or 0 }
	)

	local thisTween = blurTween
	thisTween.Completed:Connect(function()
		if thisTween ~= blurTween then
			return
		end
		if not MenuPanelBus.IsOpen() then
			blur.Enabled = false
		end
	end)
	thisTween:Play()
end

task.spawn(function()
	local assetUrl = "rbxassetid://" .. tostring(MENU_IMAGE_ID)
	-- Per-asset status callback tells us WHY a blank image happens:
	-- "Failed" = wrong asset type (Decal not Image), moderation, or permissions.
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync({ assetUrl }, function(_, status)
			print(("[MenuPanel] image %s -> %s"):format(assetUrl, tostring(status)))
		end)
	end)
	if not ok then
		warn("[MenuPanel] preload error:", err)
	end
end)

---------------------------------------------------------------------
-- Camera zoom lock: while the menu is open, scroll/pinch must zoom the
-- MENU, not the player camera. Pin the camera's zoom range to its current
-- distance on open; restore the real range on close.
---------------------------------------------------------------------
local savedMinZoom = player.CameraMinZoomDistance
local savedMaxZoom = player.CameraMaxZoomDistance
local zoomLocked = false

local function setCameraZoomLocked(locked: boolean)
	if locked == zoomLocked then return end
	zoomLocked = locked
	if locked then
		savedMinZoom = player.CameraMinZoomDistance
		savedMaxZoom = player.CameraMaxZoomDistance
		local cam = workspace.CurrentCamera
		local distance = 10
		if cam then
			distance = (cam.CFrame.Position - cam.Focus.Position).Magnitude
		end
		distance = math.clamp(distance, savedMinZoom, savedMaxZoom)
		player.CameraMinZoomDistance = distance
		player.CameraMaxZoomDistance = distance
	else
		player.CameraMinZoomDistance = savedMinZoom
		player.CameraMaxZoomDistance = savedMaxZoom
	end
end

MenuPanelBus.Observe(function(open: boolean)
	panel:SetVisible(open)
	setBackgroundBlur(open)
	setCameraZoomLocked(open)
end)

---------------------------------------------------------------------
-- Input: M toggles. While open — scroll wheel zooms (PC), pinch zooms
-- (mobile), dragging pans, and clicking/tapping OUTSIDE the panel closes it.
---------------------------------------------------------------------
local dragging = false
local lastDragPos: Vector2? = nil

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.M and not processed then
		MenuPanelBus.Toggle()
		return
	elseif input.KeyCode == Enum.KeyCode.Escape and MenuPanelBus.IsOpen() then
		MenuPanelBus.SetOpen(false)
		return
	end

	if not MenuPanelBus.IsOpen() then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if panel:ContainsScreenPoint(pos.X, pos.Y) then
			dragging = true
			lastDragPos = pos
		elseif not processed then
			-- clicked/tapped outside the menu: dismiss it
			MenuPanelBus.SetOpen(false)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not MenuPanelBus.IsOpen() then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local mouse = UserInputService:GetMouseLocation()
		if panel:ContainsScreenPoint(mouse.X, mouse.Y) then
			panel:ZoomBy(input.Position.Z * 0.3)
		end
	elseif dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if lastDragPos then
			panel:PanByPixels(pos.X - lastDragPos.X, pos.Y - lastDragPos.Y)
		end
		lastDragPos = pos
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		lastDragPos = nil
	end
end)

-- Mobile pinch-to-zoom
local lastPinchScale: number? = nil
UserInputService.TouchPinch:Connect(function(_, scale, _, state)
	if not MenuPanelBus.IsOpen() then return end
	if state == Enum.UserInputState.Begin then
		lastPinchScale = scale
	elseif state == Enum.UserInputState.Change and lastPinchScale then
		panel:ZoomBy((scale - lastPinchScale) * 2)
		lastPinchScale = scale
	else
		lastPinchScale = nil
	end
end)

-- Rebuild the panel when the camera resets on respawn so it stays anchored
player.CharacterAdded:Connect(function()
	if MenuPanelBus.IsOpen() then
		task.defer(function()
			panel:SetVisible(true)
			setBackgroundBlur(true)
		end)
	end
end)
