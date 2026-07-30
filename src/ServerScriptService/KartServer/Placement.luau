--[[
	Placement — finding the SpawnLocation and working out where a kart
	goes on the start line.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.BloxKart.Config)

local RIG = Config.Rig

local Placement = {}

function Placement.findSpawn(): SpawnLocation?
	if RIG.SpawnName ~= "" then
		local named = workspace:FindFirstChild(RIG.SpawnName, true)
		if named and named:IsA("SpawnLocation") then
			return named
		end
		warn(("[Placement] No SpawnLocation named %q found."):format(RIG.SpawnName))
	end

	-- Prefer an enabled pad; a disabled one is usually scenery.
	local fallback: SpawnLocation? = nil
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") then
			if inst.Enabled then
				return inst
			end
			fallback = fallback or inst
		end
	end
	return fallback
end

-- A staggered starting grid rather than one long line: 8 karts abreast
-- would be ~60 studs wide and hang off most tracks.
--
-- Columns stay centred on the pad; the stagger is fore/aft, so the
-- right-hand column sits slightly back — an actual racing grid.
--
--   . .          slot 0 front-left, slot 1 half a length back
--    . .
--   . .
function Placement.cframeFor(pad: SpawnLocation?, slot: number): CFrame
	local cols = math.max(RIG.GridColumns, 1)
	local row = math.floor(slot / cols)
	local col = slot % cols

	-- Symmetric about the centreline: an odd sideways offset would put
	-- half the field off the edge of the track.
	local sideways = (col - (cols - 1) * 0.5) * RIG.GridSpacing
	local backwards = row * RIG.GridRowSpacing + col * RIG.GridStagger

	-- The hitbox origin sits at its centre, so lift by half its height.
	local lift = RIG.HitboxSize.Y * 0.5 + RIG.DropHeight

	if not pad then
		return RIG.FallbackCF + Vector3.new(sideways, lift, backwards)
	end

	local topY = pad.Position.Y + pad.Size.Y * 0.5
	-- Yaw only — a tilted pad shouldn't spawn a tilted kart.
	local look = pad.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-4 then flat.Unit else Vector3.new(0, 0, -1)
	local sideDir = Vector3.new(0, 1, 0):Cross(flat)

	local pos = Vector3.new(pad.Position.X, topY + lift, pad.Position.Z)
		+ sideDir * sideways
		- flat * backwards -- rows sit BEHIND the line, not in front
	return CFrame.lookAt(pos, pos + flat)
end

return Placement
