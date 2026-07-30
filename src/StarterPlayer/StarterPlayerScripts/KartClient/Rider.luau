--[[
	Rider — turns the steering wheel and puts the driver's hands on it.

	Runs for EVERY kart in the world, not just the one we're driving, so
	you see other players steering too. It keys off
	`VehicleSeat.SteerFloat`, which Roblox replicates from the driver, so
	no custom networking is needed. Purely cosmetic; never touches
	movement.

	TWO DIFFERENT JOINT PROBLEMS, TWO DIFFERENT TOOLS
	-------------------------------------------------
	The steering wheel is a Motor6D on the kart. Nothing else touches it,
	so writing `Transform` directly is fine.

	The driver's arms are Motor6Ds on a CHARACTER, and there the Animator
	owns `Transform` — it recomposes those joints every frame from the
	playing animation, so anything a script writes is discarded. The
	obvious workarounds both fail:

	  - write `C0` instead: read-only from a client script on character
	    joints, the engine rejects it outright
	  - stop the animation so nothing overwrites us: the Animator then
	    stops flushing joints at all, our writes go nowhere AND the
	    driver stands bolt upright instead of sitting

	So the arms use `IKControl`, which the animation system applies
	itself. It layers over the sit pose rather than fighting it, and it
	costs one instance per arm instead of a per-frame solve.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local RunService = game:GetService("RunService")

local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Util = require(BloxKart:WaitForChild("Util"))

local R = Config.Rider
local RIG = Config.Rig
local KART_TAG = "Kart"

local Rider = {}

--=====================================================================
--  RIG LOOKUP
--=====================================================================
local function findRig(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	-- R15
	local upperTorso = character:FindFirstChild("UpperTorso")
	local lHand = character:FindFirstChild("LeftHand")
	local rHand = character:FindFirstChild("RightHand")
	if upperTorso and lHand and rHand then
		return {
			humanoid = humanoid,
			torso = upperTorso,
			lRoot = if R.IKChainFromTorso then upperTorso else character:FindFirstChild("LeftUpperArm"),
			rRoot = if R.IKChainFromTorso then upperTorso else character:FindFirstChild("RightUpperArm"),
			lHand = lHand,
			rHand = rHand,
		}
	end

	-- R6: one bone per arm, so the chain can only ever be torso -> arm.
	local torso = character:FindFirstChild("Torso")
	local lArm = character:FindFirstChild("Left Arm")
	local rArm = character:FindFirstChild("Right Arm")
	if torso and lArm and rArm then
		return {
			humanoid = humanoid,
			torso = torso,
			lRoot = torso,
			rRoot = torso,
			lHand = lArm,
			rHand = rArm,
		}
	end

	return nil
end

--=====================================================================
--  IK CONTROLS
--
--  Parented to the Humanoid, which is what makes the animation system
--  apply them. Created once and left alone; the Target is a live
--  reference, so as the wheel turns the hands follow with no per-frame
--  work from us.
--=====================================================================
-- Elbow hint. Lives on the hitbox so it rides with the kart, and is
-- client-local like everything else here.
local function makePole(hitbox: BasePart, name: string, offset: Vector3): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = offset
	att.Parent = hitbox
	return att
end

local function makeControl(
	name: string,
	rig,
	root: Instance?,
	endEffector: Instance,
	target: Instance,
	pole: Attachment?,
	priority: number
)
	if not root then
		return nil
	end
	local ik = Instance.new("IKControl")
	ik.Name = name
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = root
	ik.EndEffector = endEffector
	ik.Target = target
	-- Without this the solver puts the elbow wherever it likes on the
	-- circle around the shoulder-hand axis, which is always straight out
	-- sideways.
	if pole then
		ik.Pole = pole
	end
	ik.Weight = R.IKWeight
	ik.SmoothTime = R.IKSmoothTime
	-- Distinct priorities so the solve order is deterministic rather
	-- than whichever control happened to be created first. Only bites
	-- when the chains overlap (IKChainFromTorso), but a stable order is
	-- worth having either way.
	ik.Priority = priority
	ik.Enabled = true
	ik.Parent = rig.humanoid
	return ik
end

local function clearControls(s)
	for _, key in { "ikL", "ikR", "poleL", "poleR" } do
		if s[key] then
			s[key]:Destroy()
			s[key] = nil
		end
	end
end

--=====================================================================
--  PER-KART STATE
--=====================================================================
local state: { [Model]: any } = {}

local function stateFor(kart: Model)
	local s = state[kart]
	if not s then
		s = { steer = 0, wheelSteer = 0, roll = 0, lastPos = nil, rig = nil, ikL = nil, ikR = nil, boundTo = nil }
		state[kart] = s
	end
	return s
end

-- Rate-limited so a per-frame failure doesn't flood Output. Prints only
-- when the reason changes, or once a second.
local lastReason, lastReasonAt = nil, 0
local function report(reason: string?)
	if not R.Debug then
		return
	end
	local now = os.clock()
	if reason ~= lastReason or now - lastReasonAt > 1 then
		lastReason, lastReasonAt = reason, now
		print("[Rider] " .. (reason or "hands on the wheel"))
	end
end

--=====================================================================
--  ROAD WHEELS
--
--  Cosmetic only — the hitbox decides how the kart moves, and these just
--  have to look like they belong to it. Fronts steer and roll, rears
--  roll.
--
--  Roll comes from how far the kart actually MOVED, not from a speed
--  value: this runs for every kart including other people's, and their
--  speed isn't replicated. Distance between frames is, because their
--  position is.
--=====================================================================
local function updateRoadWheels(kart: Model, s, dt: number)
	local hitbox = kart.PrimaryPart
	if not hitbox then
		return
	end

	-- Metres rolled since last frame -> radians, via the wheel's
	-- circumference. Signed, so reversing spins them backwards.
	local pos = hitbox.Position
	local moved = 0
	if s.lastPos then
		local delta = pos - s.lastPos
		moved = delta.Magnitude * math.sign(delta:Dot(hitbox.CFrame.LookVector))
	end
	s.lastPos = pos
	s.roll = (s.roll or 0) + moved / math.max(RIG.RoadWheelRadius, 0.1)

	-- Fronts lag the input a touch, like the steering wheel does.
	local maxLock = math.rad(RIG.RoadWheelSteer)
	s.wheelSteer = Util.approach(s.wheelSteer or 0, s.steer, RIG.RoadWheelSteerRate, dt)
	local lock = s.wheelSteer * maxLock

	-- Counter-steer. Mid-drift the body is yawed sideways while the kart
	-- still travels roughly forwards, so cancelling that angle points the
	-- fronts back down the ROAD instead of down the bodywork. It's the
	-- detail that makes a drift look deliberate rather than like the kart
	-- is simply facing the wrong way.
	--
	-- Local kart only: driftAngle isn't replicated, so other people's
	-- wheels just follow their steering. Worth it for the driver's own
	-- view, which is the one that has to feel good.
	local drift = kart:GetAttribute(Names.DRIFT)
	if typeof(drift) == "number" then
		lock -= drift * RIG.RoadWheelCounterSteer
	end

	-- Lock stop, which real steering has and which matters here for a
	-- specific reason: a SPINOUT drives driftAngle through several whole
	-- revolutions, and without this the front wheels would whirl round
	-- like a fan while the kart span.
	lock = math.clamp(lock, -maxLock, maxLock)

	for _, motor in kart:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Name == "RoadWheelMotor" then
			-- Yaw THEN pitch: steering turns the whole wheel, and the wheel
			-- rolls about its own axle afterwards. The other order would
			-- swing the axle around instead.
			-- Axes are per wheel and were measured at build time; see
			-- KartFactory. Falling back to the old assumption keeps a kart
			-- built before this change from breaking outright.
			local rollAxis = motor:GetAttribute(Names.ROLL_AXIS) or Vector3.xAxis
			local steerAxis = motor:GetAttribute(Names.STEER_AXIS) or Vector3.yAxis

			-- Steer THEN roll: steering swings the whole wheel about the
			-- kart's up, and the wheel spins on its axle within that. The
			-- other order would carry the axle around with the spin.
			local turn = if motor:GetAttribute(Names.WHEEL_FRONT)
				then CFrame.fromAxisAngle(steerAxis, -lock)
				else CFrame.new()
			motor.Transform = turn * CFrame.fromAxisAngle(rollAxis, s.roll)
		end
	end
end

local function updateKart(kart: Model, dt: number)
	local seat = kart:FindFirstChild("Seat")
	local hub = kart:FindFirstChild("SteeringWheel", true)
	if not (seat and seat:IsA("VehicleSeat") and hub and hub:IsA("BasePart")) then
		return
	end
	local motor = hub:FindFirstChild("WheelMotor")
	if not (motor and motor:IsA("Motor6D")) then
		return
	end

	local s = stateFor(kart)
	local occupant = seat.Occupant

	----------------------------------------------------------------
	-- Wheel. SteerFloat is replicated from the driver, so this works
	-- for other people's karts as well as our own. No Animator is
	-- involved here, so Transform is the right tool.
	----------------------------------------------------------------
	-- The kart's own attribute first, then the seat.
	--
	-- On a touch device the pad feeds Simulation directly and the
	-- VehicleSeat never sees a steer value at all, so SteerFloat alone
	-- would leave a mobile player's wheel dead straight while they corner.
	-- The driver's client writes its real steer onto its own kart; that
	-- doesn't replicate, so remote karts fall through to SteerFloat, which
	-- is right for anyone on a keyboard.
	local own = kart:GetAttribute(Names.STEER)
	local targetSteer = 0
	if occupant then
		targetSteer = if typeof(own) == "number" then own else seat.SteerFloat
	end
	s.steer = Util.approach(s.steer, targetSteer, R.WheelSmoothing, dt)
	local spin = -s.steer * math.rad(R.MaxWheelAngle)
	motor.Transform = CFrame.Angles(0, 0, if R.InvertWheel then -spin else spin)

	updateRoadWheels(kart, s, dt)

	----------------------------------------------------------------
	-- Hands
	----------------------------------------------------------------
	local character = occupant and occupant.Parent
	if not (R.IKEnabled and character) then
		if s.boundTo then
			clearControls(s)
			s.rig, s.boundTo = nil, nil
		end
		return
	end

	-- Rebuild when the driver changes or respawns.
	if s.boundTo ~= character or (s.ikL and not s.ikL.Parent) then
		clearControls(s)
		s.rig = findRig(character)
		s.boundTo = character

		if not s.rig then
			report("no arm rig on " .. character.Name .. " (neither R15 nor R6)")
			return
		end

		local gripL = hub:FindFirstChild("GripL")
		local gripR = hub:FindFirstChild("GripR")
		if not (gripL and gripR) then
			report("SteeringWheel has no GripL/GripR attachments")
			return
		end

		-- Elbow hints, mirrored across the kart's centreline.
		local hitbox = kart.PrimaryPart
		if hitbox then
			local p = R.ElbowPole
			s.poleL = makePole(hitbox, "_ElbowPoleL", Vector3.new(-p.X, p.Y, p.Z))
			s.poleR = makePole(hitbox, "_ElbowPoleR", p)
		end

		s.ikL = makeControl("KartIK_L", s.rig, s.rig.lRoot, s.rig.lHand, gripL, s.poleL, 1)
		s.ikR = makeControl("KartIK_R", s.rig, s.rig.rRoot, s.rig.rHand, gripR, s.poleR, 2)
		if not (s.ikL and s.ikR) then
			report("could not build IKControls — chain root missing")
			return
		end
		report(nil)
	end
end

--=====================================================================
--  START
--=====================================================================
function Rider.start()
	CollectionService:GetInstanceRemovedSignal(KART_TAG):Connect(function(kart)
		local s = state[kart]
		if s then
			clearControls(s)
		end
		state[kart] = nil
	end)

	-- The wheel still needs a per-frame nudge; the hands do not, because
	-- IKControl.Target is a live reference the engine follows.
	RunService:BindToRenderStep("KartRider", Enum.RenderPriority.Character.Value + 1, function(dt)
		for _, kart in CollectionService:GetTagged(KART_TAG) do
			if kart:IsA("Model") and kart.Parent then
				local ok, err = pcall(updateKart, kart, dt)
				if not ok then
					warn("[Rider] " .. tostring(err))
				end
			end
		end
	end)
end

return Rider
