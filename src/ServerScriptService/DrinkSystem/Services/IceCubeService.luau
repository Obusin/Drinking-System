-- IceCubeService: freeze a player and physically trap them inside a sliding
-- ice-cube mesh sized to fit their character. The cube is a real, unanchored
-- physics part welded to their HumanoidRootPart — no scripted "slide", other
-- players bumping the cube push it (and the trapped player) around for free.
--
-- Studio setup: drop your ice cube MeshPart anywhere under
--   ReplicatedStorage/DrinkSystem/IceCubeTemplates
-- (create that Folder if missing). Any name works — the first MeshPart found
-- inside is cloned per trap and resized to the target's bounding box.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")

local IceCubeService = {}

local TEMPLATE_FOLDER_NAME = "IceCubeTemplates"
local PADDING = Vector3.new(2, 2.5, 2) -- extra room so the rig doesn't clip the walls

type TrapState = {
	Cube: BasePart,
	Weld: WeldConstraint,
	Conn: RBXScriptConnection,
	ExpiresAt: number,
}

local trapped: { [Player]: TrapState } = {}

local function findTemplate(): BasePart?
	local folder = DrinkSystem:FindFirstChild(TEMPLATE_FOLDER_NAME)
	if not folder then
		return nil
	end
	return (folder:FindFirstChildWhichIsA("MeshPart", true) :: BasePart?)
		or folder:FindFirstChildWhichIsA("BasePart", true)
end

local function release(player: Player)
	local state = trapped[player]
	if not state then
		return
	end
	trapped[player] = nil
	if state.Conn then
		state.Conn:Disconnect()
	end
	if state.Cube and state.Cube.Parent then
		state.Cube:Destroy()
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = humanoid:GetAttribute("DS_PreIceWalkSpeed") or 16
		humanoid.JumpPower = humanoid:GetAttribute("DS_PreIceJumpPower") or 50
		humanoid.AutoRotate = true
	end
end

function IceCubeService.IsTrapped(player: Player): boolean
	return trapped[player] ~= nil
end

function IceCubeService.Trap(player: Player, duration: number?)
	if trapped[player] then
		return -- already trapped — don't stack cubes
	end
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not hrp or humanoid.Health <= 0 then
		return
	end

	local template = findTemplate()
	if not template then
		warn(("[IceCubeService] No mesh found in ReplicatedStorage.DrinkSystem.%s — drop your ice cube MeshPart there"):format(TEMPLATE_FOLDER_NAME))
		return
	end

	-- Fits ANY avatar automatically — no manual sizing per character
	local boundsCFrame, boundsSize = char:GetBoundingBox()

	local cube = template:Clone()
	cube.Name = "DS_IceCubeTrap_" .. player.Name
	cube.Size = boundsSize + PADDING
	cube.CFrame = boundsCFrame
	cube.Anchored = false
	cube.CanCollide = true
	cube.Massless = false
	cube.Material = Enum.Material.Ice
	cube.Transparency = 0.25
	cube.Color = Color3.fromRGB(200, 235, 255)
	cube.Parent = workspace

	-- Rigid attach: the character's whole rig follows the cube through
	-- normal joint physics (same reason pushing any standing character's
	-- HRP already moves their whole body) — no manual position syncing needed.
	local weld = Instance.new("WeldConstraint")
	weld.Name = "DS_IceCubeWeld"
	weld.Part0 = cube
	weld.Part1 = hrp
	weld.Parent = cube

	-- Remember their REAL speed (drunkness may have already modified it) so
	-- release restores exactly what they had, not a hardcoded default
	humanoid:SetAttribute("DS_PreIceWalkSpeed", humanoid.WalkSpeed)
	humanoid:SetAttribute("DS_PreIceJumpPower", humanoid.JumpPower)

	local dur = duration or 20
	local expiresAt = os.clock() + dur

	-- Pin movement every frame — DrunkEffectsService also writes WalkSpeed
	-- continuously based on drunk stage, so a one-time set alone would get
	-- overwritten within a tick. This wins every frame instead.
	local conn = RunService.Heartbeat:Connect(function()
		if not humanoid.Parent then
			release(player) -- character died/respawned mid-trap
			return
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		if os.clock() >= expiresAt then
			release(player)
		end
	end)

	trapped[player] = { Cube = cube, Weld = weld, Conn = conn, ExpiresAt = expiresAt }
end

function IceCubeService.init()
	Players.PlayerRemoving:Connect(release)
end

return IceCubeService
