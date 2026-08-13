--[[ RouteGuide — a client-only visual of the authored driving line. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Route = require(BloxKart:WaitForChild("Route"))

local RouteGuide = {}
RouteGuide.__index = RouteGuide

local COLOURS = {
	Color3.fromRGB(255, 90, 115), Color3.fromRGB(255, 175, 65),
	Color3.fromRGB(255, 235, 85), Color3.fromRGB(85, 235, 130),
	Color3.fromRGB(85, 175, 255), Color3.fromRGB(175, 105, 255),
}
local MARKERS = 72

local function marker(parent: Instance, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = "RouteGuideMarker"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.48, 0.48, 0.48)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = colour
	part.Transparency = 0.62
	part.Parent = parent
	return part
end

function RouteGuide.new()
	local folder = Instance.new("Folder")
	folder.Name = "LocalRouteGuide"
	folder.Parent = workspace
	return setmetatable({ folder = folder, markers = {}, signature = "", visible = false }, RouteGuide)
end

function RouteGuide:_hide()
	for _, part in self.markers do
		part.Transparency = 1
	end
end

function RouteGuide:Update(on: boolean)
	if not on then
		if self.visible then self:_hide() end
		self.visible = false
		return
	end
	local path = Route.path()
	if #path < 2 then
		self:_hide()
		self.visible = false
		return
	end
	-- Route caches the expensive world sampling. This small signature only
	-- decides whether streamed/re-authored nodes require a visual rebuild.
	local signature = tostring(#path) .. ":" .. tostring(path[1].position) .. ":" .. tostring(path[#path].position)
	if signature ~= self.signature or not self.visible then
		self.signature = signature
		for i = 1, MARKERS do
			local part = self.markers[i]
			if not part then
				part = marker(self.folder, COLOURS[(i - 1) % #COLOURS + 1])
				self.markers[i] = part
			end
			local u = (i - 1) * #path / MARKERS
			local at = Route.pointAt(u, nil, path)
			if at then
				part.Position = at + Vector3.yAxis * 0.35
				part.Transparency = 0.62
			end
		end
	end
	self.visible = true
end

function RouteGuide:Destroy()
	self.folder:Destroy()
end

return RouteGuide
