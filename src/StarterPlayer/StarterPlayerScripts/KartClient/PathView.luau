--[[
	PathView — draws the bot path, for one person.

	DRAWN ON THE CLIENT, WHICH IS THE WHOLE POINT.

	The server used to build these markers in `workspace`, so every player
	in the round saw a track covered in floating dots. A part is a part —
	there is no per-player visibility on one — so the only way to show
	this to an admin and nobody else is for the admin's own machine to
	draw it.

	It reads `Route` directly, which is shared, so nothing has to be sent
	over the wire and the picture cannot disagree with what the bots are
	following.

	KNOWN LIMIT: with streaming on, a client can hold fewer tagged parts
	than the server does, so a distant stretch may be missing here while
	being perfectly fine for the bots. The server's `Route.preflight` line
	is the authority on counts; this is the authority on SHAPE.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Route = require(BloxKart:WaitForChild("Route"))

local B = Config.Bots
local R = Config.Race

local PathView = {}

local folder: Folder? = nil

local function clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

local function marker(parent: Instance, at: Vector3, size: number, colour: Color3, ball: boolean)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Material = Enum.Material.Neon
	p.Color = colour
	p.Transparency = 0.35
	p.Shape = if ball then Enum.PartType.Ball else Enum.PartType.Block
	p.Size = Vector3.one * size
	p.Position = at
	p.Parent = parent
end

-- Rebuilt from scratch rather than diffed. It is a debug view redrawn by
-- hand, and a hundred parts is nothing next to the code needed to work
-- out which of them moved.
function PathView.show()
	clear()

	local nodes = Route.path()
	if #nodes == 0 then
		warn(("[PathView] nothing tagged %q or %q — no path to draw."):format(R.BotPathTag, R.CheckpointTag))
		return
	end

	local f = Instance.new("Folder")
	f.Name = "_BotPathView"
	f.Parent = workspace
	folder = f

	local holes, jumps = 0, 0
	for i, node in nodes do
		local up = node.parts[1] and node.parts[1].CFrame.UpVector or Vector3.yAxis

		-- The node itself.
		marker(f, node.position + up * 2, 4, Color3.fromRGB(90, 170, 255), true)

		-- THE CURVE BETWEEN THEM, which is what bots actually follow. A
		-- path can be made entirely of nodes sitting on tarmac and still
		-- run through the air between them, because a Catmull-Rom bows
		-- outside the road on a tight corner.
		for k = 1, 7 do
			local at = Route.pointAt(i - 1 + k / 8, nil, nodes)
			if at then
				local colour, size
				if Route.hasGround(at, up) then
					colour, size = Color3.fromRGB(255, 230, 120), 1.1
				elseif Route.launcherNear(at, R.RouteJumpLookout) then
					-- A gap with a ramp is a JUMP and the road is meant to
					-- stop. Colouring it like a hole reports every ramp on
					-- the track as a fault.
					colour, size = Color3.fromRGB(120, 200, 255), 1.6
					jumps += 1
				else
					colour, size = Color3.fromRGB(255, 70, 70), 2.2
					holes += 1
				end
				marker(f, at + up * 1.5, size, colour, false)
			end
		end

		-- THE ROAD EDGE the bots are clamped inside, drawn with the SAME
		-- `across` the widths were measured along rather than one derived
		-- again — two derivations disagree on a corner, and that is what
		-- put these beside the road last time.
		if node.across.Magnitude > 1e-4 then
			local l = math.max(node.leftWidth - B.EdgeMargin, 0)
			local r = math.max(node.rightWidth - B.EdgeMargin, 0)
			marker(f, node.position - node.across * l + up * 1.5, 1.6, Color3.fromRGB(120, 230, 140), false)
			marker(f, node.position + node.across * r + up * 1.5, 1.6, Color3.fromRGB(120, 230, 140), false)
		end
	end

	print(
		("[PathView] %d node(s) · %d hole(s) in the line · %d gap(s) covered by a ramp. Blue balls are nodes, green is the road edge, red is the line leaving the road."):format(
			#nodes,
			holes,
			jumps
		)
	)
end

function PathView.hide()
	clear()
end

function PathView.toggle(on: boolean?)
	if on == nil then
		on = folder == nil
	end
	if on then
		PathView.show()
	else
		PathView.hide()
	end
	return folder ~= nil
end

return PathView
