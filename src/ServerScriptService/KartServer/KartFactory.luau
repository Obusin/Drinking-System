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
function KartFactory.build(color: Color3?, visualName: string?): Model
	local kart = Instance.new("Model")
	kart.Name = "Kart"

	-- The one part that matters. Non-colliding: the controller does its
	-- own swept collision, so Roblox's solver never gets a vote. That is
	-- what makes handling identical on every machine and frame rate.
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = RIG.HitboxSize
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
	seat.CFrame = CFrame.new(0, 0.5, 0.6)
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

	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0, seatWeld.Part1 = hitbox, seat
	seatWeld.Parent = hitbox

	-- Visual: yours if you supplied one, otherwise the placeholder.
	local wanted = visualName or RIG.VisualName
	-- RECURSIVE, because art gets filed. The rocket was found only after
	-- this same lookup was widened; a kart tidied into a folder would
	-- otherwise fall silently back to the placeholder.
	local template = if wanted ~= "" then ServerStorage:FindFirstChild(wanted, true) else nil
	local visual: Model
	if template and template:IsA("Model") then
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

		for _, d in visual:GetDescendants() do
			if not d:IsA("BasePart") then
				continue
			end
			if
				CollectionService:HasTag(d, RIG.WheelFrontTag)
				or CollectionService:HasTag(d, RIG.WheelRearTag)
				or table.find(RIG.FrontWheelNames, d.Name)
				or table.find(RIG.RearWheelNames, d.Name)
			then
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
	local function wheelKind(part: BasePart): boolean?
		if CollectionService:HasTag(part, RIG.WheelFrontTag) then
			return true
		end
		if CollectionService:HasTag(part, RIG.WheelRearTag) then
			return false
		end
		if table.find(RIG.FrontWheelNames, part.Name) then
			return true
		end
		if table.find(RIG.RearWheelNames, part.Name) then
			return false
		end
		return nil
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

			-- The hub itself gets a Motor6D below, not a weld. Its
			-- children weld to the hub so they spin with it.
			local isFront = wheelKind(desc)
			if isFront ~= nil then
				-- Motor6D, not a weld: a weld can't be rotated at runtime.
				local motor = Instance.new("Motor6D")
				motor.Name = "RoadWheelMotor"
				motor.Part0, motor.Part1 = hitbox, desc
				-- About the wheel's own pivot. Anchored to its CFrame origin
				-- instead, an imported wheel orbits that point rather than
				-- spinning on its axle.
				motor.C0, motor.C1 = Util.pivotJoint(hitbox, desc)
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
			elseif desc ~= suppliedWheel then
				local anchorTo = if suppliedWheel and desc:IsDescendantOf(suppliedWheel)
					then suppliedWheel
					else hitbox
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = anchorTo, desc
				weld.Parent = anchorTo
			end
		end
	end

	if suppliedWheel then
		SteeringWheel.motorise(hitbox, suppliedWheel)
		log("using the SteeringWheel from the supplied visual")
	else
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

	CollectionService:AddTag(kart, KartFactory.TAG)
	return kart
end

return KartFactory
