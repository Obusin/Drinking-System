--[[
	KartFactory — assembles a kart model.

	THE CONSISTENCY RULE
	--------------------
	A kart is a fixed invisible Hitbox with a purely cosmetic Visual
	model welded to it. The client controller reads ONLY the Hitbox and
	the Seat — never wheel size, mass, or part positions. Swap the visual
	for a bus, a trolley or a banana and the handling is identical.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.BloxKart.Config)
local Util = require(ReplicatedStorage.BloxKart.Util)
local Names = require(ReplicatedStorage.BloxKart.Names)
local PlaceholderVisual = require(script.Parent.PlaceholderVisual)
local BikeVisual = require(script.Parent.BikeVisual)
local SteeringWheel = require(script.Parent.SteeringWheel)

local RIG = Config.Rig
local log = Util.logger("KartFactory", RIG.Debug)

local KartFactory = {}

KartFactory.TAG = "Kart"

-- Which parts take the racer's colour. Tagged parts win; otherwise
-- match by name. Anything unlisted keeps its authored colour, so trim
-- and tyres don't turn pink.
local function isPaintable(part: BasePart): boolean
	if CollectionService:HasTag(part, RIG.PaintTag) then
		return true
	end
	return table.find(RIG.PaintParts, part.Name) ~= nil
end

-- `slot` is the grid position; colour follows from it, wrapping if more
-- players turn up than there are colours.
-- Rotated once per round, so slot 0 is not red for the rest of time.
--
-- An OFFSET rather than a shuffle, deliberately: adding a constant to
-- every slot is still a one-to-one mapping, so no two racers can land
-- on the same colour. A shuffle would give variety and could collide;
-- this gives variety and cannot.
KartFactory.paintOffset = 0

function KartFactory.colorFor(slot: number): Color3
	local palette = RIG.Colors
	return palette[((slot + KartFactory.paintOffset) % #palette) + 1]
end

-- `visualName` overrides which ServerStorage model is used as the art.
-- Nil means RIG.VisualName, which is what everyone gets.
--=====================================================================
--  `kind` NAMES A ROW IN Config.Vehicles. Nil is the kart, which is the
--  existing behaviour spelled out — every current caller keeps working
--  without knowing vehicles exist.
--=====================================================================
function KartFactory.build(color: Color3?, visualName: string?, kind: string?): Model
	local kart = Instance.new("Model")
	kart.Name = "Kart"

	-- The one part that matters. Non-colliding: the controller does its
	-- own swept collision, so Roblox's solver never gets a vote. That is
	-- what makes handling identical on every machine and frame rate.
	local vehicle = Config.Vehicles.Kinds[kind or Config.Vehicles.Default] or Config.Vehicles.Kinds.kart

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	-- THE ONE VISUAL-SOUNDING NUMBER THAT IS NOT COSMETIC. A bike is
	-- narrower and the controller collides with THIS, not with the art —
	-- so it is the vehicle's to set and nothing else's.
	hitbox.Size = vehicle.hitboxSize or RIG.HitboxSize
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Anchored = true -- unanchored only while someone is driving
	hitbox.CFrame = CFrame.new()
	hitbox.Parent = kart
	kart.PrimaryPart = hitbox

	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = CFrame.new(RIG.SeatOffset)
	seat.Transparency = 1
	seat.CanCollide = false
	-- Another racer's seat must not register as a wall in our sweep.
	seat.CanQuery = false
	-- The seat is an input device, nothing more. Its built-in driving
	-- would fight the controller.
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	-- Roblox draws its own speedometer for a VehicleSeat. It reports the
	-- seat's built-in driving, which we've zeroed above, so it would sit
	-- there reading nothing next to our real one.
	seat.HeadsUpDisplay = false
	seat.Parent = kart

	-- The seat needs its own visual joint rather than a WeldConstraint.
	--
	-- A WeldConstraint would keep the driver fixed to the invisible
	-- hitbox while BodyMotor rolls the bodywork, which makes a motorcycle
	-- bank underneath an upright rider.  Rider mirrors BodyMotor's
	-- cosmetic pose onto this joint, so the seat, occupant and chassis
	-- read as one motorcycle while the hitbox (and its handling) remains
	-- completely level.
	local seatMotor = Instance.new("Motor6D")
	seatMotor.Name = "SeatMotor"
	seatMotor.Part0, seatMotor.Part1 = hitbox, seat
	seatMotor.C0, seatMotor.C1 = Util.pivotJoint(hitbox, seat)
	seatMotor.Parent = seat

	-- Visual: yours if you supplied one, otherwise the placeholder.
	local wanted = visualName or RIG.VisualName
	-- RECURSIVE, because art gets filed. The rocket was found only after
	-- this same lookup was widened; a kart tidied into a folder would
	-- otherwise fall silently back to the placeholder.
	-- A VEHICLE MAY NAME ITS OWN ART, and fall back to a code-built
	-- placeholder when that art does not exist yet. That ordering is
	-- deliberate: drop a real Model in with the right name and it wins,
	-- with no code change and no flag to remember to flip.
	if vehicle.visual then
		wanted = vehicle.visual
	end
	local template = if wanted ~= "" then ServerStorage:FindFirstChild(wanted, true) else nil
	local visual: Model
	if not template and vehicle.build then
		local builder = BikeVisual.builders[vehicle.build]
		if builder then
			visual = builder()
			visual.Name = "Visual"
			log("no %s model in ServerStorage — built the %s placeholder", tostring(wanted), vehicle.build)
		end
	end
	if visual then
		-- already built
	elseif template and template:IsA("Model") then
		visual = template:Clone()
		visual.Name = "Visual"
		log("using %s as the kart visual", template:GetFullName())
	else
		-- WARNS EVEN FOR THE DEFAULT, which it used to skip.
		--
		-- The old guard was `if visualName then`, so a missing model was
		-- only reported when someone had asked for a SPECIFIC one. The
		-- configured default going missing — which is everyone, every
		-- kart — fell back to the placeholder in silence. "Why is
		-- everybody in the old kart" had no answer anywhere in Output.
		if wanted ~= "" then
			warn(
				("[KartFactory] no Model named %q anywhere in ServerStorage — every kart falls back to the placeholder. Check Rig.VisualName matches the model's name exactly."):format(
					wanted
				)
			)
		end
		visual = PlaceholderVisual.build()
	end

	visual.Parent = kart
	--=================================================================
	--  SIT THE ART ON ITS WHEELS.
	--
	--  PivotTo puts the model's PIVOT at the hitbox origin, and a model's
	--  pivot is wherever the person who built it happened to leave it —
	--  usually the centre of the bounding box, sometimes the origin of
	--  whatever part was made first. It is not the wheel line, and there
	--  is no reason it would be.
	--
	--  So the kart floated or sank by however far those two differ, which
	--  is a property of the ART and therefore changes every time anybody
	--  edits the model. Hand-tuning VisualOffset per kart is the kind of
	--  fix that has to be redone silently forever.
	--
	--  Measured instead. The hitbox origin rides RideHeight above the
	--  road, so the art's LOWEST point belongs exactly that far below the
	--  origin — that is what "on its wheels" means, for any model.
	--
	--  VisualOffset survives as a deliberate trim on top, for art that
	--  wants to sit proud or tucked for a reason.
	--=================================================================
	local drop = RIG.VisualOffset
	if RIG.VisualAutoSit then
		--=============================================================
		--  MEASURE THE WHEELS, NOT THE BOUNDING BOX.
		--
		--  The first version took the lowest point of the whole model,
		--  which sounds like the wheel line and is not. A kart's art
		--  contains the SHIELD BUBBLE — a sphere wrapping the entire kart
		--  — so the lowest point of the model is the bottom of the
		--  bubble, well under the tyres. Sitting that on the road lifted
		--  the kart until it hung at head height with the driver seated
		--  underneath it.
		--
		--  Wheels are the parts that actually touch the ground, which
		--  makes them the only honest answer to "where is the bottom of
		--  this kart". They are already identifiable — the same tags and
		--  names the Motor6D pass uses further down.
		--=============================================================
		local lowest: number? = nil
		local function consider(part: BasePart)
			local bottom = part.Position.Y - part.Size.Y * 0.5
			if not lowest or bottom < lowest then
				lowest = bottom
			end
		end

		-- A WHEEL MAY BE A MODEL, so this asks about the part OR any Model
		-- above it. Without that the new rig had nothing it recognised
		-- touching the ground and fell through to the body fallback, which
		-- puts the kart at the wrong ride height — subtly, and everywhere.
		local function isWheelish(inst: Instance): boolean
			return CollectionService:HasTag(inst, RIG.WheelFrontTag)
				or CollectionService:HasTag(inst, RIG.WheelRearTag)
				or table.find(RIG.FrontWheelNames, inst.Name) ~= nil
				or table.find(RIG.RearWheelNames, inst.Name) ~= nil
		end

		for _, d in visual:GetDescendants() do
			if not d:IsA("BasePart") then
				continue
			end
			local wheelish = isWheelish(d)
			if not wheelish then
				local up = d:FindFirstAncestorWhichIsA("Model")
				while up and up ~= visual do
					if isWheelish(up) then
						wheelish = true
						break
					end
					up = up:FindFirstAncestorWhichIsA("Model")
				end
			end
			if wheelish then
				consider(d)
			end
		end

		-- No wheels named or tagged. Fall back to the body, still skipping
		-- anything decorative that wraps the kart — the bubble is the one
		-- that matters and the reason this needs a filter at all.
		if not lowest then
			local shield = visual:FindFirstChild(Config.Effects.ShieldName, true)
			for _, d in visual:GetDescendants() do
				if d:IsA("BasePart") and not (shield and d:IsDescendantOf(shield)) and d ~= shield then
					consider(d)
				end
			end
		end

		if lowest then
			drop += Vector3.new(0, -Config.Handling.RideHeight - (lowest - visual:GetPivot().Position.Y), 0)
			log("art dropped %.2f studs to put its wheels on the road", drop.Y)
		end
	end
	visual:PivotTo(CFrame.new(drop))

	-- STRIPPED AFTER PivotTo, and the order is load-bearing.
	--
	-- A supplied visual is DECORATION. Artists naturally model a whole
	-- kart, seat and all, and welding that on would leave a second
	-- VehicleSeat a player could sit in — outside the lock-in logic
	-- entirely — plus a second part called Hitbox for anything that looks
	-- one up by name to trip over.
	--
	-- But a Model's pivot comes from its PrimaryPart, and an authored kart
	-- usually names that part Hitbox. Destroy it first and PrimaryPart
	-- goes nil, so PivotTo falls back to the bounding-box centre — a
	-- different origin, which lands the art somewhere else entirely. It
	-- looks exactly like the custom kart failing to load.
	--
	-- Done in code rather than documented because "delete these two before
	-- exporting" is a rule someone forgets exactly once and then spends an
	-- afternoon on.
	for _, desc in visual:GetDescendants() do
		if desc:IsA("VehicleSeat") or desc:IsA("Seat") or desc.Name == "Hitbox" then
			log("stripping %s from the supplied visual — the factory owns that", desc.Name)
			desc:Destroy()
		end
	end

	-- And it must not be TAGGED as a kart. Clones carry tags, and art
	-- copied out of a live kart brings the Kart tag with it — so every
	-- Visual would answer GetTagged("Kart") and be counted as a racer.
	--
	-- That's worse than it sounds. Standings ranks it, so places are
	-- wrong; and a missile handed one as a target finds no hitbox on it,
	-- so it flies the whole route with nobody to home on and expires.
	for _, inst in { visual, table.unpack(visual:GetDescendants()) } do
		if CollectionService:HasTag(inst, KartFactory.TAG) then
			log("un-tagging %s — art must never register as a kart", inst.Name)
			CollectionService:RemoveTag(inst, KartFactory.TAG)
		end
	end

	-- If the supplied art already has a steering wheel, that becomes the
	-- hub and we skip building one. Its subtree must NOT be welded to
	-- the hitbox or the Motor6D couldn't turn it.
	local supplied = visual:FindFirstChild("SteeringWheel", true)
	local suppliedWheel = if supplied and supplied:IsA("BasePart") then supplied else nil

	-- Which way a wheel rolls: down its axle, which for a ROAD wheel is
	-- always the kart's lateral axis. Wheels roll forwards, so the axle
	-- points sideways — that is true of every wheel on every vehicle, and
	-- it doesn't care how the mesh was modelled.
	--
	-- This replaced measuring the mesh's thinnest dimension, which broke
	-- on a single mesh containing BOTH front wheels: that bounding box is
	-- wide across the kart rather than disc-shaped, so the "axle" came out
	-- vertical. Roll and steer then shared one axis and the steering was
	-- invisible inside the spin.
	--
	-- Config can still force it in the mesh's own frame if a wheel really
	-- is mounted oddly.
	local function axleOf(motor: Motor6D): Vector3
		if typeof(RIG.RoadWheelAxis) == "Vector3" then
			return motor.C1.Rotation:VectorToObjectSpace(RIG.RoadWheelAxis)
		end
		return motor.C0.Rotation:VectorToObjectSpace(Vector3.xAxis)
	end

	-- Road wheels: tagged, or named from the config lists. A wheel gets a
	-- Motor6D rather than a weld so Rider can turn it; a welded wheel is
	-- frozen to the body forever.
	--
	-- TAKES AN INSTANCE, NOT A BASEPART, because a wheel is now allowed to
	-- be a MODEL. The rig that made this necessary has FrontLeftWheel as a
	-- Model holding a Rim and a Tire, so rims and tyres can be equipped
	-- separately — and the old version, which only ever looked at
	-- BaseParts, skipped the Model entirely and then welded its Rim and
	-- Tire to the hitbox as though they were scenery. Every wheel on the
	-- new kart was bolted rigidly to the chassis: no spin, no steering,
	-- and nothing anywhere said so.
	local function wheelKind(inst: Instance): boolean?
		if CollectionService:HasTag(inst, RIG.WheelFrontTag) then
			return true
		end
		if CollectionService:HasTag(inst, RIG.WheelRearTag) then
			return false
		end
		if table.find(RIG.FrontWheelNames, inst.Name) then
			return true
		end
		if table.find(RIG.RearWheelNames, inst.Name) then
			return false
		end
		return nil
	end

	-- GLIDER PARTS. Same problem as a wheel: a welded part cannot move, so
	-- anything that has to animate needs a Motor6D instead of a weld.
	--
	-- Returns the joint name, or nil for "this is ordinary bodywork".
	local function isShield(inst: Instance): boolean
		local shield = visual:FindFirstChild(Config.Effects.ShieldName, true)
		return shield ~= nil and (inst == shield or inst:IsDescendantOf(shield))
	end

	local function gliderKind(inst: Instance): string?
		if CollectionService:HasTag(inst, RIG.AeroTag) or inst.Name == RIG.AeroName then
			return "AeroMotor"
		end
		if CollectionService:HasTag(inst, RIG.WingTag) or table.find(RIG.WingNames, inst.Name) then
			return "WingMotor"
		end
		return nil
	end

	-- The part a wheel Model actually turns on.
	--
	-- PrimaryPart if the artist set one, otherwise the biggest part —
	-- which on a Rim/Tire pair is the tyre, and is the right answer for
	-- the same reason it is the obvious one. Never "the first child":
	-- that is decided by Explorer order, which nobody thinks of as load
	-- bearing right up until they reorder it.
	local function hubOf(model: Model): BasePart?
		if model.PrimaryPart then
			return model.PrimaryPart
		end
		local best, bestVolume = nil, -1
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bestVolume then
					best, bestVolume = d, v
				end
			end
		end
		return best
	end

	-- THE BODY ROOT. Everything that is not a wheel, not the glider and
	-- not the shield hangs off THIS, and this hangs off the hitbox on a
	-- Motor6D — so the bodywork can lean while the wheels stay put.
	--
	-- Named first, largest-non-wheel second. Never "the first child":
	-- Explorer order is not a design decision, and treating it as one is
	-- how a rig silently changes behaviour when somebody tidies it.
	local bodyRoot: BasePart? = nil
	for _, d in visual:GetDescendants() do
		if d:IsA("BasePart") and (CollectionService:HasTag(d, RIG.BodyRootTag) or table.find(RIG.BodyRootNames, d.Name)) then
			bodyRoot = d
			break
		end
	end

	-- Wheel Models, resolved once so the loop below can ask "is this part
	-- inside a wheel, and is it the hub of it".
	local wheelModels: { [Model]: { hub: BasePart, front: boolean } } = {}
	-- The reverse index: hub part -> the Model it is the hub of. Needed
	-- because the motor is built on the PART but has to be pivoted about
	-- the MODEL.
	local wheelOf: { [BasePart]: Model } = {}
	for _, d in visual:GetDescendants() do
		if d:IsA("Model") then
			local front = wheelKind(d)
			local hub = if front ~= nil then hubOf(d) else nil
			if front ~= nil and hub then
				wheelModels[d] = { hub = hub, front = front }
				wheelOf[hub] = d
			elseif front ~= nil then
				warn(("[KartFactory] %s is a wheel but has no parts in it."):format(d:GetFullName()))
			end
		end
	end

	-- FALLBACK: THE LARGEST NON-WHEEL PART.
	--
	-- There must always be a body root, because everything hanging off it
	-- is the everything that can be ANIMATED — a kart without one welds
	-- its bodywork straight to the hitbox, where it can neither lean nor
	-- flip. "No body root" used to mean "this kart silently does not do
	-- half the visuals", which is not a state worth supporting.
	--
	-- Largest by volume, so it is the shell rather than a mirror or a
	-- badge. Wheels excluded or a big tyre could win and the kart would
	-- lean about its own wheel.
	if not bodyRoot then
		local bestVolume = -1
		for _, d in visual:GetDescendants() do
			if d:IsA("BasePart") and not isShield(d) then
				local inWheel = false
				local up = d:FindFirstAncestorWhichIsA("Model")
				while up and up ~= visual do
					if wheelModels[up] then
						inWheel = true
						break
					end
					up = up:FindFirstAncestorWhichIsA("Model")
				end
				if not inWheel and wheelKind(d) == nil then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if v > bestVolume then
						bodyRoot, bestVolume = d, v
					end
				end
			end
		end
		if bodyRoot then
			log("no named body root — using %s, the largest non-wheel part", bodyRoot.Name)
		end
	end


	--=================================================================
	--  PARTS THAT GET THEIR OWN MOTOR LATER MUST NOT BE WELDED NOW.
	--
	--  The weld pass below attaches every non-wheel part to the body
	--  root, and the handlebars and fork are motorised further down. A
	--  part carrying BOTH a WeldConstraint and a Motor6D is a cycle in
	--  the assembly graph, and Roblox resolves those by dropping one of
	--  the joints — WHICH one is not something to build a feature on.
	--
	--  The bars have been in exactly this state since they were
	--  motorised. They happen to work, which is worse than not working:
	--  it is the same construction either way, and the next part to hit
	--  it may lose the coin toss instead.
	--
	--  Matched by name, so art that simply has no fork skips it here as
	--  well as at the motor.
	--=================================================================
	local motorisedLater: { [Instance]: true } = {}
	if vehicle.steeringWheel == false then
		for _, name in { RIG.HandlebarName, RIG.ForkName } do
			local p = kart:FindFirstChild(name, true)
			if p and p:IsA("BasePart") then
				motorisedLater[p] = true
			end
		end
	end

	for _, desc in visual:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			-- CanQuery off matters in multiplayer: another racer's kart
			-- must not register as a wall in our swept collision.
			desc.CanQuery = false
			desc.Massless = true

			if color and isPaintable(desc) then
				desc.Color = color
			end

			-- IS THIS PART A WHEEL, OR INSIDE ONE?
			--
			-- A bare part named WheelFL is a wheel in its own right. The
			-- Tire inside FrontLeftWheel is not a wheel — it is cargo, and
			-- it has to weld to the HUB rather than to the hitbox or it
			-- will not turn with it.
			local isFront = wheelKind(desc)
			local owner: Model? = nil
			if isFront == nil then
				local model = desc:FindFirstAncestorWhichIsA("Model")
				while model do
					if wheelModels[model] then
						owner = model
						break
					end
					model = model:FindFirstAncestorWhichIsA("Model")
				end
				if owner and wheelModels[owner].hub == desc then
					-- The hub of a wheel Model IS the wheel, as far as the
					-- motor is concerned.
					isFront = wheelModels[owner].front
					owner = nil
				end
			end

			if isFront ~= nil then
				-- Motor6D, not a weld: a weld can't be rotated at runtime.
				local motor = Instance.new("Motor6D")
				motor.Name = "RoadWheelMotor"
				motor.Part0, motor.Part1 = hitbox, desc
				-- About the wheel's own pivot. Anchored to its CFrame origin
				-- instead, an imported wheel orbits that point rather than
				-- spinning on its axle.
				--
				-- For a wheel MODEL the pivot that matters is the model's,
				-- not the hub part's: a tyre's centre is the axle, but only
				-- by luck, and a rim modelled off-centre would make the
				-- whole wheel orbit rather than spin.
				local ownerModel = wheelOf[desc]
				if ownerModel then
					local pivot = ownerModel:GetPivot()
					motor.C0 = hitbox.CFrame:ToObjectSpace(pivot)
					motor.C1 = desc.CFrame:ToObjectSpace(pivot)
				else
					motor.C0, motor.C1 = Util.pivotJoint(hitbox, desc)
				end
				motor:SetAttribute(Names.WHEEL_FRONT, isFront)

				-- Both axes come from the KART and are converted into the
				-- joint's frame, so they're right whatever orientation the
				-- mesh was modelled in AND always perpendicular to each other
				-- — which is what makes steering visible rather than lost
				-- inside the roll.
				--
				--   roll  = kart's lateral axis (the axle)
				--   steer = kart's up
				motor:SetAttribute(Names.ROLL_AXIS, axleOf(motor))
				motor:SetAttribute(Names.STEER_AXIS, motor.C0.Rotation:VectorToObjectSpace(Vector3.yAxis))
				motor.Parent = desc
				log("%s -> %s road wheel", desc.Name, if isFront then "front" else "rear")
			elseif gliderKind(desc) then
				-- HINGED ABOUT ITS OWN PIVOT, which is why the setup note
				-- says to put the pivot on the hinge line. Anchored to the
				-- part's centre instead, a flap scissors through the wing
				-- rather than swinging off it.
				local joint = gliderKind(desc) :: string
				local motor = Instance.new("Motor6D")
				motor.Name = joint
				motor.Part0, motor.Part1 = hitbox, desc
				motor.C0, motor.C1 = Util.pivotJoint(hitbox, desc)

				-- The hinge is the KART's lateral axis, converted into the
				-- joint's frame — the same reasoning as the wheel axle. A
				-- flap pitches up and down, and that is true however the
				-- mesh happened to be modelled, so it must not depend on
				-- the art's orientation.
				motor:SetAttribute(Names.ROLL_AXIS, motor.C0.Rotation:VectorToObjectSpace(Vector3.xAxis))
				motor.Parent = desc
				log("%s -> %s", desc.Name, joint)
			elseif desc ~= suppliedWheel and not motorisedLater[desc] then
				-- WELDED TO THE HUB IF IT BELONGS TO A WHEEL.
				--
				-- The old comment above claimed this already happened. It
				-- did not — everything that was not itself a wheel welded to
				-- the hitbox. It never showed because a wheel used to be one
				-- bare part with nothing inside it, so there was never a
				-- child to get this wrong for.
				local anchorTo: BasePart
				if owner then
					anchorTo = wheelModels[owner].hub
				elseif suppliedWheel and desc:IsDescendantOf(suppliedWheel) then
					anchorTo = suppliedWheel
				elseif bodyRoot and desc ~= bodyRoot and not isShield(desc) then
					-- BODYWORK RIDES THE BODY ROOT, so it leans with it.
					--
					-- The shield is excluded deliberately: it is a bubble
					-- around the WHOLE kart, and a bubble that tilts with
					-- the bodywork reads as the shield being broken rather
					-- than as the kart leaning.
					anchorTo = bodyRoot
				else
					anchorTo = hitbox
				end
				if anchorTo ~= desc then
					local weld = Instance.new("WeldConstraint")
					weld.Part0, weld.Part1 = anchorTo, desc
					weld.Parent = anchorTo
				end
			end
		end
	end

	-- The joint the bodywork leans on. Built AFTER the weld pass, so
	-- everything that had to attach to the root is already attached.
	if bodyRoot then
		local motor = Instance.new("Motor6D")
		motor.Name = "BodyMotor"
		motor.Part0, motor.Part1 = hitbox, bodyRoot
		motor.C0, motor.C1 = Util.pivotJoint(hitbox, bodyRoot)
		motor.Parent = bodyRoot
		log("%s -> body root", bodyRoot.Name)
	else
		warn("[KartFactory] no body root found — the kart will not lean. Name a part "
			.. table.concat(RIG.BodyRootNames, "/")
			.. " or tag one "
			.. RIG.BodyRootTag)
	end

	if suppliedWheel then
		SteeringWheel.motorise(hitbox, suppliedWheel)
		log("using the SteeringWheel from the supplied visual")
	elseif vehicle.steeringWheel == false then
		-- HANDLEBARS TURN, they do not just sit there.
		--
		-- Without a joint the bars weld to the bodywork, so steering
		-- moves nothing and — because the hand grips live ON the bars —
		-- the rider's arms stay locked forward however hard you turn.
		-- The same motor the steering wheel gets, on a different part.
		local bars = kart:FindFirstChild(RIG.HandlebarName, true)
		if bars and bars:IsA("BasePart") then
			-- Unlike a kart steering wheel, the bars are part of the bike
			-- assembly: their steering joint hangs from the chassis so the
			-- entire front end banks with the shell.
			SteeringWheel.motorise(bodyRoot or hitbox, bars)
			log("%s -> handlebars", bars.Name)
		end

		-- THE FORK SLIDES. Same reasoning as the bars: without a joint it
		-- welds solid to the bodywork and `Bike.ForkDive` — which
		-- BikeVisuals has been computing all along — has nothing to move.
		--
		-- Its own motor rather than the wheel's, because the fork
		-- TRANSLATES along its rake while the front wheel keeps spinning
		-- and steering underneath. One joint cannot do both without the
		-- dive being carried round by the spin.
		--
		-- Optional. Art with no `Fork` part loses the dive and keeps
		-- everything else, so this is never a reason a bike fails to build.
		local fork = kart:FindFirstChild(RIG.ForkName, true)
		if fork and fork:IsA("BasePart") then
			local fm = Instance.new("Motor6D")
			fm.Name = "ForkMotor"
			-- The fork dives relative to the chassis, not the level hitbox,
			-- so it follows the same bank as the bars and bodywork.
			local anchor = bodyRoot or hitbox
			fm.Part0, fm.Part1 = anchor, fork
			fm.C0, fm.C1 = Util.pivotJoint(anchor, fork)
			fm.Parent = fork
			log("%s -> fork slider", fork.Name)
		end
	else
		-- A BIKE HAS HANDLEBARS. Without this the factory helpfully
		-- builds a steering wheel for it — the fallback is right for a
		-- kart and absurd for anything else, and it would have been
		-- floating in the rider's lap.
		SteeringWheel.build(kart, hitbox)
	end

	-- One sweep at the end rather than remembering it at every
	-- Instance.new. Karts don't collide with each other or with seated
	-- racers; see KartService for the group setup.
	--
	-- NOTHING ON A KART COLLIDES WITH ANYTHING. The sweep used to set the
	-- group and leave CanCollide alone, so authored art arrived with
	-- whatever it was saved with — which is `true` unless somebody
	-- remembered otherwise. The group stopped kart-versus-kart, and left
	-- every other contact a piece of bodywork could make.
	--
	-- A kart is KINEMATIC: Simulation writes its position outright and
	-- resolves its own collisions with queries. Physics contact is not
	-- how this kart moves, so a collidable body panel can only ever be a
	-- source of forces nothing asked for — and CanQuery is the flag that
	-- actually decides what a kart hits (see FINDINGS).
	--
	-- The group STAYS as well. Belt and braces: it is what keeps a seated
	-- driver's limbs out of the way, and CanCollide can be flipped back
	-- on by anything that touches a part later.
	for _, desc in kart:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = RIG.CollisionGroup
			desc.CanCollide = false
		end
	end

	-- THE SHIELD BUBBLE STARTS INVISIBLE.
	--
	-- It's authored art welded into the kart, so it arrives at whatever
	-- transparency it was saved with — visible. The only thing that ever
	-- hid it was the client's Effects module, and that looks at YOUR kart
	-- and nothing else. So every other kart in the race wore a permanent
	-- shield: bots most obviously, but remote players too.
	--
	-- Hidden here so "off" is the default state of the world rather than
	-- something a client has to remember to impose. Whoever owns the
	-- simulation turns it on — Effects for a player, BotService for a bot.
	--
	-- Also forced non-solid: it's decoration, and a bubble that collides
	-- turns the kart into a beach ball.
	local bubble = kart:FindFirstChild(Config.Effects.ShieldName, true)
	if bubble then
		for _, part in { bubble, table.unpack(bubble:GetDescendants()) } do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
	end

	-- Stamped so the client can build its Simulation with the right
	-- handling. It owns the controller for its own kart, so this is the
	-- only way the kind reaches it.
	kart:SetAttribute(Names.VEHICLE_KIND, kind or Config.Vehicles.Default)

	CollectionService:AddTag(kart, KartFactory.TAG)
	return kart
end

return KartFactory
