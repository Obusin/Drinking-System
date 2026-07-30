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
function KartFactory.colorFor(slot: number): Color3
	local palette = RIG.Colors
	return palette[(slot % #palette) + 1]
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
	local template = ServerStorage:FindFirstChild(wanted)
	local visual: Model
	if template and template:IsA("Model") then
		visual = template:Clone()
		visual.Name = "Visual"
		log("using ServerStorage.%s as the kart visual", wanted)
	else
		if visualName then
			warn(("[KartFactory] no Model named %q in ServerStorage — using the placeholder."):format(wanted))
		end
		visual = PlaceholderVisual.build()
	end

	-- A supplied visual is DECORATION. Artists naturally model a whole
	-- kart, seat and all, and welding that on would leave a second
	-- VehicleSeat a player could sit in — outside the lock-in logic
	-- entirely — plus a second part called Hitbox for everything that
	-- looks one up by name to trip over.
	--
	-- Stripped here rather than asked for in the docs, because "delete
	-- these two before exporting" is a rule someone forgets exactly once
	-- and then spends an afternoon on.
	for _, desc in visual:GetDescendants() do
		if desc:IsA("VehicleSeat") or desc:IsA("Seat") or desc.Name == "Hitbox" then
			log("stripping %s from the supplied visual — the factory owns that", desc.Name)
			desc:Destroy()
		end
	end

	visual.Parent = kart
	visual:PivotTo(CFrame.new(RIG.VisualOffset))

	-- If the supplied art already has a steering wheel, that becomes the
	-- hub and we skip building one. Its subtree must NOT be welded to
	-- the hitbox or the Motor6D couldn't turn it.
	local supplied = visual:FindFirstChild("SteeringWheel", true)
	local suppliedWheel = if supplied and supplied:IsA("BasePart") then supplied else nil

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
			if desc ~= suppliedWheel then
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
	for _, desc in kart:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = RIG.CollisionGroup
		end
	end

	CollectionService:AddTag(kart, KartFactory.TAG)
	return kart
end

return KartFactory
