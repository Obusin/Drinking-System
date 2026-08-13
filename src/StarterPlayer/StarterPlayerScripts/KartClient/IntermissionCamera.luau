--[[
	IntermissionCamera — plays the authored camera rail stored in
	ReplicatedFirst.Intermission while a round is assembling.

	The folder intentionally contains only ordinary Parts. Their numeric names
	define path order (including nested folders), and each Part's CFrame is the
	shot: move it for position, rotate it so its local +X face points where the
	camera should look. Keeping these markers in
	ReplicatedFirst makes them present before normal world streaming and avoids a
	server camera object trying to control every player's view.
--]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local CAM = Config.Match.IntermissionCamera

local IntermissionCamera = {}
IntermissionCamera.__index = IntermissionCamera

local function numericName(inst: Instance): number
	return tonumber(inst.Name) or math.huge
end

local function hierarchyKey(root: Instance, inst: Instance): string
	local bits = {}
	local cursor: Instance? = inst
	while cursor and cursor ~= root do
		local n = numericName(cursor)
		table.insert(bits, 1, if n < math.huge then ("%08d"):format(n) else cursor.Name)
		cursor = cursor.Parent
	end
	return table.concat(bits, "/")
end

local function markerPath(root: Instance): { BasePart }
	local parts = {}
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end
	table.sort(parts, function(a, b)
		-- Respect the numeric hierarchy: Intermission/1/1, /1/2, /2/1.
		-- Sorting only by leaf name would incorrectly make every "1" play
		-- before every "2" across separate authored groups.
		local ak, bk = hierarchyKey(root, a), hierarchyKey(root, b)
		return if ak ~= bk then ak < bk else a:GetFullName() < b:GetFullName()
	end)
	return parts
end

-- A direct child of Intermission is one SCENE, not merely another point on
-- the same rail. Markers inside that child blend; crossing to the next child
-- is an intentional hard cut to a new part of the map.
local function scenePath(root: Instance): { { BasePart } }
	local children = root:GetChildren()
	table.sort(children, function(a, b)
		local an, bn = numericName(a), numericName(b)
		return if an ~= bn then an < bn else a.Name < b.Name
	end)

	local scenes = {}
	for _, child in children do
		local markers = if child:IsA("BasePart") then { child } else markerPath(child)
		if #markers > 0 then
			table.insert(scenes, markers)
		end
	end
	return scenes
end

-- Studio's Part gizmo makes the local X face convenient to use as an authored
-- "camera points this way" arrow. Roblox cameras normally look down -Z, so
-- convert each marker rather than requiring every marker to be modelled with
-- an invisible 90-degree correction.
local function shotCFrame(marker: BasePart): CFrame
	return CFrame.lookAt(marker.Position, marker.Position + marker.CFrame.RightVector, marker.CFrame.UpVector)
end

function IntermissionCamera.new()
	return setmetatable({
		active = false,
		scenes = {},
		scene = 1,
		sceneElapsed = 0,
		streamRequested = {},
		streamReady = {},
		previousType = nil,
		previousFov = nil,
		lastShot = nil,
	}, IntermissionCamera)
end

function IntermissionCamera:_requestScene(index: number)
	if self.streamRequested[index] then
		return
	end
	local scene = self.scenes[index]
	if not scene then
		return
	end
	self.streamRequested[index] = true
	-- A camera can look far beyond the driver's streamed bubble. Ask Roblox
	-- to stream each authored scene around its markers before we cut there;
	-- this is event-driven per scene, never a per-frame streaming request.
	task.spawn(function()
		for _, marker in scene do
			pcall(function()
				Players.LocalPlayer:RequestStreamAroundAsync(marker.Position)
			end)
		end
		self.streamReady[index] = true
	end)
end

function IntermissionCamera:_begin(camera: Camera)
	local root = ReplicatedFirst:FindFirstChild(CAM.FolderName)
	self.scenes = if root then scenePath(root) else {}
	self.scene = 1
	self.sceneElapsed = 0
	table.clear(self.streamRequested)
	table.clear(self.streamReady)
	self.active = #self.scenes > 0
	if not self.active then
		return
	end
	self.previousType = camera.CameraType
	self.previousFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CAM.Fov
	-- A cinematic cut cannot wait for a streaming request at its boundary.
	-- There are only a few authored scenes, so request all of their marker
	-- areas once, up front, rather than discovering the next map region at
	-- the exact frame the camera is meant to cut there.
	for index = 1, #self.scenes do
		self:_requestScene(index)
	end
end

function IntermissionCamera:_end(camera: Camera)
	if not self.active then
		return
	end
	self.active = false
	-- A seated player owns a CameraRig, which will take Scriptable back on
	-- its next frame. An unseated player gets the exact camera mode they had.
	camera.CameraType = self.previousType or Enum.CameraType.Custom
	camera.FieldOfView = self.previousFov or camera.FieldOfView
	self.previousType, self.previousFov = nil, nil
end

function IntermissionCamera:Update(dt: number, shouldPlay: boolean)
	if not CAM.Enabled then
		shouldPlay = false
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if shouldPlay and not self.active then
		self:_begin(camera)
	elseif not shouldPlay and self.active then
		self:_end(camera)
	end
	if not self.active then
		return
	end

	local segmentTime = math.max(CAM.SegmentTime, 0.1)
	local current = self.scenes[self.scene]
	-- Never burn a scene's timeline while its region is still streaming.
	-- Hold on its opening shot; once Roblox confirms the request, the scene
	-- begins normally instead of arriving halfway through an unloaded map.
	if not self.streamReady[self.scene] then
		self.lastShot = shotCFrame(current[1])
		camera.CFrame = self.lastShot
		camera.FieldOfView = CAM.Fov
		return
	end
	self.sceneElapsed += dt

	-- Complete the current scene, then make one clean cut to the first marker
	-- of the next top-level folder. There is deliberately no interpolation OR
	-- hold across that folder boundary: a stopped camera reads like a loading
	-- hitch rather than a cinematic scene change.
	while self.scene < #self.scenes do
		local markers = self.scenes[self.scene]
		local duration = segmentTime * math.max(#markers - 1, 0)
		if self.sceneElapsed < duration then
			break
		end
		self.sceneElapsed -= duration
		self.scene += 1
	end

	local markers = self.scenes[self.scene]
	local count = #markers
	if count == 1 then
		self.lastShot = shotCFrame(markers[1])
		camera.CFrame = self.lastShot
		camera.FieldOfView = CAM.Fov
		return
	end
	local travel = segmentTime * (count - 1)
	local t = math.min(self.sceneElapsed, travel)
	local index = math.min(math.floor(t / segmentTime) + 1, count - 1)
	local alpha = math.clamp((t - (index - 1) * segmentTime) / segmentTime, 0, 1)
	local from = markers[index]
	local to = markers[index + 1]
	if from.Parent and to.Parent then
		self.lastShot = shotCFrame(from):Lerp(shotCFrame(to), alpha)
		camera.CFrame = self.lastShot
	end
	camera.FieldOfView = CAM.Fov
end

function IntermissionCamera:LastShot(): CFrame?
	return self.lastShot
end

function IntermissionCamera:Destroy()
	local camera = workspace.CurrentCamera
	if camera then
		self:_end(camera)
	end
end

return IntermissionCamera
