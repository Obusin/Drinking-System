--[[
	PlacementPreviewClient
	──────────────────────
	Reusable client-side placement preview system.
	Shows a ghost clone of the held item that follows the cursor (PC) or
	projects forward (mobile), with a white outline Highlight and a surface
	glow. Calls onConfirm() when the player commits the placement.

	Usage:
		local preview = PlacementPreviewClient.new({
			player              = player,
			isPlaceable         = function(tool) return tool:GetAttribute("DS_Drink") end,
			findNearestSurface  = function(player) return ... end,   -- returns BasePart? or nil
			activationRange     = 8,      -- studs; outside this range preview hides
			placeKey            = Enum.KeyCode.Q,
			onConfirm           = function(tool) ... end,
		})
		preview:Start()
		preview:Stop()   -- cleans up everything
--]]

local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local PlacementPreviewClient = {}
PlacementPreviewClient.__index = PlacementPreviewClient

---------------------------------------------------------------------
-- Ghost builder — strips scripts, makes parts semi-transparent
---------------------------------------------------------------------
local function buildGhost(tool: Tool): Model
	local ghost = Instance.new("Model")
	ghost.Name = "DS_PlacementGhost"

	local toolClone = tool:Clone()
	for _, child in ipairs(toolClone:GetChildren()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript")
			or child:IsA("ProximityPrompt") or child:IsA("ClickDetector") then
			child:Destroy()
		else
			child.Parent = ghost
		end
	end
	toolClone:Destroy()

	for _, desc in ipairs(ghost:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored      = true
			desc.CanCollide    = false
			desc.CanQuery      = false
			desc.CastShadow    = false
			-- Ghost-ify only VISIBLE parts. Blanket 0.45 was revealing hidden
			-- meshes (unselected garnishes, unused fill stages) in the preview.
			if desc.Transparency < 0.9 then
				desc.Transparency = math.max(desc.Transparency, 0.45)
			end
		end
	end

	-- White outline, no fill
	local hl = Instance.new("Highlight")
	hl.FillTransparency    = 1
	hl.OutlineColor        = Color3.fromRGB(255, 255, 255)
	hl.OutlineTransparency = 0
	hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee             = ghost
	hl.Parent              = ghost

	-- Pick the Handle or tallest part as primary
	local primary = ghost:FindFirstChild("Handle", true) or ghost:FindFirstChildWhichIsA("BasePart", true)
	if primary and primary:IsA("BasePart") then
		ghost.PrimaryPart = primary
	end

	ghost.Parent = workspace
	return ghost
end

---------------------------------------------------------------------
-- Surface glow highlight (separate from ghost, adorns the surface part)
---------------------------------------------------------------------
local function buildSurfaceHighlight(): Highlight
	local hl = Instance.new("Highlight")
	hl.FillColor           = Color3.fromRGB(180, 230, 255)
	hl.OutlineColor        = Color3.fromRGB(180, 230, 255)
	hl.FillTransparency    = 0.78
	hl.OutlineTransparency = 0.2
	hl.DepthMode           = Enum.HighlightDepthMode.Occluded
	hl.Enabled             = false
	hl.Parent              = workspace
	return hl
end


---------------------------------------------------------------------
-- Geometry helpers
---------------------------------------------------------------------
local function surfaceTopY(surface: BasePart): number
	return surface.Position.Y + surface.Size.Y * 0.5
end

local function clampToSurfaceXZ(surface: BasePart, worldPoint: Vector3): Vector3
	local local_ = surface.CFrame:PointToObjectSpace(worldPoint)
	local hx = surface.Size.X * 0.5 - 0.3
	local hz = surface.Size.Z * 0.5 - 0.3
	return surface.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(local_.X, -hx, hx),
		0,
		math.clamp(local_.Z, -hz, hz)
	))
end

local function ghostHalfHeight(ghost: Model): number
	local _, size = ghost:GetBoundingBox()
	return math.max(size.Y * 0.5, 0.3)
end

local function forwardProjectedPos(player: Player, surface: BasePart, ghost: Model): CFrame
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local halfH = ghostHalfHeight(ghost)
	local topY  = surfaceTopY(surface)

	local x, z = surface.Position.X, surface.Position.Z
	if root then
		local fwd = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if fwd.Magnitude > 0.01 then
			fwd = fwd.Unit
		end
		local preferred = clampToSurfaceXZ(surface, root.Position + fwd * 2.5)
		x, z = preferred.X, preferred.Z
	end

	local yaw = root and math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z) or 0
	return CFrame.new(x, topY + halfH, z) * CFrame.Angles(0, yaw, 0)
end

-- PC: raycast through cursor; returns the surface part hit and the world position, or nil.
local function cursorRaycastSurface(player: Player, isSurface: (BasePart) -> boolean): (BasePart?, Vector3?)
	local char = player.Character
	local cam  = workspace.CurrentCamera
	if not char or not cam then return nil, nil end

	local mousePos = UserInputService:GetMouseLocation()
	local ray      = cam:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- exclude character and any ghost already in workspace
	local excludes = { char }
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == "DS_PlacementGhost" then
			table.insert(excludes, obj)
		end
	end
	params.FilterDescendantsInstances = excludes

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result then return nil, nil end

	local hit = result.Instance
	if not hit:IsA("BasePart") then return nil, nil end

	-- Walk up to check if hit or ancestor is a surface
	local candidate: BasePart? = nil
	if isSurface(hit) then
		candidate = hit
	else
		local ancestor = hit.Parent
		while ancestor and ancestor ~= workspace do
			if ancestor:IsA("BasePart") and isSurface(ancestor) then
				candidate = ancestor :: BasePart
				break
			end
			ancestor = ancestor.Parent
		end
	end

	if candidate then
		return candidate, result.Position
	end
	return nil, nil
end

---------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------
function PlacementPreviewClient.new(config: {
	player:             Player,
	isPlaceable:        (tool: Tool) -> boolean,
	isSurface:          (part: BasePart) -> boolean,
	findNearestSurface: (player: Player) -> BasePart?,
	activationRange:    number?,
})
	local self         = setmetatable({}, PlacementPreviewClient)
	self._player       = config.player
	self._isPlaceable  = config.isPlaceable
	self._isSurface    = config.isSurface
	self._findNearest  = config.findNearestSurface
	self._range        = config.activationRange or 8

	self._ghost             = nil  -- Model?
	self._lastTool          = nil  -- Tool? (ghost was built from this)
	self._lastPreviewCFrame = nil  -- CFrame? last computed ghost position
	self._surfaceHL         = buildSurfaceHighlight()
	self._lastSurface       = nil
	self._active            = false
	self._connections       = {}

	return self
end

---------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------
function PlacementPreviewClient:_getEquippedPlaceable(): Tool?
	local char = self._player.Character
	if not char then return nil end
	for _, inst in ipairs(char:GetChildren()) do
		if inst:IsA("Tool") and self._isPlaceable(inst) then
			return inst
		end
	end
	return nil
end

function PlacementPreviewClient:_destroyGhost()
	if self._ghost then
		self._ghost:Destroy()
		self._ghost    = nil
		self._lastTool = nil
	end
end

function PlacementPreviewClient:_ensureGhost(tool: Tool): Model
	if self._ghost and self._lastTool == tool then
		return self._ghost
	end
	self:_destroyGhost()
	self._ghost    = buildGhost(tool)
	self._lastTool = tool
	return self._ghost
end

function PlacementPreviewClient:_setSurface(surface: BasePart?)
	if surface ~= self._lastSurface then
		self._lastSurface          = surface
		self._surfaceHL.Adornee    = surface
		self._surfaceHL.Enabled    = surface ~= nil
	end
end

function PlacementPreviewClient:_hideAll()
	self:_destroyGhost()
	self:_setSurface(nil)
end

---------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------
function PlacementPreviewClient:_update()
	local tool = self:_getEquippedPlaceable()
	if not tool then
		self:_hideAll()
		return
	end

	local char = self._player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local surface = self._findNearest(self._player)

	if not surface or not root then
		self:_hideAll()
		return
	end

	-- Range check (bounding-box closest point)
	local localPoint = surface.CFrame:PointToObjectSpace(root.Position)
	local half = surface.Size * 0.5
	local clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	local dist = (surface.CFrame:PointToWorldSpace(clampedLocal) - root.Position).Magnitude
	if dist > self._range then
		self:_hideAll()
		return
	end

	if IS_MOBILE then
		-- Mobile: only highlight the surface — ghost is shown on tap via showAtPosition.
		self:_setSurface(surface)
		return
	end

	-- PC: only show ghost when cursor is pointing at a valid surface.
	local hitSurface, hitPos = cursorRaycastSurface(self._player, self._isSurface)
	if not hitSurface or not hitPos then
		self:_hideAll()
		return
	end

	local ghost = self:_ensureGhost(tool)
	local clampedPos = clampToSurfaceXZ(hitSurface, hitPos)
	self:_setSurface(hitSurface)
	local yaw = root and math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z) or 0
	local targetCF = CFrame.new(clampedPos.X, surfaceTopY(hitSurface) + ghostHalfHeight(ghost), clampedPos.Z)
		* CFrame.Angles(0, yaw, 0)
	self._lastPreviewCFrame = targetCF
	pcall(function() ghost:PivotTo(targetCF) end)
end

---------------------------------------------------------------------
-- Mobile API: show ghost at exact tap position, hide ghost only
---------------------------------------------------------------------
function PlacementPreviewClient:showAtPosition(worldPos: Vector3, surface: BasePart?)
	local tool = self:_getEquippedPlaceable()
	if not tool then return end
	local ghost = self:_ensureGhost(tool)
	local char = self._player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local yaw = root and math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z) or 0
	local halfH = ghostHalfHeight(ghost)
	local topY = surface and surfaceTopY(surface) or worldPos.Y
	local targetCF = CFrame.new(worldPos.X, topY + halfH, worldPos.Z) * CFrame.Angles(0, yaw, 0)
	self._lastPreviewCFrame = targetCF
	pcall(function() ghost:PivotTo(targetCF) end)
end

-- Hide ghost only — surface highlight stays driven by _update proximity check.
function PlacementPreviewClient:hideGhost()
	self:_destroyGhost()
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------
-- True when the ghost is currently visible (player is near a valid surface).
function PlacementPreviewClient:isPreviewActive(): boolean
	return self._ghost ~= nil
end

-- Returns the last computed preview position, or nil if no ghost is active.
function PlacementPreviewClient:getPreviewPosition(): Vector3?
	if self._ghost and self._lastPreviewCFrame then
		return self._lastPreviewCFrame.Position
	end
	return nil
end

function PlacementPreviewClient:Start()
	if self._active then return end
	self._active = true

	-- Visual-only: just run the per-frame ghost/highlight update.
	-- Placement is confirmed externally (e.g. click-on-surface intercept in the game controller).
	local renderConn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function() self:_update() end)
		if not ok then
			warn("[PlacementPreviewClient] _update error:", err)
		end
	end)
	table.insert(self._connections, renderConn)
end

function PlacementPreviewClient:Stop()
	self._active = false
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}

	self:_destroyGhost()
	self._surfaceHL:Destroy()
end

return PlacementPreviewClient
