--[[
	CameraRig — the chase camera.

	Roblox's default camera is locked to world-up, so it would stay
	upright while the kart rolled around a loop. This one rolls with the
	track normal instead, which means it has to be Scriptable — and that
	in turn means rebuilding mouse orbit ourselves (see Input).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local CAM = Config.Camera

local Lighting = game:GetService("Lighting")

local CameraRig = {}
CameraRig.__index = CameraRig

function CameraRig.new(sim)
	local camera = workspace.CurrentCamera
	-- One blur, created once and left in Lighting. Toggled rather than
	-- added and removed: churning post-processing instances is a hitch
	-- every time a boost starts.
	local blur = Instance.new("BlurEffect")
	blur.Name = "BloxKartSpeedBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting

	return setmetatable({
		camera = camera,
		-- Seeded behind the kart so the first frame doesn't fly in.
		pos = sim.pos - sim.forward * CAM.Distance + Vector3.yAxis * CAM.Height,
		up = Vector3.yAxis,
		snap = false,
		blur = blur,
		boostBack = 0,
		boostDrop = 0,
		lag = 0,
		shakePhase = 0,
		impact = 0,
		drop = 0,
		flip = 0,
		glide = 0,
	}, CameraRig)
end

function CameraRig:Engage(seatPart: BasePart)
	self.camera = workspace.CurrentCamera
	if CAM.Enabled then
		-- Scriptable, or Roblox keeps forcing the view back to world-up
		-- and fights the roll on every loop.
		self.camera.CameraType = Enum.CameraType.Scriptable
	else
		self.camera.CameraSubject = seatPart
	end
end

-- Always call this on teardown, or the player is left stuck in a
-- Scriptable camera on foot.
function CameraRig:Restore(humanoid: Humanoid?)
	self.camera.FieldOfView = CAM.FovBase
	if self.blur then
		self.blur.Size = 0
		self.blur.Enabled = false
	end
	self.camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		self.camera.CameraSubject = humanoid
	end
end

-- The kick when a stage BEGINS. The width it settles at is handled in
-- Update from the live burn stage — this is only the arrival.
-- The value for a burn stage, or 0 when nothing is burning. One helper,
-- so the field of view, the pull-back, the shake and the blur cannot
-- disagree about how fast things currently are.
local function pick(list: { number }, stage: number): number
	if stage <= 0 then
		return 0
	end
	return list[math.min(stage, #list)] or 0
end

function CameraRig:BoostPunch(tier: number)
	local n = math.max(#CAM.BoostFovStage, 1)
	self.camera.FieldOfView += CAM.BoostFovPunch * (tier / n)
end

-- Cut instead of sweep on the next frame. Call it after anything that
-- teleports the kart — a respawn, or being placed on the starting grid.
-- Letting the camera fly across the map to catch up is disorienting, and
-- on a long track it takes seconds.
-- The camera falling behind at the start of a burn. Strongest speed cue
-- there is: being overtaken by your own kart for a quarter of a second
-- says "that accelerated" better than any amount of blur.
function CameraRig:BoostLag(tier: number)
	self.lag = math.max(self.lag, pick(CAM.BoostLag, tier))
end

-- IMPACTS FEED ONE DECAYING CHANNEL. Several sources, one amplitude,
-- one decay rate — two separate shake timers end up fighting over the
-- same offset, and the loser is whichever ran second.
function CameraRig:Impact(amount: number)
	self.impact = math.max(self.impact or 0, amount)
end

-- Landing. Scaled by how hard, so a drift hop does nothing at all.
function CameraRig:Land(impact: number)
	if impact < CAM.LandShakeMin then
		return
	end
	local amt = math.min((impact - CAM.LandShakeMin) * CAM.LandShakePer, CAM.LandShakeMax)
	self:Impact(amt)
	-- The camera drops with the kart, a beat behind. That lag is the
	-- weight of the CAMERA, and it is what makes the landing feel shared
	-- rather than watched.
	self.drop = math.max(self.drop or 0, CAM.LandDrop * (amt / CAM.LandShakeMax))
end

function CameraRig:WallHit()
	self:Impact(CAM.WallShake)
end

function CameraRig:Snap()
	self.snap = true
end

function CameraRig:Update(dt: number, sim, input)
	local camera = self.camera

	-- READ FROM THE LIVE BURN STAGE, not from the event that started it.
	-- An event fires once; the width has to be held for as long as the
	-- stage lasts, or it decays back to the speed-only target and the
	-- next stage starts from scratch — which is exactly what made three
	-- boosts feel like the same boost three times.
	local burn = sim.burnStage or 0
	local hold = 0
	if burn > 0 then
		hold = CAM.BoostFovStage[math.min(burn, #CAM.BoostFovStage)] or 0
	end

	local fovTarget = CAM.FovBase + (CAM.FovAtTopSpeed - CAM.FovBase) * sim.speedFrac + hold
	-- Opens faster than it closes. Symmetrical rates make the widest
	-- stage look like it is still arriving after the burn has ended.
	local fovRate = if fovTarget > camera.FieldOfView then CAM.FovRiseRate else CAM.FovRate
	camera.FieldOfView = Util.approach(camera.FieldOfView, fovTarget, fovRate, dt)

	if not CAM.Enabled then
		return
	end

	-- Roll target is the surface normal, so the whole view rotates with
	-- the track through a loop.
	local camUp = sim.visualNormal.Unit

	-- Aim down the direction of TRAVEL, only partly following the
	-- drifted body. That's what makes a drift read as sideways rather
	-- than the camera just turning with you.
	local camLook = Util.orthonormal(Util.rotateAbout(sim.forward, sim.up, sim.driftAngle * CAM.DriftFollow), camUp)

	local pull = CAM.Distance + CAM.SpeedPull * sim.speedFrac + (if sim.boosting then CAM.BoostPull else 0)

	local anchor = sim.pos + camUp * CAM.LookHeight

	-- Build the offset in the kart's frame, then orbit it. Rotating
	-- about camUp (not world Y) is what keeps looking around sane while
	-- upside-down on a loop.
	-- THE SPEED FEEL, all of it on the camera. Pulled back and dropped
	-- toward the road as the burn stage climbs: a wider view with the
	-- kart smaller in it reads as covering ground, and height is most of
	-- why a chase cam feels slow — the further above the surface you
	-- are, the less of it appears to move.
	local stage = if sim then math.min(sim.burnStage or 0, #CAM.BoostPullBack) else 0
	self.boostBack = Util.approach(self.boostBack, pick(CAM.BoostPullBack, stage), CAM.FovRiseRate, dt)
	self.boostDrop = Util.approach(self.boostDrop, pick(CAM.BoostDrop, stage), CAM.FovRiseRate, dt)

	local offset = -camLook * (pull + self.boostBack) + camUp * (CAM.Height - self.boostDrop)
	if input.lookYaw ~= 0 or input.lookPitch ~= 0 then
		offset = Util.rotateAbout(offset, camUp, input.lookYaw)
		local pitchAxis = offset:Cross(camUp)
		if pitchAxis.Magnitude > 1e-3 then
			offset = Util.rotateAbout(offset, pitchAxis.Unit, input.lookPitch)
		end
	end
	local wanted = sim.pos + offset

	if input.consumeCamSnap() or self.snap then
		-- Look-back toggled, or the kart just respawned somewhere else:
		-- cut, don't sweep. Letting the camera fly across the map to
		-- catch up after a respawn is disorienting.
		self.pos = wanted
		self.up = camUp
		self.snap = false
	else
		-- Chase a little harder while free-looking so the orbit feels
		-- attached to the mouse rather than dragged behind it.
		--
		-- Look-back gets the same boost for a completely different reason.
		-- With the eye parked in FRONT of the kart, chase lag works
		-- AGAINST the offset instead of trailing behind it: a rate-9 lerp
		-- following a target moving at 120 studs/s settles ~13 studs
		-- behind it, and 13 studs is the entire look-back distance. The
		-- kart drives into its own camera and you get a close-up of the
		-- driver's face, worse the faster you go.
		local tight = input.isOrbiting() or input.lookingBack
		local rate = if tight then CAM.PosRate * CAM.OrbitChaseBoost else CAM.PosRate
		self.pos = self.pos:Lerp(wanted, math.min(rate * dt, 1))
	end
	-- The roll lags a little, which reads as the world tipping rather
	-- than the camera jumping.
	self.up = self.up:Lerp(camUp, math.min(CAM.RollRate * dt, 1))

	local eye = self.pos
	if CAM.Collide then
		-- Keep scenery out of the shot. On a loop the track itself is
		-- frequently between the camera and the kart.
		local span = eye - anchor
		local blocked = workspace:Raycast(anchor, span, sim.rayParams)
		if blocked then
			local safe = blocked.Position - anchor
			if safe.Magnitude > CAM.MinDistance then
				eye = anchor + safe * 0.92
			else
				eye = anchor + span.Unit * CAM.MinDistance
			end
		end
	end

	-- Absolute floor on how close the eye may end up, applied LAST so
	-- nothing downstream can undo it. The chase lerp, the orbit and the
	-- collision pull-in can each put the camera inside the kart; a
	-- slightly clipped wall is a far better failure than a shot of the
	-- driver's face.
	--
	-- Measured from the anchor, which is the kart centre — so this has to
	-- clear half the hitbox length, not zero.
	local fromAnchor = eye - anchor
	if fromAnchor.Magnitude < CAM.MinChase then
		local dir = if fromAnchor.Magnitude > 1e-3 then fromAnchor.Unit else -camLook
		eye = anchor + dir * CAM.MinChase
	end

	-- Drop the look-ahead as you orbit away, so looking back frames the
	-- kart rather than a point out in front of it.
	local ahead = CAM.LookAhead * (1 - math.min(math.abs(input.lookYaw) / math.pi, 1))
	local aim = sim.pos + camLook * ahead + camUp * CAM.LookHeight

	-- LAG. Held back along the view direction and reeled in, so the kart
	-- pulls away from the camera for a moment when a stage fires.
	if self.lag > 0.001 then
		eye -= camLook * self.lag
		self.lag = math.max(self.lag - CAM.BoostLagRecover * dt, 0)
	end

	-- SHAKE. Engine vibration, not an earthquake: anything you can
	-- consciously see becomes motion sickness inside a lap. Sine rather
	-- than random, because random noise on a camera reads as a dropped
	-- frame.
	-- FLIP AND GLIDE FRAMING, eased so the transitions are not cuts.
	--
	-- The camera deliberately does NOT roll with a flip. A camera that
	-- inverts with a barrel roll is one nobody can play through — the
	-- horizon goes with it and the player loses the reference they steer
	-- against. It shakes and widens instead: "something big is happening"
	-- without taking the world away.
	local flipping = if (sim.trickAngle or 0) ~= 0 then 1 else 0
	self.flip = Util.approach(self.flip, flipping, CAM.GlideRate, dt)
	if self.flip > 0.01 then
		camera.FieldOfView += CAM.FlipFov * self.flip
		eye -= camLook * (CAM.FlipPull * self.flip)
		self:Impact(CAM.FlipShake * self.flip * dt * 6)
	end

	-- Gliding pulls back and rises. A glide is about where you are GOING
	-- — the gap, the landing zone — and the ground game's tight framing
	-- puts all of that off the bottom of the screen.
	local gliding = if sim.state == "glide" then 1 else 0
	self.glide = Util.approach(self.glide, gliding, CAM.GlideRate, dt)
	if self.glide > 0.01 then
		camera.FieldOfView += CAM.GlideFov * self.glide
		eye -= camLook * (CAM.GlidePull * self.glide)
		eye += camUp * (CAM.GlideRise * self.glide)
	end

	-- The landing drop. Recovers on its own.
	if (self.drop or 0) > 0.001 then
		eye -= camUp * self.drop
		self.drop = math.max(self.drop - CAM.LandDropRecover * dt, 0)
	end

	local shake = pick(CAM.BoostShake, stage) + (self.impact or 0)
	if (self.impact or 0) > 0.001 then
		self.impact = math.max(self.impact - CAM.ImpactShakeDecay * dt, 0)
	end
	if shake > 0 then
		self.shakePhase += dt * (CAM.BoostShakeSpeed + CAM.ImpactShakeSpeed * math.min((self.impact or 0) * 3, 1))
		local side = camLook:Cross(camUp)
		eye += side * math.sin(self.shakePhase) * shake
		eye += camUp * math.sin(self.shakePhase * 1.7) * shake * 0.6
	end

	-- BLUR, kept because it is a camera effect rather than something
	-- drawn over the world.
	local wantBlur = pick(CAM.BoostBlur, stage)
	self.blur.Size = Util.approach(self.blur.Size, wantBlur, CAM.BlurRate, dt)
	local blurOn = self.blur.Size > 0.05
	if self.blur.Enabled ~= blurOn then
		self.blur.Enabled = blurOn
	end

	-- lookAt fails if up is parallel to the view direction.
	local viewDir = aim - eye
	if viewDir.Magnitude > 1e-3 and viewDir.Unit:Cross(self.up).Magnitude > 1e-3 then
		camera.CFrame = CFrame.lookAt(eye, aim, self.up)
	end
end

return CameraRig
