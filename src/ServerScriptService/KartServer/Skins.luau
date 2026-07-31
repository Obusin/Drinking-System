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

-- Returns true if the mesh actually changed.
local function apply(part: BasePart, id: string): boolean
	-- MeshContent first: it is the assignable one.
	local ok = pcall(function()
		(part :: any).MeshContent = Content.fromUri(id)
	end)
	if ok then
		if not said then
			said = true
			print("[Skins] MeshContent is writable at runtime — skins can be pure asset ids.")
		end
		return true
	end

	-- Only to turn a silent no-op into a stated one.
	local legacy = pcall(function()
		(part :: any).MeshId = id
	end)
	if not said then
		said = true
		if legacy then
			print("[Skins] MeshContent failed but MeshId took — unusual, worth noting.")
		else
			warn(
				"[Skins] neither MeshContent nor MeshId could be set at runtime. Skins cannot be a mesh swap on this engine version; they need a separate model per skin, swapped through Rig.VisualName."
			)
		end
	end
	return legacy
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

			for _, kart in CollectionService:GetTagged("Kart") do
				-- Recursive: the part lives wherever the artist filed it,
				-- and requiring a fixed path is how the rocket lookup
				-- silently found nothing.
				local part = kart:FindFirstChild(RIG.SkinPart, true)
				if part and part:IsA("MeshPart") then
					apply(part, id)
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
	return apply(part, id)
end

return Skins
