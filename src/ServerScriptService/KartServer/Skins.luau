--[[
	Skins — proving a kart skin is just a mesh id.

	WHAT THIS IS ACTUALLY TESTING
	-----------------------------
	If a skin can be applied by swapping the mesh on an existing part,
	then cosmetics need no new karts, no new models in ServerStorage, and
	no change to KartFactory — a skin becomes a row in a table and an
	asset id. That is the difference between a cosmetics system you can
	ship and one you have to build.

	It also has to hold WITHOUT touching handling, and here it does by
	construction: the mesh sits on a part inside the visual, and the
	visual is art. Simulation reads the Hitbox and the Seat and nothing
	else, so a skin cannot change how a kart drives even by accident.

	MeshPart.MeshId IS NOT ASSIGNABLE AT RUNTIME
	--------------------------------------------
	It never has been — it is set when the part is created and read-only
	afterwards. The newer `MeshContent` property is the one that can be
	written, so that is the path this uses, with MeshId attempted as a
	fallback purely so the failure is reported rather than silent.

	Which of the two worked is printed once. That answer is the entire
	point of the exercise, and it decides how cosmetics get built.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local RIG = Config.Rig

local Skins = {}

-- Reported once rather than per kart per swap, which at a few seconds an
-- id would bury Output within a minute.
local said = false

-- Swaps the mesh on an existing MeshPart, and says how.
--
-- THREE ROUTES, tried in order, because which one exists depends on the
-- engine version and only one of them is the documented answer:
--
--   1. MeshContent = Content.fromUri(id)
--        The newer Content property. Direct, no yield, no extra part.
--   2. AssetService:CreateMeshPartAsync + ApplyMesh
--        The DOCUMENTED runtime path: build a MeshPart from the id and
--        transplant its mesh onto ours. Yields, so this runs inside the
--        loop's own thread.
--   3. MeshId = id
--        Attempted last and expected to fail. MeshPart.MeshId has never
--        been assignable at runtime; it is here only so "nothing worked"
--        is stated rather than inferred.
local AssetService = game:GetService("AssetService")

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

function Skins.start()
	if not RIG.SkinTest or #RIG.SkinTestIds < 2 then
		return
	end

	warn(
		("[Skins] TEST MODE: cycling %s between %d mesh ids every %.1fs. Rig.SkinTest = false to stop."):format(
			RIG.SkinPart,
			#RIG.SkinTestIds,
			RIG.SkinTestInterval
		)
	)

	task.spawn(function()
		local at = 0
		while true do
			task.wait(RIG.SkinTestInterval)
			at += 1
			local id = RIG.SkinTestIds[(at - 1) % #RIG.SkinTestIds + 1]

			local karts, found, changed = 0, 0, 0
			local how = "nothing"
			for _, kart in CollectionService:GetTagged("Kart") do
				karts += 1
				-- Recursive: the part lives wherever the artist filed it,
				-- and requiring a fixed path is how the rocket lookup
				-- silently found nothing.
				local part = kart:FindFirstChild(RIG.SkinPart, true)
				if part and part:IsA("MeshPart") then
					found += 1
					local ok, route = apply(part, id)
					if ok then
						changed += 1
						how = route
					end
				elseif part and not said then
					said = true
					warn(
						("[Skins] found %s but it is a %s, not a MeshPart — only a MeshPart has a mesh to swap."):format(
							part:GetFullName(),
							part.ClassName
						)
					)
				end
			end

			-- SAID ONCE, and it says what was actually seen. The first
			-- version reported only the write, so a part that was never
			-- found produced no output at all — which is
			-- indistinguishable from a swap that silently did nothing,
			-- and is the likelier of the two.
			-- Nothing to report on yet. The first tick lands a few seconds
			-- in and karts may not exist, and reporting "found nothing in
			-- 0 karts" would burn the one report on a question nobody
			-- asked.
			if karts > 0 and not said then
				said = true
				if found == 0 then
					warn(
						("[Skins] no MeshPart named %q in any of %d kart(s). Check the name matches exactly — it is looked up recursively, so its folder does not matter."):format(
							RIG.SkinPart,
							karts
						)
					)
				elseif changed == 0 then
					warn(
						("[Skins] found %d %q part(s) but no runtime mesh swap worked on this engine. Skins need a separate model per skin, applied through Rig.VisualName."):format(
							found,
							RIG.SkinPart
						)
					)
				else
					print(
						("[Skins] swapping %d %q mesh(es) via %s — skins CAN be pure asset ids."):format(
							changed,
							RIG.SkinPart,
							how
						)
					)
				end
			end
		end
	end)
end

-- The real entry point for later: one kart, one id, no loop. The test
-- above exists to prove this line is possible; this is the line.
function Skins.applyTo(kart: Model, id: string): boolean
	local part = kart:FindFirstChild(RIG.SkinPart, true)
	if not (part and part:IsA("MeshPart") and id ~= "") then
		return false
	end
	local ok = apply(part, id)
	return ok
end

return Skins
