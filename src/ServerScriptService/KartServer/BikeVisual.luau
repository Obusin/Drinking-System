--[[
	BikeVisual — a placeholder motorcycle, built in code.

	WHY BUILT RATHER THAN IMPORTED
	------------------------------
	`src/ServerStorage` is not synced (see SPEC-packaging: Studio owns it,
	so Argon cannot delete your art). That is the right call and it means
	there is no way to ship a Model from disk — so the first bike is
	assembled from parts here.

	IT IS MEANT TO BE THROWN AWAY. Drop a Model named `Motorcycle` into
	ServerStorage and `Config.Vehicles.Kinds.bike.visual` finds it instead;
	nothing else changes. This exists so the vehicle can be driven and
	tuned before any art is modelled, which is the order that actually
	works — art built against handling that turned out wrong is art built
	twice.

	THE NAMES ARE THE CONTRACT, NOT THE SHAPE.
	------------------------------------------
	`KartFactory` discovers a rig entirely by name and tag:

	    WheelF / WheelR    already in Rig.FrontWheelNames / RearWheelNames
	    Chassis            already in Rig.BodyRootNames
	    Rim / Tire         already in Rig.RimNames / TireNames

	So this needs no special case anywhere in the factory — it motorises a
	bike with the same code that motorises a kart, and any real model that
	uses these names drops straight in.

	Each wheel is a MODEL containing Rim and Tire, matching the kart's own
	rig, so the garage can swap rims and tyres on a bike with the existing
	dressing code rather than a second path.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config"))

-- The footpegs are placed from the same numbers the knee IK aims at, so
-- the boot lands ON the peg rather than beside it. See Config.Bike.
local BK = Config.Bike
local RIG = Config.Rig

local BikeVisual = {}

local function part(name: string, size: Vector3, cf: CFrame, colour: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- The factory forces all of this again on its final sweep. Set here
	-- too so the model is already sane if anything looks at it first.
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Parent = parent
	return p
end

-- A wheel is a MODEL with a Rim and a Tire inside, exactly as the kart's
-- wheels are. The Model's PIVOT is the axle — `KartFactory` motorises
-- about `Model:GetPivot()`, so a wheel whose pivot is anywhere else
-- orbits that point instead of spinning on its axle.
local function wheel(name: string, at: CFrame, radius: number, width: number, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent

	local tire = part(
		"Tire",
		Vector3.new(width, radius * 2, radius * 2),
		at,
		Color3.fromRGB(28, 28, 32),
		m
	)
	tire.Shape = Enum.PartType.Cylinder
	tire.Material = Enum.Material.Pebble

	local rim = part(
		"Rim",
		Vector3.new(width * 1.05, radius * 1.05, radius * 1.05),
		at,
		Color3.fromRGB(190, 195, 205),
		m
	)
	rim.Shape = Enum.PartType.Cylinder
	rim.Material = Enum.Material.Metal

	--==============================================================
	--  SPOKES, AND THEY ARE NOT DECORATION.
	--
	--  The wheels were always spinning — `s.roll` accumulates and is
	--  applied every frame. But a plain black cylinder is rotationally
	--  symmetric, so a spinning one and a stationary one are the SAME
	--  IMAGE. "The wheels do not spin" was really "the wheels have
	--  nothing on them to see spinning".
	--
	--  Anything that breaks the symmetry fixes it. Four spokes is the
	--  cheapest thing that reads at speed, and it reads better than a
	--  texture would because it also catches the light.
	--
	--  They live inside the wheel Model, so the factory welds them to
	--  the hub and they turn with it — no extra joints.
	--==============================================================
	for i = 0, 3 do
		local a = (i / 4) * math.pi * 2
		local spoke = part(
			"Spoke",
			Vector3.new(width * 1.15, radius * 1.5, radius * 0.16),
			at * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, a),
			Color3.fromRGB(225, 228, 235),
			m
		)
		spoke.Material = Enum.Material.Metal
	end

	-- The tyre is the bigger part, so `hubOf` picks it as the hub anyway.
	-- Said explicitly rather than relied upon: "largest part wins" is a
	-- sensible default and a poor contract.
	m.PrimaryPart = tire
	m:PivotTo(at)
	return m
end

--=====================================================================
--  BUILD
--
--  Laid out around the origin with +Z BACKWARD, matching the kart: the
--  factory reads the hitbox's own axes, so a model built the other way
--  round drives in reverse with everything else looking correct.
--=====================================================================
function BikeVisual.build(): Model
	local bike = Instance.new("Model")
	bike.Name = "Visual"

	local body = Color3.fromRGB(196, 60, 72)
	local dark = Color3.fromRGB(40, 42, 48)
	local chrome = Color3.fromRGB(200, 205, 215)

	-- THE BODY ROOT. Named `Chassis` because that is already first in
	-- Rig.BodyRootNames — everything that is not a wheel welds to this,
	-- and this is what leans.
	local chassis = part("Chassis", Vector3.new(1.1, 1.0, 3.6), CFrame.new(0, 0.15, 0), body, bike)
	bike.PrimaryPart = chassis

	-- Tank and seat: the silhouette that says "motorcycle" from behind,
	-- which is the only angle most players ever see.
	part("Tank", Vector3.new(1.5, 1.0, 1.6), CFrame.new(0, 0.85, -0.5), body, bike)
	part("SeatPad", Vector3.new(1.2, 0.45, 1.6), CFrame.new(0, 0.85, 0.9), dark, bike)
	part("TailFairing", Vector3.new(1.0, 0.7, 1.0), CFrame.new(0, 1.05, 1.75), body, bike)

	--==============================================================
	--  A TELESCOPIC FORK IS TWO PARTS, AND THAT IS WHY IT IS TWO
	--  PARTS HERE.
	--
	--  `ForkDive` has been computed in BikeVisuals since the bike was
	--  built and applied by nobody, because a single welded tube has
	--  nothing to dive WITH — a fork does not move, it SHORTENS, and
	--  you cannot shorten one part without resizing it every frame.
	--
	--  Upper stanchion welds to the chassis. Lower slider gets a motor
	--  and telescopes up into it under braking and on landings. The
	--  overlap at rest is what hides the join at full extension.
	--
	--  The rake is on both, so the slide runs along the fork's own
	--  axis rather than straight down — a fork that dives vertically
	--  on a raked front end reads as the wheel being pushed backward.
	--==============================================================
	local RAKE = CFrame.Angles(math.rad(-18), 0, 0)
	part("ForkUpper", Vector3.new(0.44, 1.3, 0.44), CFrame.new(0, 1.05, -1.7) * RAKE, dark, bike)
	part("Fork", Vector3.new(0.4, 1.7, 0.4), CFrame.new(0, 0.45, -1.9) * RAKE, chrome, bike)

	-- Bars.
	-- WITHIN ARM'S REACH OF THE SEAT, which the factory fixes at
	-- (0, 0.5, 0.6). An R15 arm is about two studs; bars placed for
	-- looks rather than for reach leave the IK stretched to its limit,
	-- and a maxed-out IKControl simply stops tracking — which reads as
	-- "the IK is not working" rather than "the bars are too far away".
	local bars = part("Handlebar", Vector3.new(2.0, 0.22, 0.22), CFrame.new(0, 1.35, -1.05), dark, bike)

	-- THE HANDS AIM AT THESE. Named exactly as the steering wheel's,
	-- because `Rider` looks for GripL/GripR and does not care what they
	-- are attached to — so a bike gets working arm IK with no second
	-- code path, just the same two names in the right places.
	--
	-- Without them the rider's arms simply hang: the IK bails out with
	-- "no GripL/GripR" and nothing else looks wrong, which is a silent
	-- failure worth knowing the shape of.
	for name, x in { GripL = -0.85, GripR = 0.85 } do
		local att = Instance.new("Attachment")
		att.Name = name
		att.Position = Vector3.new(x, 0, 0)
		att.Parent = bars
	end
	part("Headlight", Vector3.new(0.8, 0.8, 0.35), CFrame.new(0, 1.15, -2.05), Color3.fromRGB(250, 245, 220), bike).Material =
		Enum.Material.Neon

	--==============================================================
	--  FOOTPEGS — THE THING THE RIDER ACTUALLY STANDS ON.
	--
	--  The knee-out pose pins the boot to a fixed point and swings the
	--  knee out from it, which is what makes the leg read as bearing
	--  weight. Until now that point was in mid-air: the rider was
	--  standing on nothing, and it showed.
	--
	--  BUILT FROM Config.Bike's OWN PEG NUMBERS, converted out of the
	--  seat's frame into the model's. Hard-coding a position here
	--  instead would be a second copy of it, and the day one moved the
	--  boot would float beside the peg rather than on it.
	--
	--  Cylinders, laid along X like the wheels — a peg is a short bar
	--  sticking out sideways, and a Roblox cylinder's length already
	--  runs along its own X.
	--==============================================================
	local pegY = RIG.SeatOffset.Y - BK.FootPegDrop
	local pegZ = RIG.SeatOffset.Z - BK.FootPegForward
	for name, side in { FootPegL = -1, FootPegR = 1 } do
		local peg = part(
			name,
			Vector3.new(0.62, 0.16, 0.16),
			CFrame.new(side * BK.FootPegOut, pegY, pegZ),
			chrome,
			bike
		)
		peg.Shape = Enum.PartType.Cylinder
		peg.Material = Enum.Material.Metal
	end

	-- Engine block and pipe. `Exhaust` is the other cosmetic slot.
	part("Engine", Vector3.new(1.3, 0.9, 1.2), CFrame.new(0, 0.05, 0.1), dark, bike)
	part("Exhaust", Vector3.new(0.35, 0.35, 2.2), CFrame.new(0.55, -0.05, 1.1), chrome, bike)

	-- WHEELS. NO ROTATION.
	--
	-- A Roblox cylinder's length already runs along its X, and X is the
	-- kart's lateral axis — which is exactly where a wheel's axle goes.
	-- The default orientation is the correct one.
	--
	-- Rotating it 90 degrees "so the flat faces point sideways" is the
	-- obvious-sounding fix and it lays the wheel FLAT, like a turntable
	-- under the bike. That is what the hovering discs were.
	--
	-- Y places the axle so the tyre touches the road: centre = radius -
	-- RideHeight. Get this wrong and the bike either hovers or sinks,
	-- because the hitbox height is fixed and the art has to meet it.
	wheel("WheelF", CFrame.new(0, 1.05 - 1.4, -2.05), 1.05, 0.45, bike)
	wheel("WheelR", CFrame.new(0, 1.15 - 1.4, 1.75), 1.15, 0.6, bike)

	--==============================================================
	--  TYRE SMOKE, AT THE REAR CONTACT PATCH.
	--
	--  ON THE CHASSIS, NOT ON THE WHEEL, for two separate reasons and
	--  either one on its own would be enough:
	--
	--    A wheel SPINS. An emitter parented to one has its emission
	--    directions dragged round with it, so the smoke sprays in a
	--    rotating fan instead of trailing behind.
	--
	--    The chassis rotates ABOUT this point when the bike leans —
	--    see Bike.LeanPivot — so an attachment placed here is the one
	--    spot on the bodywork that stays put through a 60-degree lean.
	--    That is exactly the behaviour a contact patch should have,
	--    and it comes for free rather than needing to be tracked.
	--
	--  Position is in the CHASSIS's frame, which sits at y = 0.15, so
	--  the contact patch at y = -1.4 is -1.55 from here.
	--
	--  The stock Roblox smoke texture, deliberately: this is a
	--  placeholder and it should look like one.
	--==============================================================
	local smokeAt = Instance.new("Attachment")
	smokeAt.Name = "TyreSmokeAt"
	smokeAt.Position = Vector3.new(0, -1.55, 1.75)
	smokeAt.Parent = chassis

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "TyreSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 0
	smoke.Enabled = false
	smoke.Lifetime = NumberRange.new(0.55, 0.85)
	smoke.Speed = NumberRange.new(6, 11)
	-- Backward and slightly up, in the attachment's own frame — the
	-- direction rubber actually leaves a spinning tyre.
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 2.6),
	})
	-- Fades IN fast and OUT slow. Smoke that appears at full opacity
	-- reads as a puff of steam rather than as a tyre building it up.
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(190, 190, 195))
	smoke.LightEmission = 0
	smoke.Acceleration = Vector3.new(0, 6, 0)
	-- The smoke must NOT inherit the bike's velocity, or a 90 studs/s
	-- powerslide drags the whole cloud along with the bike and it looks
	-- painted on. It should be left behind.
	smoke.VelocityInheritance = 0.15
	smoke.Parent = smokeAt

	-- Everything unanchored for the factory, which expects to weld and
	-- motorise a loose model.
	for _, d in bike:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end

	return bike
end

-- Named builders, so `Config.Vehicles` can ask for one by string without
-- this module having to know what a vehicle is.
BikeVisual.builders = {
	bike = BikeVisual.build,
}

return BikeVisual
