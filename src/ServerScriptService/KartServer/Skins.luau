--[[
	Skins — proving a kart skin is just a set of mesh ids.

	WHAT THIS IS ACTUALLY TESTING
	-----------------------------
	If a skin can be applied by swapping meshes on parts that already
	exist, then cosmetics need no new karts, no new models in
	ServerStorage, and no change to KartFactory — a skin becomes a row in
	a table. That is the difference between a cosmetics system you can
	ship and one you have to build.

	It also has to hold WITHOUT touching handling, and here it does by
	construction: the meshes sit on parts inside the visual, and the
	visual is art. Simulation reads the Hitbox and the Seat and nothing
	else, so a skin cannot change how a kart drives even by accident.

	A SKIN IS A SET, NOT A PART
	---------------------------
	Swapping the body alone leaves the old wheels on the new shell. The
	unit that has to swap atomically is the whole set, which is also the
	unit a player buys, so that is the unit this cycles.

	The wheels are the interesting case. They are MeshParts hung off
	Motor6Ds — the front steers and rolls, the rear only rolls — and the
	joints are built from each wheel's own pivot at spawn. Swapping the
	MESH under a live joint leaves the joint alone, so the wheels keep
	turning through the swap. If a swapped wheel ever spins about the
	wrong point, that is the new mesh's pivot differing from the old
	one's, not the joint breaking.

	MeshPart.MeshId IS NOT ASSIGNABLE AT RUNTIME
	--------------------------------------------
	It never has been — it is set when the part is created and read-only
	afterwards. Three routes are tried in order and the report names
	which one took, because that answer is the point of the exercise.
--]]

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local RIG = Config.Rig

local Skins = {}

-- Swaps the mesh on an existing MeshPart, and says how.
--
--   1. MeshContent = Content.fromUri(id)
--        The newer Content property. Direct, no yield, no extra part.
--   2. AssetService:CreateMeshPartAsync + ApplyMesh
--        The DOCUMENTED runtime path: build a MeshPart from the id and
--        transplant its mesh onto ours. Yields, so callers must not be
--        on a path that cannot.
--   3. MeshId = id
--        Attempted last and expected to fail. Here only so "nothing
--        worked" is stated rather than inferred.
local function apply(part: BasePart, id: string): (boolean, string)
	if pcall(function()
		(part :: any).MeshContent = Content.fromUri(id)
	end) then
		return true, "MeshContent"
	end

	local built
	if pcall(function()
		built = AssetService:CreateMeshPartAsync(id)
	end) and built then
		if pcall(function()
			(part :: any):ApplyMesh(built)
		end) then
			return true, "CreateMeshPartAsync + ApplyMesh"
		end
	end

	if pcall(function()
		(part :: any).MeshId = id
	end) then
		return true, "MeshId"
	end
	return false, "nothing"
end

-- Applies one skin — the whole set — to one kart. Returns how many
-- parts were found and how many actually took, so a caller can tell
-- "the wheels are not named that" from "the swap does not work here".
local function applySet(kart: Model, skin: { [string]: string }): (number, number, string)
	local found, changed, how = 0, 0, "nothing"
	for name, id in skin do
		-- Recursive: the part lives wherever the artist filed it, and
		-- requiring a fixed path is how the rocket lookup silently
		-- found nothing.
		local part = kart:FindFirstChild(name, true)
		if part and part:IsA("MeshPart") and id ~= "" then
			found += 1
			local ok, route = apply(part, id)
			if ok then
				changed += 1
				how = route
			end
		end
	end
	return found, changed, how
end

-- Reported once rather than per kart per swap, which at a few seconds a
-- set would bury Output within a minute.
local said = false

-- Names the parts that were never found, and any found under the right
-- name but of the wrong class — the two failures that otherwise look
-- identical to a swap that silently did nothing.
local function diagnose(kart: Model, skin: { [string]: string })
	local missing, wrong = {}, {}
	for name in skin do
		local part = kart:FindFirstChild(name, true)
		if not part then
			table.insert(missing, name)
		elseif not part:IsA("MeshPart") then
			table.insert(wrong, ("%s is a %s"):format(name, part.ClassName))
		end
	end
	table.sort(missing)
	table.sort(wrong)
	if #missing > 0 then
		warn(
			("[Skins] no MeshPart named %s in %s. The lookup is recursive, so the folder does not matter — only the name."):format(
				table.concat(missing, ", "),
				kart:GetFullName()
			)
		)
	end
	if #wrong > 0 then
		warn(
			("[Skins] %s — only a MeshPart has a mesh to swap. A Part with a SpecialMesh inside is a different thing and needs a different write."):format(
				table.concat(wrong, ", ")
			)
		)
	end
end

function Skins.start()
	if not RIG.SkinTest or #RIG.SkinTestSkins < 2 then
		return
	end

	warn(
		("[Skins] TEST MODE: cycling %d skin sets every %.1fs. Rig.SkinTest = false to stop."):format(
			#RIG.SkinTestSkins,
			RIG.SkinTestInterval
		)
	)

	task.spawn(function()
		local at = 0
		while true do
			task.wait(RIG.SkinTestInterval)
			at += 1
			local skin = RIG.SkinTestSkins[(at - 1) % #RIG.SkinTestSkins + 1]

			local karts, found, changed = 0, 0, 0
			local how, sample = "nothing", nil
			for _, kart in CollectionService:GetTagged("Kart") do
				if kart:IsA("Model") then
					karts += 1
					sample = sample or kart
					local f, c, route = applySet(kart, skin)
					found += f
					changed += c
					if c > 0 then
						how = route
					end
				end
			end

			-- SAID ONCE, and it says what was actually seen. Waits for a
			-- kart to exist first: the first tick lands a few seconds in
			-- and spending the one report on "found nothing in 0 karts"
			-- would answer a question nobody asked.
			if karts > 0 and not said then
				said = true
				local want = 0
				for _ in skin do
					want += 1
				end
				if found < karts * want and sample then
					diagnose(sample, skin)
				end
				if found == 0 then
					warn(("[Skins] nothing to swap in %d kart(s) — see above for which names missed."):format(karts))
				elseif changed == 0 then
					warn(
						"[Skins] parts found but no runtime mesh swap worked on this engine. Skins need a separate model per skin, applied through Rig.VisualName."
					)
				else
					print(
						("[Skins] swapping %d mesh(es) across %d kart(s) via %s — skins CAN be pure asset ids."):format(
							changed,
							karts,
							how
						)
					)
				end
			end
		end
	end)
end

--=====================================================================
--  WHO LOOKS LIKE WHAT
--
--  Stable per racer: the same key always produces the same look, so a
--  player keeps their kart across respawns, retirement and rebuilds
--  rather than changing shape every time the watchdog hands them a new
--  one.
--
--  The GARAGE REPLACES THIS FUNCTION AND NOTHING ELSE. Everything below
--  it — the set shape, applyTo, the fact that a skin is mesh ids and
--  cannot reach handling — is already what a chosen skin needs.
--=====================================================================
local SK = Config.Skins

local function hash(key: string): number
	local h = 5381
	for i = 1, #key do
		h = (h * 33 + string.byte(key, i)) % 2147483647
	end
	return h
end

function Skins.randomFor(key: string): { [string]: string }
	local h = hash(key)
	local body = SK.Bodies[h % #SK.Bodies + 1]
	-- Front and rear from the SAME entry. Mismatched axles read as a bug
	-- rather than as a build.
	local wheel = SK.Wheels[math.floor(h / 7) % #SK.Wheels + 1]
	return { Body = body, FWheel = wheel, RWheel = wheel }
end

-- Gives a kart its look. YIELDS — the working swap route is
-- CreateMeshPartAsync, which fetches over the network — so this is
-- spawned by the caller and never sits on the path that builds a kart.
function Skins.dress(kart: Model, key: string)
	if not SK.Enabled or not kart.Parent then
		return
	end
	Skins.applyTo(kart, Skins.randomFor(key))
end

-- The real entry point for later: one kart, one skin, no loop. The test
-- above exists to prove this line is possible; this is the line.
function Skins.applyTo(kart: Model, skin: { [string]: string }): boolean
	local _, changed = applySet(kart, skin)
	return changed > 0
end

return Skins
