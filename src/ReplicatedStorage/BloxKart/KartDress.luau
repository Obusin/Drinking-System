--[[
	KartDress — put a look on a kart, from either side of the wire.

	WHY THIS IS SHARED AND KartServer/Skins IS NOT
	----------------------------------------------
	Skins.luau lives in ServerScriptService, so the client cannot require
	it — and the garage has to dress a kart the client owns outright: the
	MenuStage preview is a local clone that no server ever sees. This
	holds the part of the job that is identical on both sides (swap a
	mesh, paint the body) and nothing that is not.

	It deliberately does NOT do Skins.luau's reattach work. That exists
	because swapping a mesh on a LIVE kart can pop the part out of a
	moving assembly, which needs the motor or weld rebuilding. A menu
	kart is anchored scenery: there is no assembly to fall out of, and
	copying that logic here would be carrying a fix for a problem this
	caller cannot have.

	NOTHING HERE CAN AFFECT HANDLING. Simulation reads the Hitbox and the
	Seat; a mesh and a colour are decoration by construction.
--]]

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")

local KartDress = {}

-- Swaps the mesh on an existing MeshPart. Same three routes, in the same
-- order, as KartServer/Skins — see the long note there for why MeshId is
-- last and expected to fail.
--
-- YIELDS on the CreateMeshPartAsync route (it fetches), so callers must
-- be on a thread that can wait.
function KartDress.applyMesh(part: BasePart, id: string): boolean
	if id == "" then
		return false
	end

	if pcall(function()
		(part :: any).MeshContent = Content.fromUri(id)
	end) then
		return true
	end

	local built
	if pcall(function()
		built = AssetService:CreateMeshPartAsync(id)
	end) and built then
		if pcall(function()
			(part :: any):ApplyMesh(built)
		end) then
			return true
		end
	end

	return (pcall(function()
		(part :: any).MeshId = id
	end))
end

-- Parts under `model` whose name is in `names`.
--
-- `meshOnly` MATTERS, and conflating the two cases was a real bug.
--
-- Swapping a mesh requires a MeshPart — there is nowhere to put a MeshId
-- otherwise. PAINTING does not: `Color` is on BasePart, so a Part, a
-- WedgePart or a UnionOperation takes it perfectly well.
--
-- This used to filter to MeshPart for BOTH, so on any kart whose `Body`
-- is not a MeshPart the paint silently did nothing — while the SERVER
-- painted it fine, because that path only ever asked for a BasePart.
-- Same look, same name, two answers: the garage showed a kart that
-- refused to change colour and the real kart did change, which is
-- exactly backwards from how it was being reported.
local function partsNamed(model: Instance, names: { string }, meshOnly: boolean): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		local ok = if meshOnly then d:IsA("MeshPart") else d:IsA("BasePart")
		if ok then
			for _, n in names do
				if d.Name == n then
					table.insert(out, d :: BasePart)
					break
				end
			end
		end
	end
	return out
end

-- WHICH PARTS TAKE A COLOUR. One definition, every caller.
--
-- This is the bug that kept karts stubbornly red. `KartFactory` paints
-- the grid colour onto `Rig.PaintTag` + `Rig.PaintParts` — which is
-- { "Chassis", "Nose" } — while the garage paint only ever touched the
-- part named by `Rig.BodyNames`. So the factory coloured the
-- visible bodywork red and the garage coloured something else. The paint
-- WAS applying; it was landing on a part nobody looks at.
--
-- The body mesh's own part is included as well as the factory's set, so
-- the garage covers everything the grid colour touched PLUS the panel it
-- swapped a mesh onto. A colour the player chose should never leave a
-- patch of grid red behind.
--
-- Tag first, then name: tagging is what lets a new kart opt parts in
-- without editing config.
function KartDress.paintableParts(model: Instance, rig): { BasePart }
	local names = {}
	for _, n in (rig and rig.BodyNames or { "Body" }) do
		table.insert(names, n)
	end
	if rig and rig.PaintParts then
		for _, n in rig.PaintParts do
			table.insert(names, n)
		end
	end
	local tag = rig and rig.PaintTag
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local take = tag ~= nil and CollectionService:HasTag(d, tag)
			if not take then
				take = table.find(names, d.Name) ~= nil
			end
			if take then
				table.insert(out, d :: BasePart)
			end
		end
	end
	return out
end

-- Applies a look to a kart model.
--
-- `look` is { body = meshId?, wheel = meshId?, paint = Color3? } — all
-- optional, so the garage can change one slot without restating the
-- others. Mesh ids of "" mean "stock", i.e. leave the built mesh alone.
--
-- PAINT GOES ON THE BODY PART, the same part the body mesh is swapped
-- onto, so shape and colour always describe the same object.
-- Returns TRUE only if everything asked for actually landed.
--
-- It used to return nothing and swallow applyMesh's result, which let a
-- caller record "dressed" for a dress that failed. During loading the
-- mesh routes CAN fail — CreateMeshPartAsync fetches over the network —
-- so on a cold join the apply quietly did nothing, got marked done, and
-- was never retried. Opening the garage "fixed" it only because that
-- path re-applies unconditionally and by then the assets had arrived.
--
-- A caller that caches on this MUST cache on the return value.
function KartDress.apply(model: Instance, look: { body: string?, wheel: string?, paint: Color3? }, rig): boolean
	local bodyNames = if rig and rig.BodyNames then rig.BodyNames else { "Body" }
	local wheelNames = {}
	if rig then
		for _, n in rig.FrontWheelNames do
			table.insert(wheelNames, n)
		end
		for _, n in rig.RearWheelNames do
			table.insert(wheelNames, n)
		end
	else
		wheelNames = { "FWheel", "RWheel" }
	end

	local ok = true

	if look.body and look.body ~= "" then
		local parts = partsNamed(model, bodyNames, true)
		-- No parts is a FAILURE, not a no-op: we were asked for a body
		-- and this model has nowhere to put one. Reporting success there
		-- is how a naming mismatch stayed invisible.
		if #parts == 0 then
			ok = false
		end
		for _, part in parts do
			if not KartDress.applyMesh(part, look.body) then
				ok = false
			end
		end
	end

	if look.wheel and look.wheel ~= "" then
		local parts = partsNamed(model, wheelNames, true)
		if #parts == 0 then
			ok = false
		end
		for _, part in parts do
			if not KartDress.applyMesh(part, look.wheel) then
				ok = false
			end
		end
	end

	-- Applied AFTER the mesh: a swapped mesh arrives with its own colour,
	-- so painting first would be overwritten by the very next line.
	--
	-- Re-queried WITHOUT the MeshPart filter, and not reusing the list
	-- above. Colour lives on BasePart, so a body that is a Part or a
	-- Union still paints even though it can never take a mesh swap —
	-- and those are the karts where the paint appeared to do nothing.
	if look.paint then
		local parts = KartDress.paintableParts(model, rig)
		if #parts == 0 then
			ok = false
		end
		for _, part in parts do
			part.Color = look.paint
		end
	end

	return ok
end

return KartDress
