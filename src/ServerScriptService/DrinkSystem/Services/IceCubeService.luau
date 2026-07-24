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
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local IceCubeService = {}

local TEMPLATE_FOLDER_NAME = "IceCubeTemplates"
local PADDING = Vector3.new(2, 2.5, 2) -- extra room so the rig doesn't clip the walls

local CORNER_SIGNS = {
	Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
	Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1),
}

-- Model:GetBoundingBox() sweeps EVERY descendant including an equipped Tool
-- (a held glass out at arm's length balloons the box hugely). This computes
-- bounds from body parts only — Tool geometry is ignored entirely, exactly
-- as it should be for sizing the cube around the PLAYER, not their gear.
local function computeBodyBounds(character: Model): (CFrame, Vector3)
	local minV, maxV
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and not part:FindFirstAncestorWhichIsA("Tool") then
			local half = part.Size * 0.5
			for _, signs in ipairs(CORNER_SIGNS) do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * signs.X, half.Y * signs.Y, half.Z * signs.Z))
				if not minV then
					minV, maxV = corner, corner
				else
					minV = Vector3.new(math.min(minV.X, corner.X), math.min(minV.Y, corner.Y), math.min(minV.Z, corner.Z))
					maxV = Vector3.new(math.max(maxV.X, corner.X), math.max(maxV.Y, corner.Y), math.max(maxV.Z, corner.Z))
				end
			end
		end
	end
	if not minV then
		return character:GetPivot(), Vector3.new(2, 3, 2) -- fallback, shouldn't happen
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end

-- Deliberately slippery — a bump should send the cube (and its passenger)
-- sliding a good distance, not just nudge in place. Density barely matters
-- since the cube is Massless (see Trap()) — kept low anyway for consistency.
local ICE_PHYSICAL_PROPERTIES = PhysicalProperties.new(
	0.3,  -- density — irrelevant while Massless, low if that ever changes
	0.05, -- friction — LOW, this is the "slide" feel
	0.1,  -- elasticity — barely bouncy
	1,    -- frictionWeight
	1     -- elasticityWeight
)

-- Passive humanoid-to-part collisions in Roblox are pretty weak by default —
-- low friction alone reads as "barely moves." A Touched-based shove gives it
-- the actual fun "hehehe" oomph; the speed cap + cooldown keep it from ever
-- flinging someone across the map from one graze (the "not buggy" part).
local PUSH_IMPULSE_SPEED = 34 -- studs/sec added per shove, horizontal only
local PUSH_MAX_SPEED = 55     -- hard clamp on resulting horizontal speed
local PUSH_SPIN_SPEED = 5     -- rad/sec of tumble added per shove
local PUSH_MAX_SPIN = 9       -- hard clamp on resulting tumble speed
local PUSH_COOLDOWN = 0.6     -- per-pusher debounce so leaning on it doesn't runaway-accelerate

-- Disabled outright (not just reverted after the fact) so nothing — jump
-- input, a queued emote's state flip, etc. — can ever flash a movement
-- animation before our per-frame checks catch it. Ragdoll/Dead/Seated/
-- GettingUp/Physics are deliberately left alone so other systems (drunk
-- collapse, death) keep working normally if they ever overlap a trap.
local FROZEN_DISABLED_STATES = {
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Landed,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.StrafingNoPhysics,
}

type TrapState = {
	Cube: BasePart,
	Weld: WeldConstraint,
	Conn: RBXScriptConnection,
	AnimConn: RBXScriptConnection?,
	ExpiresAt: number,
}

local trapped: { [Player]: TrapState } = {}

-- The default character Animate script keeps looping whatever animation
-- (idle/walk) was last playing — Physics state alone doesn't tell it to
-- stop. AnimationTracks are visible/controllable from the server, so we
-- just stop them every frame; cheap (usually 0-1 tracks) and reliably wins
-- against the client re-triggering one.
local function freezeAnimations(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

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
	if state.AnimConn then
		state.AnimConn:Disconnect()
	end
	if state.Cube and state.Cube.Parent then
		state.Cube:Destroy()
	end
	pcall(function()
		Packets.IceCubeFrozen.sendTo({ Trapped = false }, player)
	end)

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.WalkSpeed = humanoid:GetAttribute("DS_PreIceWalkSpeed") or 16
		humanoid.JumpPower = humanoid:GetAttribute("DS_PreIceJumpPower") or 50
		humanoid.AutoRotate = true
		for _, stateType in ipairs(FROZEN_DISABLED_STATES) do
			humanoid:SetStateEnabled(stateType, true)
		end
		-- Hand control back — GettingUp is the standard "resume normal
		-- control" transition out of a forced Physics state
		if humanoid:GetState() == Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			pcall(function()
				hrp:SetNetworkOwnershipAuto() -- give responsiveness back to their client
			end)
		end
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

	-- Fits ANY avatar automatically — no manual sizing per character.
	-- Body-only bounds (Tool geometry excluded, see computeBodyBounds).
	local boundsCFrame, boundsSize = computeBodyBounds(char)

	local cube = template:Clone()
	cube.Name = "DS_IceCubeTrap_" .. player.Name
	cube.Size = boundsSize + PADDING
	cube.CFrame = boundsCFrame
	cube.Anchored = false
	cube.CanCollide = true
	-- Massless: the cube itself contributes ZERO weight to the welded
	-- assembly, so total mass is just the trapped player's own body — light
	-- enough that a normal shove actually sends them sliding, instead of the
	-- character-sized mesh (dozens of studs^3) making it push like a boulder.
	cube.Massless = true
	cube.Material = Enum.Material.Ice
	cube.Transparency = 0.25
	cube.Color = Color3.fromRGB(200, 235, 255)
	cube.CustomPhysicalProperties = ICE_PHYSICAL_PROPERTIES
	cube.Parent = workspace

	-- Rigid attach: the character's whole rig follows the cube through
	-- normal joint physics (same reason pushing any standing character's
	-- HRP already moves their whole body) — no manual position syncing needed.
	local weld = Instance.new("WeldConstraint")
	weld.Name = "DS_IceCubeWeld"
	weld.Part0 = cube
	weld.Part1 = hrp
	weld.Parent = cube

	-- Shove mechanic: another player's body part touching the cube gives it
	-- a real velocity kick, away from the pusher, horizontal-only (no
	-- launching), clamped to PUSH_MAX_SPEED, debounced per pusher.
	local lastPushAt: { [Player]: number } = {}
	cube.Touched:Connect(function(hit)
		local hitChar = hit:FindFirstAncestorOfClass("Model")
		local pusher = hitChar and Players:GetPlayerFromCharacter(hitChar)
		if not pusher or pusher == player then
			return -- ignore world geometry and the trapped player's own body
		end
		local now = os.clock()
		if lastPushAt[pusher] and now - lastPushAt[pusher] < PUSH_COOLDOWN then
			return
		end
		lastPushAt[pusher] = now

		local pusherHrp = hitChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pusherHrp then
			return
		end

		-- Standing/riding ON TOP shouldn't shove every touch (feet stay in
		-- continuous contact while standing still, which used to ramp the
		-- cube straight to max speed and keep it there forever — "they keep
		-- on going"). Only a clear side hit counts as a shove; someone
		-- clearly above the cube's own center is riding it, not bumping it.
		if pusherHrp.Position.Y > cube.Position.Y + 0.5 then
			return
		end

		local direction = cube.Position - pusherHrp.Position
		direction = Vector3.new(direction.X, 0, direction.Z)
		if direction.Magnitude < 0.1 then
			direction = pusherHrp.CFrame.LookVector
		end
		direction = direction.Unit

		local currentVel = cube.AssemblyLinearVelocity
		local horizontal = Vector3.new(currentVel.X, 0, currentVel.Z) + direction * PUSH_IMPULSE_SPEED
		if horizontal.Magnitude > PUSH_MAX_SPEED then
			horizontal = horizontal.Unit * PUSH_MAX_SPEED
		end
		cube.AssemblyLinearVelocity = Vector3.new(horizontal.X, currentVel.Y, horizontal.Z)

		-- Tumble: spin around the horizontal axis perpendicular to the push
		-- (the WeldConstraint means the frozen character tumbles right along
		-- with it — a proper yeet, not just a smooth slide)
		local tumbleAxis = direction:Cross(Vector3.yAxis)
		if tumbleAxis.Magnitude < 0.01 then
			tumbleAxis = Vector3.xAxis
		end
		tumbleAxis = tumbleAxis.Unit

		local newAngular = cube.AssemblyAngularVelocity + tumbleAxis * PUSH_SPIN_SPEED
		if newAngular.Magnitude > PUSH_MAX_SPIN then
			newAngular = newAngular.Unit * PUSH_MAX_SPIN
		end
		cube.AssemblyAngularVelocity = newAngular
	end)

	-- Remember their REAL speed (drunkness may have already modified it) so
	-- release restores exactly what they had, not a hardcoded default
	humanoid:SetAttribute("DS_PreIceWalkSpeed", humanoid.WalkSpeed)
	humanoid:SetAttribute("DS_PreIceJumpPower", humanoid.JumpPower)

	-- The trapped player's OWN CLIENT normally owns the physics/network
	-- authority for their character — their local movement controller keeps
	-- re-asserting Running state, silently overriding our replicated
	-- WalkSpeed/ChangeState calls. Taking server ownership removes that
	-- fight entirely; other players pushing the (now server-owned) cube
	-- still resolves correctly, that's a normal cross-ownership collision.
	local ok = pcall(function()
		hrp:SetNetworkOwner(nil)
	end)
	if not ok then
		warn("[IceCubeService] Could not take server network ownership of", player.Name)
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	for _, stateType in ipairs(FROZEN_DISABLED_STATES) do
		humanoid:SetStateEnabled(stateType, false)
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	freezeAnimations(humanoid)
	pcall(function()
		Packets.IceCubeFrozen.sendTo({ Trapped = true }, player)
	end)

	-- Instant kill: fires the moment ANY track starts (jump, a queued emote,
	-- whatever) — far tighter than waiting for the next Heartbeat, so
	-- nothing gets a visible frame to play before we stop it.
	local animConn: RBXScriptConnection? = nil
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		animConn = animator.AnimationPlayed:Connect(function(track)
			track:Stop(0)
		end)
	end

	local dur = duration or 20
	local expiresAt = os.clock() + dur

	-- Pin every frame: Enum.HumanoidStateType.Physics is the hard lock — it
	-- strips ALL input/AI control from the humanoid (no walking, no jumping,
	-- no auto-rotate) while the character stays a normal, pushable physics
	-- body — same technique this project's own ragdoll system already uses.
	-- WalkSpeed/JumpPower are zeroed too as a belt-and-suspenders (and
	-- because DrunkEffectsService writes WalkSpeed every frame based on
	-- drunk stage, which a one-time set alone would lose the race against).
	local conn = RunService.Heartbeat:Connect(function()
		-- Health check catches death IMMEDIATELY — Parent can stay non-nil
		-- for a while after death (corpse lingers before the engine clears
		-- it), which used to let this loop keep fighting a dead humanoid
		-- forever and permanently block the NEXT character from ever being
		-- trapped or released.
		if not humanoid.Parent or humanoid.Health <= 0 then
			release(player)
			return
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
		freezeAnimations(humanoid)
		-- Equipping a tool (e.g. grabbing a fresh glass) can silently hand
		-- network ownership back to the client, which then resumes driving
		-- movement locally — reassert every frame so that can never stick.
		if hrp.Parent then
			pcall(function()
				hrp:SetNetworkOwner(nil)
			end)
		end
		if os.clock() >= expiresAt then
			release(player)
		end
	end)

	trapped[player] = { Cube = cube, Weld = weld, Conn = conn, AnimConn = animConn, ExpiresAt = expiresAt }
end

function IceCubeService.init()
	Players.PlayerRemoving:Connect(release)

	-- Guaranteed safety net: force a clean release the instant ANY new
	-- character spawns, regardless of whether the Heartbeat loop's own
	-- death detection already fired. Without this, a respawn during a trap
	-- could leave the player permanently unable to be trapped OR released.
	local function hookRespawn(player: Player)
		player.CharacterAdded:Connect(function()
			release(player)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		hookRespawn(player)
	end
	Players.PlayerAdded:Connect(hookRespawn)
end

return IceCubeService
