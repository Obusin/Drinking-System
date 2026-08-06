--[[
	MainMenuHud - the front door.

	The lobby is still a real place, but a new player should not have to
	guess what the place is for. This is a menu shell over the lobby/start
	place: Race first, then garage/shop/quests/social destinations.

	If ReplicatedStorage.MenuStage exists, the client clones it locally and
	locks the camera to its Camera marker while this menu is open. The UI
	remains ScreenGui because buttons and panels need to scale cleanly on
	desktop and mobile; stage SurfaceGuis can come later for the event
	boards behind the avatar.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))
local UiSound = require(script.Parent:WaitForChild("UiSound"))

local FONT = Util.font(Config.Hud.FontName, Config.Hud.FontWeight)
local R = Config.Rewards

local MainMenuHud = {}
MainMenuHud.__index = MainMenuHud

export type Options = {
	onPlay: () -> (),
	onLobby: (closeMenu: () -> ()) -> (),
	getHumanoid: () -> Humanoid?,
	-- Lobby world-action: call / put away your kart. Optional so the menu
	-- still builds if the lobby wiring isn't there.
	onCallKart: (() -> ())?,
	-- Opens the real quest panel. The floating quest pill is hidden once the
	-- lobby nav bar exists, so MISSIONS here is the only way in.
	onQuests: (() -> ())?,
	-- Opens the garage over the menu stage.
	onGarage: (() -> ())?,
}

local TABS = {
	{ id = "Play", label = "PLAY", badge = "" },
	{ id = "Karts", label = "KARTS", badge = "" },
	{ id = "Garage", label = "GARAGE", badge = "" },
	{ id = "PowerUps", label = "POWER-UPS", badge = "!" },
	{ id = "Quests", label = "MISSIONS", badge = "" },
	{ id = "Shop", label = "SHOP", badge = "" },
}

local BLACK = Color3.fromRGB(7, 8, 10)
local CHARCOAL = Color3.fromRGB(22, 22, 24)
local ORANGE = Color3.fromRGB(255, 117, 22)
local GOLD = Color3.fromRGB(255, 198, 28)
local YELLOW = Color3.fromRGB(255, 227, 65)
local RED = Color3.fromRGB(225, 32, 24)
local BLUE = Color3.fromRGB(23, 158, 225)
local PURPLE = Color3.fromRGB(121, 74, 220)
local WHITE = Color3.fromRGB(252, 252, 245)
local MUTED = Color3.fromRGB(198, 197, 186)
local SOFT_PANEL = Color3.fromRGB(17, 18, 21)
local EVENT_CARD_IMAGES = {
	"rbxassetid://135160337638228", -- double xp placeholder
	"rbxassetid://109055291769960", -- sale placeholder
	"rbxassetid://135160337638228",
	"rbxassetid://109055291769960",
	"rbxassetid://135160337638228",
}
local RACE_BUTTON_IMAGE = "rbxassetid://75948045702410"
local LOBBY_BUTTON_IMAGE = "rbxassetid://92801979011641"
-- The lobby camera is the AUTHORED angle plus parallax, nothing more: it
-- does not dolly or reframe, so it needs no max-FOV or dolly of its own
-- (see the Lobby branch in Update). Only the garage, which is an
-- inspection camera, has those.
local LOBBY_FOV = 52

local GARAGE_FOV = 40
local GARAGE_MAX_FOV = 58
local GARAGE_BASE_DOLLY = 13
local GARAGE_NARROW_DOLLY = 12

local MENU_IDLE_ANIM = "rbxassetid://77663910821313"
local MENU_REFERENCE_ASPECT = 16 / 9
local MENU_PARALLAX_RATE = 5
local MENU_PARALLAX_SIDE = 0.45
local MENU_PARALLAX_UP = 0.18
local MENU_PARALLAX_LOOK_SIDE = 1.4
local MENU_PARALLAX_LOOK_UP = 0.55
local CAROUSEL_ADVANCE_TIME = 5
local LOCAL_STAGE_NAME = "_BloxKartMenuStage"
local RENDER_STEP_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local localMenuStage: Instance? = nil
local menuStageAvatarUserId: number? = nil

local function text(parent: Instance, name: string, size: number, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextSize = size
	label.TextColor3 = colour
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = ""
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

-- The faint edge that makes a hotbar slot read as a raised key rather than a
-- flat swatch.
local function addHotStroke(inst: GuiObject)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 255, 255)
	s.Thickness = 1
	s.Transparency = 0.86
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
end

local function panel(parent: Instance, name: string, colour: Color3, radius: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = colour
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, radius)
	return frame
end

local function button(parent: Instance, name: string, label: string, colour: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = colour
	b.BorderSizePixel = 0
	b.FontFace = FONT
	b.TextSize = 20
	b.TextColor3 = WHITE
	b.Text = label
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 12)
	UiSound.bind(b)   -- hover + click cues for every factory button
	return b
end

local function badge(parent: Instance, label: string, size: number): TextLabel
	local frame = Instance.new("TextLabel")
	frame.Name = "Badge"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.BackgroundColor3 = RED
	frame.BorderSizePixel = 0
	frame.FontFace = FONT
	frame.TextColor3 = WHITE
	frame.TextSize = size
	frame.Text = label
	frame.TextXAlignment = Enum.TextXAlignment.Center
	frame.TextYAlignment = Enum.TextYAlignment.Center
	frame.Position = UDim2.new(1, 8, 0, -8)
	frame.Size = UDim2.fromOffset(24, 24)
	frame.Parent = parent
	corner(frame, 12)
	return frame
end

local function image(parent: Instance, name: string, id: string, px: number, tag: string): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.Size = UDim2.fromOffset(px, px)
	i.ScaleType = Enum.ScaleType.Fit
	i.Image = id
	i.Visible = id ~= ""
	i.Parent = parent
	if id ~= "" then
		Util.verifyImage(i, id, tag)
	end
	return i
end

local function findStageTemplate(): Instance?
	return ReplicatedStorage:FindFirstChild("MenuStage") or BloxKart:FindFirstChild("MenuStage")
end

local function getMenuStage(): Instance?
	if localMenuStage and localMenuStage.Parent then
		return localMenuStage
	end

	local existingLocal = Workspace:FindFirstChild(LOCAL_STAGE_NAME)
	if existingLocal then
		localMenuStage = existingLocal
		return existingLocal
	end

	local template = findStageTemplate()
	if template then
		local clone = template:Clone()
		clone.Name = LOCAL_STAGE_NAME
		clone.Parent = Workspace
		localMenuStage = clone
		return clone
	end

	return Workspace:FindFirstChild("MenuStage")
end

local function applyPlayerAppearanceToStage(stage: Instance, player: Player)
	if menuStageAvatarUserId == player.UserId then
		return
	end
	menuStageAvatarUserId = player.UserId

	task.spawn(function()
		local rig = stage:FindFirstChild("Rig", true)
		if not rig or not rig:IsA("Model") then
			warn("[MainMenuHud] MenuStage has no Rig MODEL for avatar preview — add a Model named 'Rig'.")
			return
		end

		-- Freeze the placeholder immediately (it may be unanchored on the client
		-- and would otherwise fall during the yielding build below). Capture:
		--   • its HRP CFrame  → horizontal position + which way it faces, and
		--   • its bounding-box BOTTOM → the ground its feet stand on.
		-- We align the generated avatar FEET-to-feet, not HRP-to-HRP: the
		-- player's real body scale differs from the placeholder dummy, so
		-- matching HRP heights leaves a taller avatar sunk into the floor.
		local placeholderRoot = rig:FindFirstChild("HumanoidRootPart", true)
		local rootCF = (placeholderRoot and placeholderRoot.CFrame) or rig:GetPivot()
		local pbCF, pbSize = rig:GetBoundingBox()
		local groundY = pbCF.Position.Y - pbSize.Y / 2
		local rigParent = rig.Parent
		for _, d in ipairs(rig:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end

		local ok, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if not ok or not description then
			warn("[MainMenuHud] GetHumanoidDescriptionFromUserId failed for " .. player.Name .. ": " .. tostring(description)
				.. " (is 'Allow Studio Access to API Services' on?)")
			return
		end

		-- Humanoid:ApplyDescription is SERVER-ONLY, so it can't dress a client-
		-- local menu rig. Instead we BUILD the avatar model from the description
		-- on the client (R15) and swap it in where the placeholder rig stood.
		local built, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if not built or typeof(model) ~= "Instance" then
			warn("[MainMenuHud] CreateHumanoidModelFromDescription failed: " .. tostring(model))
			return
		end

		model.Name = "Rig"
		-- Anchor ONLY the HumanoidRootPart: that pins the avatar in place (can't
		-- fall), while leaving the limbs jointed & unanchored so the idle
		-- animation can still move them. Anchoring every part would freeze the
		-- pose and the animation would have nothing to drive.
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = (d.Name == "HumanoidRootPart")
				d.CanCollide = false
			end
		end
		model.Parent = rigParent
		model:PivotTo(rootCF) -- correct horizontal position + facing (HRP-aligned)
		-- Then shift vertically so the avatar's OWN feet rest on that ground,
		-- regardless of its body scale — this is what stops the sinking.
		local gbCF, gbSize = model:GetBoundingBox()
		local feetY = gbCF.Position.Y - gbSize.Y / 2
		model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - feetY, 0))
		rig:Destroy()

		-- Idle emote so the preview breathes instead of T-posing.
		local hum = model:FindFirstChildWhichIsA("Humanoid")
		if hum then
			hum.EvaluateStateMachine = false -- no walk/fall states on a display rig
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			local animator = hum:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = hum
			end
			local anim = Instance.new("Animation")
			anim.AnimationId = MENU_IDLE_ANIM
			local okAnim, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if okAnim and track then
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Idle
				track:Play(0.2)
			else
				warn("[MainMenuHud] Idle animation failed to load ("
					.. MENU_IDLE_ANIM .. "): " .. tostring(track)
					.. " — the animation may need to be owned by the experience.")
			end
		end
		print(("[MainMenuHud] Built %s's R15 avatar onto MenuStage.Rig."):format(player.Name))
	end)
end

local function findPart(stage: Instance, names: {string}): Instance?
	for _, name in ipairs(names) do
		local found = stage:FindFirstChild(name) or stage:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end

local function stageParts(mode: "Lobby" | "Garage")
	local stage = getMenuStage()
	if not stage then
		return nil, nil, nil
	end

	local cameraNames
	local lookNames
	local fitNames

	if mode == "Garage" then
		cameraNames = { "GarageCamera", "Camera", "CameraPoint" }
		lookNames = { "GarageLookAt", "LookAt" }
		fitNames = { "GarageFitBounds", "FitBounds" }
	else
		cameraNames = { "LobbyCamera", "MenuCamera", "Camera", "CameraPoint" }
		lookNames = { "LobbyLookAt", "MenuLookAt", "LookAt" }
		fitNames = { "LobbyFitBounds", "MenuFitBounds", "FitBounds" }
	end

	local cameraPoint = findPart(stage, cameraNames)
	local lookAt = findPart(stage, lookNames)
	local fitBounds = findPart(stage, fitNames)

	-- GARAGE ONLY. The garage is an inspection camera and needs a centre to
	-- orbit and zoom around, so with no marker the kart is the honest
	-- subject.
	--
	-- The lobby menu deliberately gets NO fallback: its angle is authored
	-- and already framed, and aiming it at the kart would re-centre the
	-- composition on every stage edit. With no LookAt it keeps the marker's
	-- own orientation — see responsiveCamera.
	if not lookAt and mode == "Garage" then
		local kart = stage:FindFirstChild("Kart", true)
		if kart then
			lookAt = if kart:IsA("Model")
				then kart.PrimaryPart or kart:FindFirstChildWhichIsA("BasePart", true)
				else kart
		end
	end

	if cameraPoint and (cameraPoint:IsA("BasePart") or cameraPoint:IsA("Camera")) then
		return cameraPoint,
			if lookAt and lookAt:IsA("BasePart") then lookAt else nil,
			if fitBounds and fitBounds:IsA("BasePart") then fitBounds else nil
	end

	return nil, nil, nil
end

local function authoredCamera(cameraPoint: Instance): CFrame
	if cameraPoint:IsA("BasePart") then
		return (cameraPoint :: BasePart).CFrame
	end
	return (cameraPoint :: Camera).CFrame
end

local function responsiveCamera(
	cameraPoint: Instance,
	lookAt: BasePart?,
	fitBounds: BasePart?,
	viewport: Vector2,
	zoom: number,
	orbit: Vector2,
	baseFov: number,
	maxFov: number,
	baseDolly: number,
	narrowDolly: number
): (CFrame, number)
	local pointCFrame = if cameraPoint:IsA("BasePart")
		then (cameraPoint :: BasePart).CFrame
		else (cameraPoint :: Camera).CFrame

	local targetPosition = if lookAt then lookAt.Position elseif fitBounds then fitBounds.Position else nil
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else MENU_REFERENCE_ASPECT
	local narrow = math.max((MENU_REFERENCE_ASPECT / math.max(aspect, 0.01)) - 1, 0)
	local fov = math.clamp(baseFov + narrow * 18, baseFov, maxFov)

	if fitBounds then
		local fitRadius = math.max(fitBounds.Size.X, fitBounds.Size.Y, fitBounds.Size.Z) * 0.5
		local distance = if targetPosition then (pointCFrame.Position - targetPosition).Magnitude else 0
		if distance > 0 and fitRadius > 0 then
			local requiredFov = math.deg(2 * math.atan(fitRadius / distance))
			fov = math.clamp(math.max(fov, requiredFov + 8), baseFov, maxFov)
		end
	end

	if not targetPosition then
		targetPosition = pointCFrame.Position + pointCFrame.LookVector * 20
	end

	local view = pointCFrame.Position - targetPosition
	if view.Magnitude < 0.001 then
		return pointCFrame, fov
	end

	local dolly = math.max(baseDolly + narrow * narrowDolly + zoom, 0)
	local radius = view.Magnitude + dolly
	local dir = view.Unit

	if orbit.X ~= 0 or orbit.Y ~= 0 then
		dir = CFrame.Angles(0, orbit.X, 0):VectorToWorldSpace(dir)
		local right = Vector3.new(dir.Z, 0, -dir.X)
		if right.Magnitude > 0.001 then
			dir = CFrame.fromAxisAngle(right.Unit, orbit.Y):VectorToWorldSpace(dir)
		end
	end

	return CFrame.lookAt(targetPosition + dir * radius, targetPosition), fov
end

local function mouseParallaxTarget(viewport: Vector2): Vector2
	if not UserInputService.MouseEnabled or viewport.X <= 0 or viewport.Y <= 0 then
		return Vector2.zero
	end

	local mouse = UserInputService:GetMouseLocation()
	local x = math.clamp((mouse.X / viewport.X - 0.5) * 2, -1, 1)
	local y = math.clamp((mouse.Y / viewport.Y - 0.5) * 2, -1, 1)
	return Vector2.new(x, y)
end

local function applyParallax(cframe: CFrame, parallax: Vector2): CFrame
	if parallax.Magnitude < 0.001 then
		return cframe
	end

	local side = cframe.RightVector
	local up = cframe.UpVector
	local position = cframe.Position
		+ side * (parallax.X * MENU_PARALLAX_SIDE)
	- up * (parallax.Y * MENU_PARALLAX_UP)
	local aim = cframe.Position
		+ cframe.LookVector * 100
		+ side * (parallax.X * MENU_PARALLAX_LOOK_SIDE)
	- up * (parallax.Y * MENU_PARALLAX_LOOK_UP)
	return CFrame.lookAt(position, aim, up)
end

function MainMenuHud.new(opts: Options)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stage = getMenuStage()
	if stage then
		applyPlayerAppearanceToStage(stage, player)
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartMainMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = playerGui

	-- FIXED DESIGN CANVAS. The whole menu is laid out in a constant 1600x900
	-- (16:9) space and centred; a UIScale then shrinks the WHOLE thing to fit
	-- the viewport (see Update). This is what keeps the layout identical at any
	-- window size — every child's fromScale position maps to the same 16:9 box
	-- regardless of the real aspect ratio, so nothing reflows or collides when
	-- the window is narrow. Off-16:9 windows letterbox over the 3D stage, which
	-- is fine because the menu background is transparent.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = BLACK
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(1600, 900)
	root.Parent = gui

	local rootScale = Instance.new("UIScale")
	rootScale.Name = "RootScale"
	rootScale.Scale = 1
	rootScale.Parent = root

	local vignette = panel(root, "Vignette", Color3.fromRGB(0, 0, 0), 0)
	vignette.BackgroundTransparency = 1
	vignette.Size = UDim2.fromScale(1, 1)

	local floorGlow = panel(root, "FloorGlow", ORANGE, 36)
	floorGlow.AnchorPoint = Vector2.new(0.5, 1)
	floorGlow.BackgroundTransparency = 1
	floorGlow.Position = UDim2.fromScale(0.38, 0.96)
	floorGlow.Size = UDim2.fromScale(0.58, 0.2)

	local tabs = panel(root, "Tabs", Color3.fromRGB(8, 9, 11), 12)
	tabs.BackgroundTransparency = 0.08
	tabs.Position = UDim2.fromScale(0.265, 0.036)
	tabs.Size = UDim2.fromScale(0.505, 0.064)

	-- Single sliding selection pill. Lives behind the tab labels and is moved
	-- to the active tab; the buttons themselves are transparent so only this
	-- shows the selection. Positioned by the tab's rect in _MoveHighlight.
	local tabHighlight = Instance.new("Frame")
	tabHighlight.Name = "Highlight"
	tabHighlight.AnchorPoint = Vector2.new(0.5, 0.5)
	tabHighlight.BackgroundColor3 = GOLD
	tabHighlight.BorderSizePixel = 0
	tabHighlight.ZIndex = 1
	tabHighlight.Size = UDim2.fromOffset(0, 0)
	tabHighlight.Parent = tabs
	corner(tabHighlight, 10)
	local highlightScale = Instance.new("UIScale")
	highlightScale.Name = "Pulse"
	highlightScale.Scale = 1
	highlightScale.Parent = tabHighlight

	-- Inner row carries the list layout + buttons, above the highlight.
	local tabsInner = Instance.new("Frame")
	tabsInner.Name = "Inner"
	tabsInner.BackgroundTransparency = 1
	tabsInner.Size = UDim2.fromScale(1, 1)
	tabsInner.ZIndex = 2
	tabsInner.Parent = tabs

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 2)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabsInner

	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingTop = UDim.new(0, 6)
	tabPad.PaddingBottom = UDim.new(0, 6)
	tabPad.PaddingLeft = UDim.new(0, 8)
	tabPad.PaddingRight = UDim.new(0, 8)
	tabPad.Parent = tabsInner

	-- LOBBY WORLD-ACTION: call / put away your kart.
	--
	-- Lives in the top bar (where the logo used to sit) rather than as a
	-- bottom-centre key prompt: the prompt was floating debug-looking text
	-- disconnected from the rest of the UI. The G key still works — see
	-- KeyPrompt:SetShown — this is a second, visible way in, not a
	-- replacement. Stays visible when the menu is minimised in the lobby,
	-- which is exactly when you need it.
	local kartAction = button(root, "KartAction", "CALL KART", GOLD)
	kartAction.Position = UDim2.fromScale(0.035, 0.036)
	kartAction.Size = UDim2.fromScale(0.155, 0.064)
	kartAction.TextColor3 = BLACK
	kartAction.TextSize = 17
	kartAction.Visible = false -- shown once lobby wiring provides onCallKart

	local kartKeyHint = text(kartAction, "KeyHint", 12, BLACK)
	kartKeyHint.AnchorPoint = Vector2.new(1, 1)
	kartKeyHint.Position = UDim2.fromScale(0.96, 0.94)
	kartKeyHint.Size = UDim2.fromScale(0.3, 0.34)
	kartKeyHint.Text = "[G]"
	kartKeyHint.TextTransparency = 0.35
	kartKeyHint.TextXAlignment = Enum.TextXAlignment.Right

	-- LOBBY HOTBAR. While the menu is minimised the full text nav would be a
	-- menu bar sitting over a place you are walking around in, which reads as
	-- the menu never having closed. A row of square slots reads as game
	-- furniture instead — the same actions, presented as a hotbar.
	--
	-- Shown ONLY when minimised; the tab bar takes over when the menu opens.
	local hotbar = Instance.new("Frame")
	hotbar.Name = "LobbyHotbar"
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.fromScale(0.5, 0.965)
	hotbar.Size = UDim2.fromScale(0.5, 0.088)
	hotbar.BackgroundTransparency = 1
	hotbar.Visible = false
	hotbar.Parent = root

	local hotLayout = Instance.new("UIListLayout")
	hotLayout.FillDirection = Enum.FillDirection.Horizontal
	hotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hotLayout.Padding = UDim.new(0, 8)
	hotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hotLayout.Parent = hotbar

	local iconBar = panel(root, "IconBar", Color3.fromRGB(8, 9, 11), 12)
	iconBar.BackgroundTransparency = 0.08
	iconBar.Position = UDim2.fromScale(0.78, 0.036)
	iconBar.Size = UDim2.fromScale(0.16, 0.064)

	local iconLayout = Instance.new("UIListLayout")
	iconLayout.FillDirection = Enum.FillDirection.Horizontal
	iconLayout.Padding = UDim.new(0, 7)
	iconLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	iconLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	iconLayout.Parent = iconBar

	local stageShade = panel(root, "StageShade", Color3.fromRGB(14, 14, 14), 18)
	stageShade.BackgroundTransparency = 1
	stageShade.Position = UDim2.fromScale(0.025, 0.16)
	stageShade.Size = UDim2.fromScale(0.475, 0.58)

	local previewHint = text(stageShade, "PreviewHint", 16, MUTED)
	previewHint.AnchorPoint = Vector2.new(0.5, 1)
	previewHint.Position = UDim2.fromScale(0.5, 0.96)
	previewHint.Size = UDim2.fromScale(0.82, 0.08)
	previewHint.TextXAlignment = Enum.TextXAlignment.Center
	previewHint.Text = "Add ReplicatedStorage.MenuStage with a Camera marker to frame your racer and kart here."
	previewHint.Visible = getMenuStage() == nil

	local profile = panel(root, "Profile", SOFT_PANEL, 12)
	profile.BackgroundTransparency = 0.08
	profile.Position = UDim2.fromScale(0.035, 0.64)
	profile.Size = UDim2.fromScale(0.225, 0.112)

	local avatar = panel(profile, "Avatar", Color3.fromRGB(26, 28, 34), 8)
	avatar.Position = UDim2.fromScale(0.05, 0.14)
	avatar.Size = UDim2.fromScale(0.18, 0.66)
	avatar.ClipsDescendants = true -- round the headshot with the corner

	-- True square regardless of viewport aspect, so the square headshot fills it.
	local avatarRatio = Instance.new("UIAspectRatioConstraint")
	avatarRatio.AspectRatio = 1
	avatarRatio.DominantAxis = Enum.DominantAxis.Height
	avatarRatio.Parent = avatar

	-- rbxthumb:// loads the player's real Roblox headshot DIRECTLY — Roblox
	-- resolves + caches it. GetUserThumbnailAsync was returning nothing here
	-- (silent), which is why the box stayed blank; this is the reliable path.
	local avatarImage = Instance.new("ImageLabel")
	avatarImage.Name = "AvatarImage"
	avatarImage.BackgroundTransparency = 1
	avatarImage.Size = UDim2.fromScale(1, 1)
	avatarImage.ScaleType = Enum.ScaleType.Crop
	avatarImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
	avatarImage.Parent = avatar

	local name = text(profile, "PlayerName", 18, WHITE)
	name.Position = UDim2.fromScale(0.3, 0.12)
	name.Size = UDim2.fromScale(0.64, 0.26)
	name.Text = player.DisplayName
	name.TextStrokeTransparency = 0.3

	local rank = text(profile, "Rank", 12, BLUE)
	rank.Position = UDim2.fromScale(0.3, 0.38)
	rank.Size = UDim2.fromScale(0.6, 0.18)
	rank.Text = "SPEEDSTER"

	local level = panel(profile, "Level", GOLD, 8)
	level.Position = UDim2.fromScale(0.075, 0.78)
	level.Size = UDim2.fromScale(0.16, 0.18)

	local levelText = text(level, "LevelText", 13, BLACK)
	levelText.Size = UDim2.fromScale(1, 1)
	levelText.Text = "23"
	levelText.TextXAlignment = Enum.TextXAlignment.Center

	local xpBar = panel(profile, "XpBar", Color3.fromRGB(4, 5, 6), 8)
	xpBar.Position = UDim2.fromScale(0.3, 0.67)
	xpBar.Size = UDim2.fromScale(0.6, 0.15)

	local xpFill = panel(xpBar, "XpFill", BLUE, 8)
	xpFill.Size = UDim2.fromScale(0.71, 1)

	local xp = text(profile, "Xp", 12, WHITE)
	xp.Position = UDim2.fromScale(0.32, 0.65)
	xp.Size = UDim2.fromScale(0.56, 0.17)
	xp.Text = "4,250 / 6,000 XP"
	xp.TextXAlignment = Enum.TextXAlignment.Center

	local currency = panel(root, "Currency", SOFT_PANEL, 12)
	currency.BackgroundTransparency = 0.08
	currency.Position = UDim2.fromScale(0.035, 0.752)
	currency.Size = UDim2.fromScale(0.225, 0.098)

	-- BOLTS row (primary currency — big icon, prominent value)
	local boltIcon = image(currency, "BoltIcon", R.BoltIcon, 46, "MainMenuHud")
	boltIcon.AnchorPoint = Vector2.new(0, 0.5)
	boltIcon.Position = UDim2.fromScale(0.06, 0.3)

	local bolts = text(currency, "Bolts", 14, MUTED)
	bolts.AnchorPoint = Vector2.new(0, 0.5)
	bolts.Position = UDim2.fromScale(0.26, 0.3)
	bolts.Size = UDim2.fromScale(0.4, 0.32)
	bolts.Text = "BOLTS"
	bolts.TextXAlignment = Enum.TextXAlignment.Left

	local boltValue = text(currency, "BoltValue", 20, WHITE)
	boltValue.AnchorPoint = Vector2.new(1, 0.5)
	boltValue.Position = UDim2.fromScale(0.93, 0.3)
	boltValue.Size = UDim2.fromScale(0.5, 0.38)
	boltValue.Text = "12,450"
	boltValue.TextXAlignment = Enum.TextXAlignment.Right

	-- Hairline between the two rows so they read as a tidy list, not a stack.
	local curDivider = Instance.new("Frame")
	curDivider.Name = "Divider"
	curDivider.AnchorPoint = Vector2.new(0.5, 0.5)
	curDivider.Position = UDim2.fromScale(0.5, 0.52)
	curDivider.Size = UDim2.new(0.88, 0, 0, 1)
	curDivider.BorderSizePixel = 0
	curDivider.BackgroundColor3 = WHITE
	curDivider.BackgroundTransparency = 0.9
	curDivider.Parent = currency

	-- NITRO CRYSTALS row (secondary) — icon aligned with the Bolt icon above.
	local nitroIcon = image(currency, "NitroIcon", R.NitroIcon, 40, "MainMenuHud")
	nitroIcon.AnchorPoint = Vector2.new(0, 0.5)
	nitroIcon.Position = UDim2.fromScale(0.06, 0.74)

	local crystals = text(currency, "Crystals", 13, MUTED)
	crystals.AnchorPoint = Vector2.new(0, 0.5)
	crystals.Position = UDim2.fromScale(0.26, 0.74)
	crystals.Size = UDim2.fromScale(0.44, 0.3)
	crystals.Text = "NITRO CRYSTALS"
	crystals.TextXAlignment = Enum.TextXAlignment.Left

	local crystalValue = text(currency, "CrystalValue", 16, WHITE)
	crystalValue.AnchorPoint = Vector2.new(1, 0.5)
	crystalValue.Position = UDim2.fromScale(0.93, 0.74)
	crystalValue.Size = UDim2.fromScale(0.4, 0.32)
	crystalValue.Text = "320"
	crystalValue.TextXAlignment = Enum.TextXAlignment.Right

	local lobbyButton = button(root, "EnterLobby", "ENTER LOBBY", CHARCOAL)
	lobbyButton.BackgroundTransparency = 1
	lobbyButton.AnchorPoint = Vector2.new(1, 1)
	lobbyButton.Position = UDim2.fromScale(0.74, 0.94)
	lobbyButton.Size = UDim2.fromScale(0.34, 0.16)
	lobbyButton.Text = ""

	local lobbyButtonArt = image(lobbyButton, "Art", LOBBY_BUTTON_IMAGE, 128, "MainMenuHud")
	lobbyButtonArt.AnchorPoint = Vector2.new(0.5, 0.5)
	lobbyButtonArt.Position = UDim2.fromScale(0.5, 0.5)
	lobbyButtonArt.Size = UDim2.fromScale(1.78, 1.98)
	lobbyButtonArt.ScaleType = Enum.ScaleType.Fit

	local lobbyButtonScale = Instance.new("UIScale")
	lobbyButtonScale.Name = "HoverScale"
	lobbyButtonScale.Scale = 1
	lobbyButtonScale.Parent = lobbyButtonArt

	local eventPanel = panel(root, "EventPanel", SOFT_PANEL, 14)
	eventPanel.BackgroundTransparency = 0.05
	eventPanel.Position = UDim2.fromScale(0.49, 0.155)
	eventPanel.Size = UDim2.fromScale(0.42, 0.36)

	local eventArt = panel(eventPanel, "EventArt", Color3.fromRGB(16, 132, 215), 10)
	eventArt.Position = UDim2.fromScale(0.035, 0.06)
	eventArt.Size = UDim2.fromScale(0.93, 0.72)
	eventArt.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	eventArt.ClipsDescendants = true

	local carouselCanvas = Instance.new("CanvasGroup")
	carouselCanvas.Name = "CarouselCanvas"
	carouselCanvas.BackgroundTransparency = 1
	carouselCanvas.BorderSizePixel = 0
	carouselCanvas.ClipsDescendants = true
	carouselCanvas.GroupTransparency = 0
	carouselCanvas.Position = UDim2.fromScale(0, 0)
	carouselCanvas.Size = UDim2.fromScale(1, 1)
	carouselCanvas.ZIndex = 5
	carouselCanvas.Parent = eventArt

	local carouselSlides = {}
	local carouselScales = {}

	for i = 1, #EVENT_CARD_IMAGES do
		local slide = image(carouselCanvas, "Slide" .. i, EVENT_CARD_IMAGES[i], 128, "MainMenuHud")
		slide.AnchorPoint = Vector2.new(0.5, 0.5)
		slide.BackgroundTransparency = 1
		slide.Position = UDim2.fromScale(0.5, 0.5)
		slide.ScaleType = Enum.ScaleType.Crop
		slide.Size = UDim2.fromScale(1, 1)
		slide.ImageTransparency = if i == 1 then 0 else 1
		slide.ZIndex = if i == 1 then 5 else 1
		local slideScale = Instance.new("UIScale")
		slideScale.Name = "HoverScale"
		slideScale.Scale = 1
		slideScale.Parent = slide
		table.insert(carouselSlides, slide)
		table.insert(carouselScales, slideScale)
	end

	local carouselLabel = text(eventArt, "CarouselLabel", 15, WHITE)
	carouselLabel.AnchorPoint = Vector2.new(0, 1)
	carouselLabel.Position = UDim2.fromScale(0.045, 0.95)
	carouselLabel.Size = UDim2.fromScale(0.44, 0.12)
	carouselLabel.Text = "FEATURED EVENT"
	carouselLabel.TextStrokeTransparency = 0.5
	carouselLabel.ZIndex = 20

	local prevSlide = button(eventArt, "CarouselPrev", "<", Color3.fromRGB(0, 0, 0))
	prevSlide.AnchorPoint = Vector2.new(0, 0.5)
	prevSlide.BackgroundTransparency = 0.48
	prevSlide.Position = UDim2.fromScale(0.025, 0.5)
	prevSlide.Size = UDim2.fromScale(0.07, 0.22)
	prevSlide.TextSize = 26
	prevSlide.ZIndex = 25

	local nextSlide = button(eventArt, "CarouselNext", ">", Color3.fromRGB(0, 0, 0))
	nextSlide.AnchorPoint = Vector2.new(1, 0.5)
	nextSlide.BackgroundTransparency = 0.48
	nextSlide.Position = UDim2.fromScale(0.975, 0.5)
	nextSlide.Size = UDim2.fromScale(0.07, 0.22)
	nextSlide.TextSize = 26
	nextSlide.ZIndex = 25

	local eventFooter = panel(eventPanel, "EventFooter", Color3.fromRGB(8, 9, 11), 8)
	eventFooter.Position = UDim2.fromScale(0.035, 0.79)
	eventFooter.Size = UDim2.fromScale(0.93, 0.13)

	local eventFooterText = text(eventFooter, "EventFooterText", 18, WHITE)
	eventFooterText.Position = UDim2.fromScale(0.04, 0)
	eventFooterText.Size = UDim2.fromScale(0.6, 1)
	eventFooterText.Text = "EVENT CAROUSEL PLACEHOLDER"

	local countdown = text(eventFooter, "Countdown", 15, WHITE)
	countdown.Position = UDim2.fromScale(0.66, 0)
	countdown.Size = UDim2.fromScale(0.31, 1)
	countdown.Text = "ENDS IN: 2D 14H"
	countdown.TextXAlignment = Enum.TextXAlignment.Right

	local dots = panel(root, "CarouselDots", Color3.fromRGB(0, 0, 0), 9)
	dots.BackgroundTransparency = 1
	dots.Position = UDim2.fromScale(0.61, 0.53)
	dots.Size = UDim2.fromScale(0.13, 0.025)

	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.Padding = UDim.new(0, 8)
	dotLayout.Parent = dots

	local carouselDots = {}
	for i = 1, 5 do
		local dot = panel(dots, "Dot" .. i, if i == 1 then GOLD else Color3.fromRGB(94, 94, 94), 5)
		dot.Size = UDim2.fromOffset(9, 9)
		table.insert(carouselDots, dot)
	end

	local featureRow = panel(root, "FeatureRow", Color3.fromRGB(0, 0, 0), 0)
	featureRow.BackgroundTransparency = 1
	featureRow.Position = UDim2.fromScale(0.49, 0.575)
	featureRow.Size = UDim2.fromScale(0.32, 0.155)

	local featureLayout = Instance.new("UIListLayout")
	featureLayout.FillDirection = Enum.FillDirection.Horizontal
	featureLayout.Padding = UDim.new(0, 10)
	featureLayout.SortOrder = Enum.SortOrder.LayoutOrder
	featureLayout.Parent = featureRow

	local function featureCard(i: number, title: string, foot: string, colour: Color3, artId: string?)
		local card = panel(featureRow, "Feature" .. i, colour, 12)
		card.Size = UDim2.new(1 / 2, -6, 1, 0)
		card.LayoutOrder = i

		-- A supplied artId is a finished card graphic: it replaces the whole
		-- placeholder styling and fills the slot (no title/footer/tile/bg).
		if artId then
			card.BackgroundTransparency = 1
			local art = image(card, "Art", artId, 128, "MainMenuHud")
			art.AnchorPoint = Vector2.new(0.5, 0.5)
			art.Position = UDim2.fromScale(0.5, 0.5)
			art.Size = UDim2.fromScale(1, 1)
			art.ScaleType = Enum.ScaleType.Fit
			art.ImageTransparency = 0
			return
		end

		local titleLabel = text(card, "Title", 19, WHITE)
		titleLabel.Position = UDim2.fromScale(0.08, 0.08)
		titleLabel.Size = UDim2.fromScale(0.84, 0.38)
		titleLabel.Text = title
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		titleLabel.TextWrapped = true
		titleLabel.TextStrokeTransparency = 0.45

		local art = image(card, "Art", artId or "", 72, "MainMenuHud")
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.58)
		art.Size = UDim2.fromScale(0.6, 0.44)
		art.ScaleType = Enum.ScaleType.Fit
		art.Visible = true
		art.ImageTransparency = if artId then 0 else 1

		-- Placeholder tile only when no real art is supplied.
		local artPlaceholder = panel(card, "ArtPlaceholder", Color3.fromRGB(255, 255, 255), 8)
		artPlaceholder.AnchorPoint = Vector2.new(0.5, 0.5)
		artPlaceholder.BackgroundTransparency = 0.88
		artPlaceholder.Position = UDim2.fromScale(0.5, 0.58)
		artPlaceholder.Size = UDim2.fromScale(0.44, 0.28)
		artPlaceholder.Visible = artId == nil

		local footer = text(card, "Footer", 14, if colour == GOLD then BLACK else WHITE)
		footer.Position = UDim2.fromScale(0.1, 0.78)
		footer.Size = UDim2.fromScale(0.8, 0.15)
		footer.Text = foot
		footer.TextXAlignment = Enum.TextXAlignment.Center
	end

	featureCard(1, "MISSIONS", "3/5", BLUE)
	featureCard(2, "SEASON\nPASS", "12", PURPLE, "rbxassetid://81945884451967")

	local raceButton = button(root, "Race", "RACE!", GOLD)
	raceButton.BackgroundTransparency = 1
	raceButton.AnchorPoint = Vector2.new(1, 1)
	raceButton.Position = UDim2.fromScale(0.945, 0.94)
	raceButton.Size = UDim2.fromScale(0.34, 0.16)
	raceButton.Text = ""

	local raceButtonArt = image(raceButton, "Art", RACE_BUTTON_IMAGE, 128, "MainMenuHud")
	raceButtonArt.AnchorPoint = Vector2.new(0.5, 0.5)
	raceButtonArt.Position = UDim2.fromScale(0.5, 0.5)
	raceButtonArt.Size = UDim2.fromScale(1.62, 1.82)   -- trimmed to match Enter Lobby's visual size (its PNG has less padding)
	raceButtonArt.ScaleType = Enum.ScaleType.Fit

	local raceButtonScale = Instance.new("UIScale")
	raceButtonScale.Name = "HoverScale"
	raceButtonScale.Scale = 1
	raceButtonScale.Parent = raceButtonArt

	local status = text(root, "Status", 16, YELLOW)
	status.Position = UDim2.fromScale(0.47, 0.765)
	status.Size = UDim2.fromScale(0.46, 0.035)
	status.Text = ""
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextWrapped = true

	local self = setmetatable({
		gui = gui,
		root = root,
		rootScale = rootScale,
		floorGlow = floorGlow,
		raceButton = raceButton,
		raceButtonScale = raceButtonScale,
		lobbyButtonScale = lobbyButtonScale,
		carouselSlides = carouselSlides,
		carouselScales = carouselScales,
		carouselDots = carouselDots,
		carouselIndex = 1,
		carouselHover = false,
		carouselNextAt = os.clock() + CAROUSEL_ADVANCE_TIME,
		status = status,
		kartAction = kartAction,
		kartActionEnabled = opts.onCallKart ~= nil,
		iconBar = iconBar,
		hotbar = hotbar,
		tabs = {},
		tabsHolder = tabs,
		tabHighlight = tabHighlight,
		highlightScale = highlightScale,
		hlAnimating = false,
		active = "Play",
		open = true,
		opts = opts,
		cameraSaved = nil,
		renderStepName = "BloxKartMainMenuCamera_" .. tostring(player.UserId),
		parallax = Vector2.zero,
		shine = 0,
		-- Garage camera dolly, in studs. `zoom` is where the camera is,
		-- `zoomTarget` where it is heading — see the ease in Update.
		zoom = 0,
		zoomTarget = 0,
		-- Garage orbit, radians. X yaw, Y pitch.
		orbit = Vector2.zero,
		orbitTarget = Vector2.zero,
		inspecting = false, -- garage owns the camera
	}, MainMenuHud)

	for i, spec in TABS do
		local tab = button(tabsInner, spec.id, spec.label, Color3.fromRGB(13, 14, 17))
		tab.BackgroundTransparency = 1   -- selection is drawn by the sliding highlight
		tab.AutoButtonColor = false
		tab.Size = UDim2.new(1 / #TABS, -2, 1, 0)
		tab.LayoutOrder = i
		tab.TextSize = if spec.id == "PowerUps" then 16 else 19
		tab.TextColor3 = if i == 1 then BLACK else WHITE
		tab.Activated:Connect(function()
			self:_Activate(spec.id)
		end)
		if spec.badge ~= "" then
			badge(tab, spec.badge, 20)
		end
		self.tabs[spec.id] = tab
	end

	-- One square slot per destination, plus a kart slot when the lobby wired
	-- one. Routed through _Activate so a hotbar press and a tab press cannot
	-- drift into meaning different things.
	local hotSpecs = table.clone(TABS)
	if opts.onCallKart then
		table.insert(hotSpecs, 1, { id = "_Kart", label = "KART", badge = "" })
	end
	for i, spec in hotSpecs do
		local slot = Instance.new("TextButton")
		slot.Name = "Hot_" .. spec.id
		slot.LayoutOrder = i
		slot.Size = UDim2.fromOffset(72, 72)
		slot.BackgroundColor3 = if spec.id == "_Kart" then GOLD else Color3.fromRGB(13, 14, 17)
		slot.BackgroundTransparency = 0.08
		slot.BorderSizePixel = 0
		slot.FontFace = FONT
		slot.Text = if spec.id == "PowerUps" then "POWER\nUPS" else spec.label
		slot.TextSize = 13
		slot.TextWrapped = true
		slot.TextColor3 = if spec.id == "_Kart" then BLACK else WHITE
		slot.AutoButtonColor = false
		slot.Parent = hotbar
		corner(slot, 12)
		addHotStroke(slot)
		UiSound.bind(slot)
		if spec.badge ~= "" then
			badge(slot, spec.badge, 18)
		end
		if spec.id == "_Kart" then
			self.kartHotSlot = slot
			slot.Activated:Connect(function()
				opts.onCallKart()
			end)
		else
			slot.Activated:Connect(function()
				self:_Activate(spec.id)
			end)
		end
	end

	if opts.onCallKart then
		kartAction.Visible = true
		kartAction.Activated:Connect(function()
			opts.onCallKart()
		end)
	end

	local settingsTop = button(iconBar, "TopSettings", "SET", Color3.fromRGB(15, 16, 19))
	settingsTop.Size = UDim2.fromScale(0.27, 0.72)
	settingsTop.TextSize = 13
	local friendsTop = button(iconBar, "TopFriends", "FR", Color3.fromRGB(15, 16, 19))
	friendsTop.Size = UDim2.fromScale(0.27, 0.72)
	friendsTop.TextSize = 13
	local inboxTop = button(iconBar, "TopInbox", "MAIL", Color3.fromRGB(15, 16, 19))
	inboxTop.Size = UDim2.fromScale(0.27, 0.72)
	inboxTop.TextSize = 11
	badge(inboxTop, "2", 16)

	settingsTop.Activated:Connect(function()
		self:SetStatus("Settings panel placeholder.")
	end)
	friendsTop.Activated:Connect(function()
		self:SetStatus("Friends panel placeholder.")
	end)
	inboxTop.Activated:Connect(function()
		self:SetStatus("Inbox panel placeholder.")
	end)

	eventArt.MouseEnter:Connect(function()
		self.carouselHover = true
		self:_TweenActiveCarouselScale(1.035)
	end)
	eventArt.MouseLeave:Connect(function()
		self.carouselHover = false
		self.carouselNextAt = os.clock() + CAROUSEL_ADVANCE_TIME
		self:_TweenActiveCarouselScale(1)
	end)
	prevSlide.Activated:Connect(function()
		UiSound.play("Click")
		self:_SetCarousel(self.carouselIndex - 1, false, -1)
	end)
	nextSlide.Activated:Connect(function()
		UiSound.play("Click")
		self:_SetCarousel(self.carouselIndex + 1, false, 1)
	end)

	local function play()
		UiSound.play("Click")
		self:SetStatus("Finding you a race...")
		opts.onPlay()
	end

	raceButton.Activated:Connect(play)
	raceButton.MouseEnter:Connect(function()
		UiSound.play("Hover")
		TweenService:Create(
			self.raceButtonScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1.04 }
		):Play()
	end)
	raceButton.MouseLeave:Connect(function()
		TweenService:Create(
			self.raceButtonScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)

	lobbyButton.Activated:Connect(function()
		UiSound.play("Click")
		opts.onLobby(function()
			self:Close()
		end)
	end)
	lobbyButton.MouseEnter:Connect(function()
		UiSound.play("Hover")
		TweenService:Create(
			self.lobbyButtonScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1.045 }
		):Play()
	end)
	lobbyButton.MouseLeave:Connect(function()
		TweenService:Create(
			self.lobbyButtonScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)

	self:_SetCarousel(1, true)
	self:Open()
	return self
end

function MainMenuHud:_TweenActiveCarouselScale(scale: number)
	local activeScale = self.carouselScales[self.carouselIndex]
	if not activeScale then
		return
	end
	TweenService:Create(
		activeScale,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = scale }
	):Play()
end

function MainMenuHud:_SetCarousel(index: number, instant: boolean, directionOverride: number?)
	local count = #self.carouselSlides
	if count == 0 then
		return
	end

	local previous = self.carouselIndex or 1
	local active = ((index - 1) % count) + 1
	self.carouselIndex = active
	self.carouselNextAt = os.clock() + CAROUSEL_ADVANCE_TIME

	if instant or previous == active then
		for i, slide in self.carouselSlides do
			local isActive = i == active
			self.carouselScales[i].Scale = if isActive and self.carouselHover then 1.035 else 1
			slide.Visible = isActive
			slide.Position = UDim2.fromScale(0.5, 0.5)
			slide.Size = UDim2.fromScale(1, 1)
			slide.Rotation = 0
			slide.ImageTransparency = if isActive then 0 else 1
			slide.ZIndex = if isActive then 10 else 1
		end
	else
		local direction = directionOverride or if index > previous then 1 else -1
		local oldSlide = self.carouselSlides[previous]
		local newSlide = self.carouselSlides[active]

		for i, slide in self.carouselSlides do
			local visible = i == previous or i == active
			self.carouselScales[i].Scale = if i == active and self.carouselHover then 1.035 else 1
			slide.Visible = visible
			slide.Size = UDim2.fromScale(1, 1)
			slide.Rotation = 0
			slide.ImageTransparency = if visible then 0 else 1
			slide.ZIndex = if i == active then 10 elseif i == previous then 9 else 1
		end

		oldSlide.Position = UDim2.fromScale(0.5, 0.5)
		newSlide.Position = UDim2.fromScale(0.5 + direction * 0.16, 0.5)
		newSlide.ImageTransparency = 0.08

		local tweenInfo = TweenInfo.new(0.46, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(oldSlide, tweenInfo, {
			Position = UDim2.fromScale(0.5 - direction * 0.12, 0.5),
			ImageTransparency = 1,
		}):Play()
		TweenService:Create(newSlide, tweenInfo, {
			Position = UDim2.fromScale(0.5, 0.5),
			ImageTransparency = 0,
		}):Play()

		task.delay(0.48, function()
			if self.carouselIndex ~= active then
				return
			end
			for i, slide in self.carouselSlides do
				local isActive = i == active
				self.carouselScales[i].Scale = if isActive and self.carouselHover then 1.035 else 1
				slide.Visible = isActive
				slide.Position = UDim2.fromScale(0.5, 0.5)
				slide.ImageTransparency = if isActive then 0 else 1
			end
		end)
	end

	for i, dot in self.carouselDots do
		dot.BackgroundColor3 = if i == active then GOLD else Color3.fromRGB(94, 94, 94)
	end
end

-- The active tab's rect, in the highlight parent's local (offset) space.
-- AbsolutePosition/Size are in real screen pixels (already through the root
-- UIScale), but the pill lives under that same scale — so divide it back out,
-- or the pill lands scale-factor off and drifts with distance from the left.
function MainMenuHud:_TabRect(tab: GuiObject): (UDim2, UDim2)
	local s = self.rootScale.Scale
	if s <= 0 then
		s = 1
	end
	local rel = (tab.AbsolutePosition - self.tabsHolder.AbsolutePosition) / s
	local size = tab.AbsoluteSize / s
	return UDim2.fromOffset(rel.X + size.X / 2, rel.Y + size.Y / 2), UDim2.fromOffset(size.X, size.Y)
end

-- Slide + resize the gold pill onto `tab`. Animated selects add a quick
-- shrink-then-pop so it reads as landing rather than gliding.
function MainMenuHud:_MoveHighlight(tab: GuiObject?, animate: boolean)
	local hl = self.tabHighlight
	if not hl or not tab then
		return
	end
	local pos, size = self:_TabRect(tab)
	if size.X.Offset <= 0 then
		return -- layout hasn't resolved yet; Update() will snap once it has
	end
	if not animate then
		hl.Position = pos
		hl.Size = size
		self.highlightScale.Scale = 1
		return
	end
	self.hlAnimating = true
	TweenService:Create(
		hl,
		TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = pos, Size = size }
	):Play()
	TweenService:Create(
		self.highlightScale,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 0.8 }
	):Play()
	task.delay(0.1, function()
		if not self.open then
			return
		end
		TweenService:Create(
			self.highlightScale,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)
	task.delay(0.3, function()
		self.hlAnimating = false
	end)
end

function MainMenuHud:Select(id: string)
	-- GARAGE is a real screen, not a placeholder tab: hand off rather than
	-- selecting it, so the menu never sits on a tab with nothing behind it.
	if id == "Garage" and self.opts.onGarage then
		self.opts.onGarage()
		return
	end
	self.active = id
	for tabId, tab in self.tabs do
		tab.TextColor3 = if tabId == id then BLACK else WHITE
	end
	self:_MoveHighlight(self.tabs[id], true)

	if id == "Play" then
		self:SetStatus("Quick Race is the main call to action. Press RACE to queue.")
	elseif id == "Karts" then
		self:SetStatus("Kart collection and equipped kart stats can live here.")
	elseif id == "Garage" then
		self:SetStatus("Garage will handle kart body, wheels, rims, spoilers, and other skins.")
	elseif id == "PowerUps" then
		self:SetStatus("Power-ups should be configured server-side before they become shop items.")
	elseif id == "Quests" then
		self:SetStatus("Missions and season progress can expand from the existing quest service.")
	elseif id == "Shop" then
		self:SetStatus("Shop rotation and Bolt catalogue will plug into this menu.")
	end
end

function MainMenuHud:SetStatus(message: string)
	self.status.Text = message
end

-- Scale-to-FIT the fixed 1600x900 canvas into the viewport (whole menu shrinks
-- together; never overflows a narrow window; no low floor).
function MainMenuHud:_FitScale()
	local cam = Workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize
	if viewport and viewport.Y > 0 then
		self.rootScale.Scale = math.clamp(math.min(viewport.X / 1600, viewport.Y / 900), 0.2, 1.35)
	end
end

-- Show/hide everything EXCEPT the persistent top bar (Tabs + IconBar). Closing
-- the menu "minimises" to that bar so lobby players can still navigate.
-- THE MENU IS A VISUAL STOP, NOT A SPAWN BLOCK.
--
-- The character still loads and stands in the lobby exactly as it would
-- otherwise — only its ability to WALK is taken away, and given straight back
-- on close. Blocking the spawn instead would mean the player has no character
-- to hand back to when they enter the lobby, which is the harder bug.
--
-- `DS_InMenu` is published on the player so other systems (and the server) can
-- ask "are they in the menu" without reaching into this module.
function MainMenuHud:_SetFrozen(frozen: boolean)
	Players.LocalPlayer:SetAttribute("BloxKartInMenu", frozen)

	local humanoid = self.opts.getHumanoid()
	if not humanoid then
		return -- character not up yet; CharacterAdded re-applies via Open
	end

	if frozen then
		-- Remembered rather than assumed: a lobby may not use the defaults,
		-- and restoring 16/50 would silently retune everyone's movement.
		if self.savedMove == nil then
			self.savedMove = { walk = humanoid.WalkSpeed, jump = humanoid.JumpPower, height = humanoid.JumpHeight }
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	elseif self.savedMove then
		humanoid.WalkSpeed = self.savedMove.walk
		humanoid.JumpPower = self.savedMove.jump
		humanoid.JumpHeight = self.savedMove.height
		self.savedMove = nil
	end
end

-- One route for a destination however it was pressed — tab or hotbar slot.
--
-- From the LOBBY (menu minimised) the two that already have somewhere real to
-- go do NOT drag the player back into the menu: PLAY races immediately, and
-- MISSIONS opens its panel over the lobby. Everything else re-opens the menu
-- focused on that tab, because that is where those screens live.
function MainMenuHud:_Activate(id: string)
	if not self.open then
		if id == "Play" then
			self.opts.onPlay()
			return
		end
		if id == "Quests" and self.opts.onQuests then
			self.opts.onQuests()
			return
		end
		self:Open()
	end
	self:Select(id)
end

function MainMenuHud:_SetContentVisible(on: boolean)
	for _, child in self.root:GetChildren() do
		if
			child:IsA("GuiObject")
			and child.Name ~= "LobbyHotbar"
		then
			child.Visible = on
		end
	end
	-- The two navigations swap rather than stack: full tab bar while the menu
	-- is open, square hotbar once it minimises into the lobby. The old
	-- KartAction chip is folded into the hotbar's kart slot.
	self.hotbar.Visible = not on
	self.kartAction.Visible = false
end

-- CALL KART / PUT AWAY, mirroring whatever the server last told VehicleHud.
function MainMenuHud:SetKartLabel(label: string)
	self.kartAction.Text = label
	-- The slot is square, so the two states are shortened to fit rather than
	-- wrapped into unreadable text.
	if self.kartHotSlot then
		self.kartHotSlot.Text = if label == Config.Lobby.DespawnText then "PUT\nAWAY" else "CALL\nKART"
	end
end

-- The kart on the menu stage — what the garage dresses. Nil until the stage
-- has been cloned, so callers must handle that.
function MainMenuHud:StageKart(): Instance?
	local stage = getMenuStage()
	return stage and stage:FindFirstChild("Kart", true)
end

-- Garage camera. `SetZoom` is absolute studs (0 = the authored framing),
-- `Zoom` nudges it. Clamped so you can neither fly through the kart nor
-- lose it off the back of the stage.
function MainMenuHud:SetZoom(studs: number)
	self.zoomTarget = math.clamp(studs, -10, 8)
end

function MainMenuHud:Zoom(delta: number)
	self:SetZoom(self.zoomTarget + delta)
end

-- Swing the camera around the kart. Deltas are in PIXELS of drag; pitch is
-- clamped short of the poles, where a look-at camera flips over.
function MainMenuHud:Orbit(dx: number, dy: number)
	local yaw = self.orbitTarget.X - dx * 0.006
	local pitch = math.clamp(self.orbitTarget.Y + dy * 0.005, -0.55, 0.7)
	self.orbitTarget = Vector2.new(yaw, pitch)
end

-- Back to the authored framing. Called when the garage closes so nobody is
-- left staring at the underside of a kart they have finished with.
function MainMenuHud:ResetView()
	self.zoomTarget = 0
	self.orbitTarget = Vector2.zero
end

-- Whether the garage owns the camera (suppresses idle parallax).
function MainMenuHud:SetInspecting(on: boolean)
	if self.inspecting == on then
		return
	end

	self.inspecting = on
	self.parallax = Vector2.zero
	self:ResetView()
	self.zoom = 0
	self.orbit = Vector2.zero

	local camera = Workspace.CurrentCamera
	if not camera or not self.open then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	if on then
		camera.FieldOfView = GARAGE_FOV
		return
	end

	local lobbyCamera = select(1, stageParts("Lobby"))
	if lobbyCamera then
		camera.CFrame = authoredCamera(lobbyCamera)
	end
	camera.FieldOfView = LOBBY_FOV
end

function MainMenuHud:SetChromeVisible(on: boolean)
	self:_SetContentVisible(on)
	-- The three the minimise deliberately keeps are hidden here too: the
	-- garage is a full screen of its own, and its panel sits exactly where
	-- the icon bar does.
	self.tabsHolder.Visible = on
	self.iconBar.Visible = on
	self.hotbar.Visible = false -- garage is a full screen; nothing else on it
	self.kartAction.Visible = on and self.kartActionEnabled
end

function MainMenuHud:Open()
	local wasOpen = self.open
	self.open = true
	self.gui.Enabled = true
	self:_SetContentVisible(true)
	self:_SetFrozen(true)

	if not wasOpen then
		UiSound.play("Open")
	end

	local camera = Workspace.CurrentCamera
	if camera and not self.cameraSaved then
		self.cameraSaved = {
			type = camera.CameraType,
			subject = camera.CameraSubject,
			cframe = camera.CFrame,
			-- Focus too: a Custom camera reads it for its own framing, and a
			-- stale one left pointing at the menu stage makes the first
			-- moments back in the lobby feel like the camera is elsewhere.
			focus = camera.Focus,
			fieldOfView = camera.FieldOfView,
		}
	end

	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = if self.inspecting then GARAGE_FOV else LOBBY_FOV
	end

	RunService:UnbindFromRenderStep(self.renderStepName)
	RunService:BindToRenderStep(self.renderStepName, RENDER_STEP_PRIORITY, function(dt)
		if self.open then
			self:Update(dt)
		end
	end)

	self.root.Position = UDim2.fromScale(0.5, 0.5)
	self.root.BackgroundTransparency = 1
	self:Update(0)
end

-- "Close" MINIMISES to the persistent top bar rather than hiding the whole GUI:
-- the lobby keeps the Tabs (+ IconBar) so players can navigate any time. Full
-- teardown is Destroy().
function MainMenuHud:Close()
	if not self.open then
		return
	end

	self.open = false
	self.inspecting = false
	UiSound.play("Close")
	self:_SetContentVisible(false)
	self:_SetFrozen(false) -- walking again, in the lobby they were standing in
	RunService:UnbindFromRenderStep(self.renderStepName)
	self:_FitScale()

	local camera = Workspace.CurrentCamera
	local saved = self.cameraSaved
	self.cameraSaved = nil

	if camera then
		-- THE LIVE HUMANOID WINS OVER THE SAVED SUBJECT.
		--
		-- cameraSaved is captured when the menu first opens, which is at client
		-- startup — usually BEFORE the character exists. Restoring that
		-- subject literally handed the camera a nil, so it followed nothing:
		-- the player stood at spawn while the view stayed put.
		--
		-- Same for the type: a menu that opened pre-character may have saved
		-- Scriptable from whatever was mid-setup, and restoring THAT would
		-- keep the camera frozen too. Custom is the correct state to hand back
		-- to the lobby regardless of what was there before.
		local humanoid = self.opts.getHumanoid()
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid or (if saved then saved.subject else nil)
		-- Only worth restoring when there is no subject to follow. With a
		-- humanoid, Custom recomputes the shot from the character anyway, and
		-- writing a startup CFrame first just costs a frame pointed elsewhere.
		if not humanoid and saved then
			camera.CFrame = saved.cframe
		end
		camera.Focus = if saved then saved.focus else camera.Focus
		camera.FieldOfView = if saved then saved.fieldOfView else (Config.Camera.FovBase or 70)
	end
end

function MainMenuHud:IsOpen(): boolean
	return self.open
end

function MainMenuHud:Update(dt: number)
	if not self.open then
		return
	end

	if not self.hlAnimating then
		self:_MoveHighlight(self.tabs[self.active], false)
	end

	local camera = Workspace.CurrentCamera

	-- OWNERSHIP IS EARNED, NOT ASSUMED.
	--
	-- Scriptable used to be set here unconditionally, but the CFrame is only
	-- written when a stage marker was actually found — so a missing MenuStage
	-- left the camera scriptable and pointed at nothing: a grey void, while
	-- the player stood correctly at their spawn. Falling back to Custom means
	-- a stage that failed to load costs you the backdrop, not the game.
	local haveStage = (stageParts(if self.inspecting then "Garage" else "Lobby")) ~= nil
	if camera and not haveStage then
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = self.opts.getHumanoid()
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end

	if camera and haveStage then
		camera.CameraType = Enum.CameraType.Scriptable

		if self.inspecting then
			local cameraPoint, lookAt, fitBounds = stageParts("Garage")

			if cameraPoint then
				local ease = math.clamp(dt * 9, 0, 1)
				self.zoom += (self.zoomTarget - self.zoom) * ease
				self.orbit = self.orbit:Lerp(self.orbitTarget, ease)

				local cframe = responsiveCamera(
					cameraPoint,
					lookAt,
					fitBounds,
					camera.ViewportSize,
					self.zoom,
					self.orbit,
					GARAGE_FOV,
					GARAGE_MAX_FOV,
					GARAGE_BASE_DOLLY,
					GARAGE_NARROW_DOLLY
				)

				self.parallax = self.parallax:Lerp(
					Vector2.zero,
					math.clamp(dt * MENU_PARALLAX_RATE, 0, 1)
				)

				camera.CFrame = cframe
				camera.FieldOfView = GARAGE_FOV
			end
		else
			local lobbyCamera = select(1, stageParts("Lobby"))

			if lobbyCamera then
				local baseCFrame = authoredCamera(lobbyCamera)
				local target = mouseParallaxTarget(camera.ViewportSize)
				self.parallax = self.parallax:Lerp(
					target,
					math.clamp(dt * MENU_PARALLAX_RATE, 0, 1)
				)

				camera.CFrame = applyParallax(baseCFrame, self.parallax)
				camera.FieldOfView = LOBBY_FOV
			end
		end
	end

	self:_FitScale()
	self.shine += dt

	if not self.carouselHover and os.clock() >= self.carouselNextAt then
		self:_SetCarousel(self.carouselIndex + 1, false, 1)
	end

	self.floorGlow.BackgroundTransparency = 1
end

function MainMenuHud:Destroy()
	self:Close()
	self.gui:Destroy()
	if localMenuStage and localMenuStage.Parent then
		localMenuStage:Destroy()
	end
	localMenuStage = nil
	menuStageAvatarUserId = nil
end

return MainMenuHud
