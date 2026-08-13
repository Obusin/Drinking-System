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
local Names = require(BloxKart:WaitForChild("Names"))
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
		dropTo = 0,
		kick = 0,
		kickTo = 0,
		flip = 0,
		glide = 0,
		hopFollow = 0,
		sway = 0,
		bikeCam = nil,
		camRoll = 0,
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
	-- A TARGET, not the value. The camera eases onto it below rather than
	-- being placed, or the landing frame teleports the eye.
	self.dropTo = math.max(self.dropTo or 0, CAM.LandDrop * (amt / CAM.LandShakeMax))
	-- AND THE FRAME OPENS BACK UP. Flips and glides now pull the camera
	-- IN, so a landing is the moment that tight framing is released —
	-- kicking outwards past neutral and settling gives that release a
	-- beat instead of just easing away. Same `amt` as the drop, so it is
	-- already scaled by how hard the landing was.
	self.kickTo = math.max(self.kickTo or 0, CAM.LandKick * (amt / CAM.LandShakeMax))
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

	--=================================================================
	--  THE BIKE CAMERA IS CLOSER, LOWER AND LOOKS FURTHER AHEAD.
	--
	--  More intimate and more aggressive than the kart's, because a bike
	--  is a smaller thing and the same framing makes it look lost.
	--
	--  Resolved once and cached: this is a per-vehicle constant, and
	--  reading an attribute plus a config table every frame to learn
	--  something that cannot change is work for nothing.
	--=================================================================
	if self.bikeCam == nil then
		local kart = sim.model
		local kind = kart and kart:GetAttribute(Names.VEHICLE_KIND)
		self.bikeCam = kind == "bike"
	end
	local BK = Config.Bike

	local pull = CAM.Distance + CAM.SpeedPull * sim.speedFrac + (if sim.boosting then CAM.BoostPull else 0)
	if self.bikeCam then
		pull += BK.CamDistance
	end

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

	--=================================================================
	--  RISE OVER A WHEELIE, so the bike does not eat the corner.
	--
	--  A 30-degree nose-up puts the front of the machine across a good
	--  part of the screen — exactly the part you are steering into. That
	--  is the one way a purely visual effect can still cost a race, and
	--  the fix is not to shrink the wheelie but to look over it.
	--
	--  Tied to the wheelie's own value, so it arrives and leaves with it
	--  and there is nothing to keep in step.
	--=================================================================
	local height = CAM.Height - self.boostDrop + (if self.bikeCam then BK.CamHeight else 0)
	if self.bikeCam then
		local up = (sim.wheelie or 0) / math.max(BK.WheelieCamAt, 1e-3)
		height += math.clamp(up, 0, 1) * BK.WheelieCamRise
	end
	local offset = -camLook * (pull + self.boostBack) + camUp * height
	--=================================================================
	--  SWIM SWAY — the camera gets thrown to the outside of the turn.
	--
	--  Turn left and the eye slides RIGHT; turn right and it slides
	--  LEFT. It is the camera behaving like it has mass and is being
	--  swung wide, and it is the cheapest way to make a boat feel heavy
	--  — a hull takes a moment to come round, and the camera being
	--  thrown while it does sells the wait.
	--
	--  A SLIDE, NOT AN ORBIT. Orbiting the eye around the kart swings
	--  the whole view and reads as steering the camera. Sliding it
	--  sideways keeps the view pointing the same way and lets the kart
	--  drift across the frame, which is what being thrown wide looks
	--  like from inside the car.
	--
	--  WHY THIS IS NOT NAUSEATING, WHICH IS THE ONLY REASON IT IS SAFE:
	--  motion sickness lives in FREQUENCY, not amplitude, and it is far
	--  more sensitive to ROTATION than to translation. This is pure
	--  translation, driven by STEERING — which in water takes 0.93s to
	--  reach full lock (SteerRateScale 0.35) and is smoothed again at
	--  SwayRate. It lands near 0.5 Hz against the hop's 2.4, a 4.5x
	--  separation, and it never tilts the horizon at all.
	--
	--  SIGN, DERIVED SO NOBODY HAS TO AGAIN:
	--    `steerTurn = -steer * turn`, so POSITIVE steer turns RIGHT.
	--    The eye is thrown to the OUTSIDE of the turn, so a right turn
	--    slides it LEFT — hence the minus.
	--  Flip it to swing inside the turn instead.
	local swim = sim.swim or 0
	if swim > 0.001 or (self.sway or 0) ~= 0 then
		local steer = math.clamp(sim.steer or 0, -1, 1)
		self.sway = Util.approach(self.sway or 0, -steer * CAM.SwimSwaySlide * swim, CAM.SwimSwayRate, dt)
		if math.abs(self.sway) > 1e-4 then
			-- SIDEWAYS, NOT AROUND. A slide keeps the camera pointing the
			-- same way and just moves it, so the kart drifts across the
			-- frame — which is what "thrown to the outside" looks like.
			-- Orbiting instead would swing the whole view and read as
			-- steering the camera rather than as the camera having mass.
			offset += camLook:Cross(camUp).Unit * self.sway
		end
	end

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
	local ahead = (CAM.LookAhead + (if self.bikeCam then BK.CamLookAhead else 0))
		* (1 - math.min(math.abs(input.lookYaw) / math.pi, 1))
	local aim = sim.pos + camLook * ahead + camUp * CAM.LookHeight

	-- THE WATER HOP — LAG, NOT SHAKE.
	--
	-- The camera takes a FRACTION of the hop and takes it LATE. The kart
	-- is drawn at `pos + swimHop`, this aims at `pos + swimHop * Follow`
	-- smoothed, so the kart genuinely rises in frame by the difference
	-- and the camera hauls itself after it. That difference is the whole
	-- effect: perfectly tracked motion is no motion at all.
	--
	-- Applied to the EYE AND THE AIM TOGETHER, so the view translates
	-- rather than tilts. Moving only the eye would swing the look
	-- direction two to three times a second, which is a nodding camera
	-- and genuinely unpleasant.
	--
	-- `sim.swimHop` is nil on a kart that has never touched water, and
	-- zero the rest of the time — this costs nothing on dry land.
	-- A SPRING, NOT A LERP, and that is the difference between a camera
	-- you notice and one you do not.
	--
	-- A lerp only ever chases: it is always somewhere between where it
	-- was and where the kart is, so it can only ever SUBTRACT from the
	-- motion on screen. Raising its gain to feel it more just cancels
	-- more of the hop — the two are the same dial pulling opposite ways,
	-- which is why the first version could not be felt at any setting.
	--
	-- A spring has its own phase. Under-damped it overshoots, so at the
	-- moment the kart starts falling the camera is still rising: the two
	-- are briefly moving APART, and that is the part the eye reads as
	-- weight. It can be felt without eating the hop, because it is not
	-- merely a delayed copy of it.
	--
	-- Damping is a RATE tied to stiffness, `2*sqrt(k)*zeta`, the same
	-- form the suspension and the heave use.
	local hop = sim.swimHop or 0
	if hop ~= 0 or (self.hopFollow or 0) ~= 0 or (self.hopFollowV or 0) ~= 0 then
		local target = hop * CAM.SwimHopFollow
		self.hopFollowV = (self.hopFollowV or 0)
			+ (-CAM.SwimHopSpring * ((self.hopFollow or 0) - target) - CAM.SwimHopDamp * (self.hopFollowV or 0)) * dt
		self.hopFollow = (self.hopFollow or 0) + self.hopFollowV * dt
		local lift = camUp * self.hopFollow
		eye += lift
		aim += lift
	end

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

	local gliding = if sim.state == "glide" then 1 else 0
	self.glide = Util.approach(self.glide, gliding, CAM.GlideRate, dt)

	--=================================================================
	--  ONE AIR FRAMING, NOT TWO THAT STACK.
	--
	--  Both of these now pull the camera IN, and a trick thrown during
	--  a glide sets both at once. Summing them put the eye 4.6 studs off
	--  the kart — through the MinChase floor, which is applied above and
	--  therefore cannot defend against anything down here — and made the
	--  kart nearly four times its normal size. That is not a close-up,
	--  it is a shot of the seat.
	--
	--  They describe the SAME situation from two directions, so the
	--  stronger one wins outright instead of both being spent. `min`
	--  because an inward pull is negative.
	--=================================================================
	local airPull = math.min(CAM.FlipPull * self.flip, CAM.GlidePull * self.glide)
	local airFov = math.min(CAM.FlipFov * self.flip, CAM.GlideFov * self.glide)
	if self.flip > 0.01 or self.glide > 0.01 then
		camera.FieldOfView += airFov
		eye -= camLook * airPull
	end
	if self.flip > 0.01 then
		self:Impact(CAM.FlipShake * self.flip * dt * 6)
	end
	-- The rise is glide-only and does not compete with anything, so it
	-- stays additive. Height is what shows the ground going past
	-- underneath, which is what sells the SPEED of a glide.
	if self.glide > 0.01 then
		eye += camUp * (CAM.GlideRise * self.glide)
	end

	-- The landing drop. Recovers on its own.
	-- Falls onto the target fast and floats back slowly — a heavy camera
	-- dragged down by the impact. Equal rates would read as a bob.
	local dropRate = if (self.dropTo or 0) > (self.drop or 0) then CAM.LandDropFall else CAM.LandDropRecover
	self.drop = Util.approach(self.drop or 0, self.dropTo or 0, dropRate, dt)
	self.dropTo = math.max((self.dropTo or 0) - CAM.LandDropRecover * dt, 0)

	-- The landing kick, decaying exactly as the drop does. Applied along
	-- the look axis rather than the up axis, so it opens the frame out
	-- instead of lifting it.
	local kickRate = if (self.kickTo or 0) > (self.kick or 0) then CAM.LandKickFall else CAM.LandKickRecover
	self.kick = Util.approach(self.kick or 0, self.kickTo or 0, kickRate, dt)
	self.kickTo = math.max((self.kickTo or 0) - CAM.LandKickRecover * dt, 0)
	if (self.kick or 0) > 0.01 then
		eye -= camLook * self.kick
	end

	--=================================================================
	--  THE FLOOR, AGAIN, AND THIS TIME ACTUALLY LAST.
	--
	--  There is a MinChase clamp further up whose comment claims to be
	--  applied last so nothing downstream can undo it. That was true
	--  when everything below it moved the eye BACKWARD; the flip and
	--  glide framings now pull it in, which makes the earlier clamp a
	--  floor with code underneath it.
	--
	--  Cheap, and it removes a whole class of "the camera ended up
	--  inside the kart" that would otherwise have to be re-derived
	--  every time something new nudges the eye.
	--=================================================================
	local finalSpan = eye - anchor
	if finalSpan.Magnitude < CAM.MinChase then
		local dir = if finalSpan.Magnitude > 1e-3 then finalSpan.Unit else -camLook
		eye = anchor + dir * CAM.MinChase
	end
	if self.drop > 0.001 then
		eye -= camUp * self.drop
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

	--=================================================================
	--  A HINT OF THE LEAN, AND NO MORE.
	--
	--  The bike can be laid over at forty degrees; the camera takes about
	--  four. WATCHING a bike lean is exciting — being ROLLED with it is
	--  nauseating, and the world stops being readable exactly when the
	--  player most needs to read it.
	--
	--  Taken from the body motor's angle rather than from steering, so
	--  the camera answers to what is actually on screen. Smoothed, so a
	--  flick through a chicane does not snap the horizon.
	--=================================================================
	if self.bikeCam then
		-- STRAIGHT OFF THE SIMULATION, which owns the lean.
		--
		-- This used to dig the roll back out of the body motor's
		-- Transform. That worked only while the body motor WAS the lean;
		-- now the whole assembly rolls at the render write and the motor
		-- carries just wobble and shiver, so reading it there would have
		-- given a camera that ignored a 60-degree corner and twitched at
		-- a pothole instead.
		--
		-- It is also three lookups and a matrix decomposition cheaper,
		-- and it cannot be broken by renaming a part.
		local lean = math.deg(sim.lean or 0)
		local want = math.clamp(lean * BK.CamRollShare, -BK.CamRollMax, BK.CamRollMax)
		self.camRoll = Util.approach(self.camRoll or 0, want, BK.CamRollRate, dt)
		if math.abs(self.camRoll) > 0.01 then
			self.up = Util.rotateAbout(self.up, camLook, math.rad(self.camRoll))
		end
	end

	-- lookAt fails if up is parallel to the view direction.
	local viewDir = aim - eye
	if viewDir.Magnitude > 1e-3 and viewDir.Unit:Cross(self.up).Magnitude > 1e-3 then
		camera.CFrame = CFrame.lookAt(eye, aim, self.up)
	end
end

return CameraRig
