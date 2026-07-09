-- RoleDisplayController: wires the Studio UI  StarterGui > Role > RoleLevel.
-- Zone-based role: standing inside any part marked DS_BartenderZone makes you
-- a Bartender; everywhere else you're a Customer. Shows "Role • Lv. N" using
-- the leaderstats Level.
--
-- Studio setup: add the attribute  DS_BartenderZone = true  (or the tag
-- "DS_BartenderZone") to one or more invisible parts covering the bar area.
-- Zones are display-only for now — future server-side gating (e.g. only
-- bartenders can mix) can reuse the same marker.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

local playerGui = player:WaitForChild("PlayerGui")
local roleGui = playerGui:WaitForChild("Role", 15)
if not roleGui then
	warn("[DrinkSystem][Role] StarterGui.Role not found — role display disabled")
	return
end
roleGui.ResetOnSpawn = false  -- this controller wires references once

local roleLabel = roleGui:WaitForChild("RoleLevel", 10)
if not (roleLabel and roleLabel:IsA("TextLabel")) then
	warn("[DrinkSystem][Role] Role.RoleLevel TextLabel not found — role display disabled")
	return
end

---------------------------------------------------------------------
-- Zone registry: parts with DS_BartenderZone (attribute or tag).
-- Rescanned occasionally so zones added later in Studio still register.
---------------------------------------------------------------------
local zones: { BasePart } = {}

local function refreshZones()
	local found: { BasePart } = {}
	local seen: { [BasePart]: boolean } = {}
	for _, inst in ipairs(CollectionService:GetTagged("DS_BartenderZone")) do
		if inst:IsA("BasePart") and not seen[inst] then
			seen[inst] = true
			table.insert(found, inst)
		end
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst:GetAttribute("DS_BartenderZone") == true and not seen[inst] then
			seen[inst] = true
			table.insert(found, inst)
		end
	end
	zones = found
end

local function isInsideZone(position: Vector3): boolean
	for _, zone in ipairs(zones) do
		if zone.Parent then
			local localPoint = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size * 0.5
			if math.abs(localPoint.X) <= half.X
				and math.abs(localPoint.Y) <= half.Y
				and math.abs(localPoint.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

---------------------------------------------------------------------
-- XP bar (sits just above the RoleLevel text) + floating "+XP" popups
---------------------------------------------------------------------
local TweenService = game:GetService("TweenService")

local xpBack = Instance.new("Frame")
xpBack.Name = "XPBar"
xpBack.AnchorPoint = Vector2.new(0.5, 1)
xpBack.Position = UDim2.new(0.5, 0, 0, -6)  -- just above the label
xpBack.Size = UDim2.new(1, 0, 0, 6)
xpBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
xpBack.BackgroundTransparency = 0.3
xpBack.BorderSizePixel = 0
xpBack.Parent = roleLabel
local xpBackCorner = Instance.new("UICorner")
xpBackCorner.CornerRadius = UDim.new(1, 0)
xpBackCorner.Parent = xpBack

local xpFill = Instance.new("Frame")
xpFill.AnchorPoint = Vector2.new(0, 0.5)
xpFill.Position = UDim2.new(0, 0, 0.5, 0)
xpFill.Size = UDim2.new(0, 0, 1, 0)
xpFill.BackgroundColor3 = Color3.fromRGB(255, 205, 80)  -- bartender gold
xpFill.BorderSizePixel = 0
xpFill.Parent = xpBack
local xpFillCorner = Instance.new("UICorner")
xpFillCorner.CornerRadius = UDim.new(1, 0)
xpFillCorner.Parent = xpFill

local gainLabel = Instance.new("TextLabel")
gainLabel.AnchorPoint = Vector2.new(0.5, 1)
gainLabel.Position = UDim2.new(0.5, 0, 0, -14)
gainLabel.AutomaticSize = Enum.AutomaticSize.XY
gainLabel.BackgroundTransparency = 1
gainLabel.Font = Enum.Font.MontserratBold
gainLabel.Text = ""
gainLabel.TextSize = 15
gainLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
gainLabel.Visible = false
gainLabel.Parent = xpBack
local gainStroke = Instance.new("UIStroke")
gainStroke.Color = Color3.fromRGB(0, 0, 0)
gainStroke.Thickness = 1.2
gainStroke.Parent = gainLabel

local lastXP: number? = nil
local lastGoal: number? = nil
local gainToken = 0

local function showGain(amount: number)
	if amount <= 0 then return end
	gainToken += 1
	local token = gainToken
	gainLabel.Text = string.format("+%d XP", amount)
	gainLabel.TextTransparency = 0
	gainStroke.Transparency = 0
	gainLabel.Position = UDim2.new(0.5, 0, 0, -14)
	gainLabel.Visible = true
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gainLabel, info, {
		Position = UDim2.new(0.5, 0, 0, -34),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(gainStroke, info, { Transparency = 1 }):Play()
	task.delay(1.1, function()
		if gainToken == token then
			gainLabel.Visible = false
		end
	end)
end

local function updateXPBar()
	local xp = tonumber(player:GetAttribute("BartenderXP")) or 0
	local goal = math.max(tonumber(player:GetAttribute("BartenderXPGoal")) or 1, 1)

	-- Floating "+XP" on gains (handles the level-up wraparound too)
	if lastXP ~= nil then
		local delta
		if xp >= lastXP then
			delta = xp - lastXP
		else
			-- leveled up: finish of the old bar + progress into the new one
			delta = ((lastGoal or goal) - lastXP) + xp
		end
		showGain(delta)
	end
	lastXP, lastGoal = xp, goal

	TweenService:Create(xpFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(math.clamp(xp / goal, 0, 1), 0, 1, 0),
	}):Play()
end

player:GetAttributeChangedSignal("BartenderXP"):Connect(updateXPBar)
player:GetAttributeChangedSignal("BartenderXPGoal"):Connect(updateXPBar)
-- Initialize without a "+XP" popup
lastXP = tonumber(player:GetAttribute("BartenderXP")) or 0
lastGoal = math.max(tonumber(player:GetAttribute("BartenderXPGoal")) or 1, 1)
xpFill.Size = UDim2.new(math.clamp(lastXP / lastGoal, 0, 1), 0, 1, 0)

---------------------------------------------------------------------
-- Display
---------------------------------------------------------------------
local function getLevel(): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local levelValue = leaderstats and leaderstats:FindFirstChild("Level")
	return (levelValue and levelValue.Value) or 1
end

local MAX_LEVEL = 250

local currentText = ""
local function updateDisplay()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local role = "Customer"
	if #zones == 0 then
		-- No zones placed yet (testing phase): everyone is a Bartender.
		-- Once DS_BartenderZone parts exist, the zone decides.
		role = "Bartender"
	elseif root and isInsideZone(root.Position) then
		role = "Bartender"
	end
	local level = getLevel()
	local text
	if level >= MAX_LEVEL then
		-- Max-level reward title — overrides the zone role
		text = string.format("★ Bartender Legend • Lv. %d", level)
	else
		text = string.format("%s • Lv. %d", role, level)
	end
	if text ~= currentText then
		currentText = text
		roleLabel.Text = text
	end
end

refreshZones()
updateDisplay()

local lastZoneScan = os.clock()
local lastRoleCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastRoleCheck >= 0.25 then
		lastRoleCheck = now
		updateDisplay()
	end
	if now - lastZoneScan >= 5 then
		lastZoneScan = now
		refreshZones()
	end
end)
