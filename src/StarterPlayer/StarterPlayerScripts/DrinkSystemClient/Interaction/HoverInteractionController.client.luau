-- HoverInteractionController
-- Handles highlighting, pickup, and pouring.
-- Highlights only real world bottles/glasses/shakers, NEVER the cloned bottle in-hand.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- Global ignore list for cloned bottles created during pouring
_G.DS_IgnoreModels = _G.DS_IgnoreModels or {}

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local ConfigFolder = DrinkSystem:WaitForChild("Config")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
if Settings.EnableHoverInteractionController ~= true then
	return
end
local Network = require(SharedModules:WaitForChild("Network"))
local RecipeRegistry = require(SharedModules:WaitForChild("RecipeRegistry"))
local Packets = Network.Packets

local RequestPickupItem = Packets.RequestPickupItem
local RequestPourIngredient = Packets.RequestPourIngredient
local RequestAddGarnish = Packets.RequestAddGarnish
local GuidanceUpdate = Packets.GuidanceUpdate
local RequestFinalizeMix = Packets.RequestFinalizeMix
local RequestSinkDrink = Packets.RequestSinkDrink

---------------------------------------------------------------------
-- Helper: Is player holding a glass tool?
---------------------------------------------------------------------
local function playerIsHoldingGlass()
	local char = player.Character
	if not char then return false end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then return false end
	if tool:GetAttribute("DS_Drink") == true then return false end

	if tool:GetAttribute("DS_GlassTool") == true then return true end

	local allowedNames = Settings.GlassToolNames or {}
	for _, name in ipairs(allowedNames) do
		if tool.Name == name then return true end
	end
	return false
end

local function playerIsHoldingDrinkTool(): boolean
	local char = player.Character
	if not char then return false end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then return false end
	return tool:GetAttribute("DS_Drink") == true or tool:GetAttribute("DS_DrinkTool") == true
end

---------------------------------------------------------------------
-- Helper: Get root model from a hit part
---------------------------------------------------------------------
local function getRootModel(part)
	if not part then return nil end
	return part:FindFirstAncestorOfClass("Model")
		or part:FindFirstAncestorOfClass("Tool")
		or part
end

---------------------------------------------------------------------
-- Detect interactable type (Bottle / Glass / Shaker / Garnish)
---------------------------------------------------------------------
-- True when the instance is any player's character or inside one.
-- MUST cover ALL players, not just the local one: other players' equipped
-- glasses/shakers otherwise make their whole character detect as an
-- interactable on live servers (invisible in solo Studio testing).
local function isInsideAnyCharacter(inst: Instance): boolean
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		if ch and (inst == ch or inst:IsDescendantOf(ch)) then
			return true
		end
	end
	return false
end

local function detectType(model)
	if not model then return nil end

	-- 1. Ignore ALL player characters completely
	if isInsideAnyCharacter(model) then
		return nil
	end

	-- 2. Ignore cloned bottle(s) in hand
	for _, ignoreModel in ipairs(_G.DS_IgnoreModels) do
		if ignoreModel and (model == ignoreModel or model:IsDescendantOf(ignoreModel)) then
			return nil
		end
	end

	-- Sink — pour out the held mix/drink
	if model:GetAttribute("DS_Sink") == true or CollectionService:HasTag(model, "DS_Sink") then
		return "Sink"
	end

	-- 3. Water overrides everything — anything carrying DS_IngredientName = "Water"
	-- is a sober-up source, no matter what other attributes the model has
	if model:GetAttribute("DS_IngredientName") == "Water" then
		return "Bottle"
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:GetAttribute("DS_IngredientName") == "Water"
			and d:FindFirstAncestorOfClass("Model") == model then
			return "Bottle"
		end
	end

	-- 4. Placed finished drink — check before DS_Glass so it isn't misidentified
	if model:GetAttribute("DS_Drink") == true then
		return "Drink"
	end

	-- 4. Detect via attributes on model
	local attrGlass = model:GetAttribute("DS_Glass")
	local attrGlass2 = model:GetAttribute("DS__Glass")
	if attrGlass == true or attrGlass2 == true or type(attrGlass) == "string" or type(attrGlass2) == "string" then
		return "Glass"
	end

	if model:GetAttribute("DS_Shaker") == true or model:GetAttribute("DS__Shaker") == true then
		return "Shaker"
	end

	if model:GetAttribute("DS_ShakerTool") == true then
		return "Shaker"
	end

	if type(model:GetAttribute("DS_Garnish")) == "string" then
		return "Garnish"
	end

	if model:GetAttribute("DS_Drinks") == true then
		return "Bottle"
	end
	-- DS_IngredientName alone is enough (e.g. bare Water part — no DS_Drinks needed)
	if type(model:GetAttribute("DS_IngredientName")) == "string" then
		return "Bottle"
	end
	if CollectionService:HasTag(model, "DS__Bottle") or CollectionService:HasTag(model, "DS_Bottle") then
		return "Bottle"
	end
	if CollectionService:HasTag(model, "DS__Glass") or CollectionService:HasTag(model, "DS_Glass") then
		return "Glass"
	end
	if CollectionService:HasTag(model, "DS__Shaker") or CollectionService:HasTag(model, "DS_Shaker") then
		return "Shaker"
	end

	if model:IsA("Tool") then
		if model:GetAttribute("DS_ShakerTool") == true then
			return "Shaker"
		end
		if model:GetAttribute("DS_GlassTool") == true then
			return "Glass"
		end
		local shakerName = Settings.ShakerToolName
		if shakerName and model.Name == shakerName then
			return "Shaker"
		end
	end

	-- 4. Detect via attributes on descendants (only parts belonging to THIS
	-- model — nested models are their own interactables; without this guard a
	-- shelf/bar container detects as whatever the first bottle inside it is)
	for _, child in ipairs(model:GetDescendants()) do
		if child:FindFirstAncestorOfClass("Model") ~= model then
			continue
		end
		local garnish = child:GetAttribute("DS_Garnish")
		if type(garnish) == "string" then
			return "Garnish"
		end

		if child:IsA("BasePart") or child:IsA("MeshPart") or child:IsA("UnionOperation") then
			local glass  = child:GetAttribute("DS_Glass")
			local glass2 = child:GetAttribute("DS__Glass")
			local drinks = child:GetAttribute("DS_Drinks")
			local shaker = child:GetAttribute("DS_Shaker")
			local shaker2 = child:GetAttribute("DS__Shaker")
			local shakerTool = child:GetAttribute("DS_ShakerTool")

			if glass == true or glass2 == true or type(glass) == "string" or type(glass2) == "string" then
				return "Glass"
			end
			if drinks == true then
				return "Bottle"
			end
			if type(child:GetAttribute("DS_IngredientName")) == "string" then
				return "Bottle"
			end
			if shaker == true or shaker2 == true then
				return "Shaker"
			end
			if shakerTool == true then
				return "Shaker"
			end
		end
	end

	return nil
end

local function getIngredientName(model: Model): string?
	if model:GetAttribute("DS_Drinks") == true then
		return model:GetAttribute("DS_IngredientName") or model.Name
	end
	local direct = model:GetAttribute("DS_IngredientName")
	if type(direct) == "string" then
		return direct
	end
	for _, d in ipairs(model:GetDescendants()) do
		-- Only parts belonging to THIS model — skip anything inside nested
		-- models. Otherwise a bar/shelf container "inherits" the ingredient
		-- name of the first bottle inside it and the whole shelf highlights.
		if d:FindFirstAncestorOfClass("Model") == model then
			if d:GetAttribute("DS_Drinks") == true then
				return d:GetAttribute("DS_IngredientName") or model.Name
			end
			local dName = d:GetAttribute("DS_IngredientName")
			if type(dName) == "string" then
				return dName
			end
		end
	end
	return nil
end

---------------------------------------------------------------------
-- Guidance state + highlights
---------------------------------------------------------------------
local guidance = {
	RecommendedIngredients = {},  -- full valid set: gates clicks
	DisplayIngredients = {},      -- highlighted subset; empty = highlight all recommended
	RequiredItemType = nil,
	Instruction = "",
}

-- Instruction label: shows the server's guidance text ("Add Coolnag." etc.)
-- just above the hotbar while a glass is held.
local instructionGui = Instance.new("ScreenGui")
instructionGui.Name = "DS_GuideInstruction"
instructionGui.ResetOnSpawn = false
instructionGui.DisplayOrder = 54
instructionGui.Parent = player:WaitForChild("PlayerGui")

local instructionLabel = Instance.new("TextLabel")
instructionLabel.AnchorPoint = Vector2.new(0.5, 1)
instructionLabel.Position = UDim2.new(0.5, 0, 1, -68)
instructionLabel.AutomaticSize = Enum.AutomaticSize.XY
instructionLabel.BackgroundTransparency = 1
instructionLabel.Font = Enum.Font.Montserrat
instructionLabel.Text = ""
instructionLabel.TextSize = 17
instructionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
instructionLabel.TextTransparency = 0.1
instructionLabel.Visible = false
instructionLabel.Parent = instructionGui

local instructionStroke = Instance.new("UIStroke")
instructionStroke.Color = Color3.fromRGB(0, 0, 0)
instructionStroke.Thickness = 1.2
instructionStroke.Parent = instructionLabel

-- Live mix timer: slim bar above the instruction text while mixing. Drains
-- over MixTimeOkSeconds from the FIRST pour — green (full speed points) →
-- amber (partial) → red (too slow). Pure pressure, no numbers, no breakdown.
local timerBack = Instance.new("Frame")
timerBack.AnchorPoint = Vector2.new(0.5, 1)
timerBack.Position = UDim2.new(0.5, 0, 1, -94)
timerBack.Size = UDim2.new(0, 180, 0, 7)
timerBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
timerBack.BackgroundTransparency = 0.35
timerBack.BorderSizePixel = 0
timerBack.Visible = false
timerBack.Parent = instructionGui
local timerBackCorner = Instance.new("UICorner")
timerBackCorner.CornerRadius = UDim.new(1, 0)
timerBackCorner.Parent = timerBack

local timerFill = Instance.new("Frame")
timerFill.AnchorPoint = Vector2.new(0, 0.5)
timerFill.Position = UDim2.new(0, 0, 0.5, 0)
timerFill.Size = UDim2.new(1, 0, 1, 0)
timerFill.BackgroundColor3 = Color3.fromRGB(110, 220, 110)
timerFill.BorderSizePixel = 0
timerFill.Parent = timerBack
local timerFillCorner = Instance.new("UICorner")
timerFillCorner.CornerRadius = UDim.new(1, 0)
timerFillCorner.Parent = timerFill

-- Label so the bar explains itself: "Speed Bonus 3.2s"
local timerLabel = Instance.new("TextLabel")
timerLabel.AnchorPoint = Vector2.new(0.5, 1)
timerLabel.Position = UDim2.new(0.5, 0, 0, -2)
timerLabel.AutomaticSize = Enum.AutomaticSize.XY
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.Montserrat
timerLabel.Text = ""
timerLabel.TextSize = 13
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.TextTransparency = 0.15
timerLabel.Parent = timerBack
local timerLabelStroke = Instance.new("UIStroke")
timerLabelStroke.Color = Color3.fromRGB(0, 0, 0)
timerLabelStroke.Thickness = 1
timerLabelStroke.Parent = timerLabel

local TIMER_FAST = Settings.MixTimeFastSeconds or 5
local TIMER_OK   = Settings.MixTimeOkSeconds or 10

local function updateMixTimer()
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	local mixStart = tool and tool:GetAttribute("DS_MixStart")
	local hasMix = tool
		and tool:GetAttribute("DS_Drink") ~= true
		and typeof(mixStart) == "number"
		and (tool:GetAttribute("DS_IngredientListCsv") or "") ~= ""

	if not hasMix then
		timerBack.Visible = false
		return
	end

	local elapsed = workspace:GetServerTimeNow() - mixStart
	local remainingFrac = math.clamp(1 - elapsed / TIMER_OK, 0, 1)
	timerFill.Size = UDim2.new(remainingFrac, 0, 1, 0)
	if elapsed <= TIMER_FAST then
		timerFill.BackgroundColor3 = Color3.fromRGB(110, 220, 110)
		timerLabel.Text = string.format("Speed Bonus %.1fs", math.max(TIMER_OK - elapsed, 0))
		timerLabel.TextColor3 = Color3.fromRGB(180, 255, 180)
	elseif elapsed <= TIMER_OK then
		timerFill.BackgroundColor3 = Color3.fromRGB(235, 185, 60)
		timerLabel.Text = string.format("Speed Bonus %.1fs", math.max(TIMER_OK - elapsed, 0))
		timerLabel.TextColor3 = Color3.fromRGB(255, 225, 150)
	else
		timerFill.BackgroundColor3 = Color3.fromRGB(220, 70, 60)
		timerFill.Size = UDim2.new(1, 0, 1, 0)
		timerLabel.Text = "Too slow — no speed bonus"
		timerLabel.TextColor3 = Color3.fromRGB(255, 160, 150)
	end
	timerBack.Visible = true
end

local function updateInstructionLabel()
	local text = guidance.Instruction or ""
	if text ~= "" and playerIsHoldingGlass() then
		instructionLabel.Text = text
		instructionLabel.Visible = true
	else
		instructionLabel.Visible = false
	end
end

local guidanceTargets = {
	Recommended = {},
	Required = nil,
}

-- Click gate: full valid set
local function isRecommended(model: Model): boolean
	local ing = getIngredientName(model)
	if not ing then return false end
	for _, name in ipairs(guidance.RecommendedIngredients or {}) do
		if name == ing then
			return true
		end
	end
	return false
end

local GUIDANCE_MAX_HIGHLIGHT_DIST = 80 -- studs

-- Set of ingredient names to HIGHLIGHT (display subset if present, else all valid)
local function getDisplayNameSet(): { [string]: boolean }
	local list = guidance.DisplayIngredients or {}
	if #list == 0 then
		list = guidance.RecommendedIngredients or {}
	end
	local set = {}
	for _, name in ipairs(list) do
		set[name] = true
	end
	return set
end

-- Collect highlightable instances for guidance. Identity must be CARRIED by
-- the instance itself:
--   * Model with DS_Drinks / DS_IngredientName on the model → highlight model
--   * BasePart with DS_IngredientName / DS_Drinks (e.g. a soda tap sitting
--     directly inside a bar/shelf model) → highlight just that part
-- Container models NEVER inherit identity from what's inside them — that was
-- lighting up entire shelves whenever one bottle inside matched.
local function collectGuidanceHighlightTargets(nameSet: { [string]: boolean }, maxCount: number): { Instance }
	local char = player.Character
	if not char then return {} end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return {} end

	local candidates = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		local matchName: string? = nil
		local distPart: BasePart? = nil

		if inst:IsA("Model") and not Players:GetPlayerFromCharacter(inst) then
			if inst:GetAttribute("DS_Drinks") == true then
				matchName = inst:GetAttribute("DS_IngredientName") or inst.Name
			else
				local direct = inst:GetAttribute("DS_IngredientName")
				if type(direct) == "string" then
					matchName = direct
				end
			end
			distPart = inst:FindFirstChildWhichIsA("BasePart", true)
		elseif inst:IsA("BasePart") and not isInsideAnyCharacter(inst) then
			local partName = inst:GetAttribute("DS_IngredientName")
			local isDrinkPart = inst:GetAttribute("DS_Drinks") == true
			if type(partName) == "string" or isDrinkPart then
				-- If the part's own model is a proper bottle (carries identity
				-- itself), the model branch already covers it — skip the part.
				local owner = inst:FindFirstAncestorOfClass("Model")
				local ownerIsBottle = owner ~= nil and (
					owner:GetAttribute("DS_Drinks") == true
					or type(owner:GetAttribute("DS_IngredientName")) == "string"
				)
				if not ownerIsBottle then
					matchName = type(partName) == "string" and partName or nil
					if not matchName and isDrinkPart and owner then
						matchName = owner.Name
					end
					distPart = inst
				end
			end
		end

		if matchName and nameSet[matchName] and distPart then
			local dist = (distPart.Position - root.Position).Magnitude
			if dist <= GUIDANCE_MAX_HIGHLIGHT_DIST then
				table.insert(candidates, { Inst = inst, Dist = dist })
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.Dist < b.Dist
	end)

	local out = {}
	for i = 1, math.min(maxCount, #candidates) do
		table.insert(out, candidates[i].Inst)
	end
	return out
end

local function isRequired(model: Model): boolean
	local itemType = detectType(model)
	if not itemType then return false end
	return guidance.RequiredItemType == itemType
end

local function collectNearestModels(predicate, maxCount: number): {Model}
	local char = player.Character
	if not char then return {} end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return {} end

	local candidates = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and not Players:GetPlayerFromCharacter(inst) and predicate(inst) then
			local part = inst:FindFirstChildWhichIsA("BasePart", true)
			if part then
				local dist = (part.Position - root.Position).Magnitude
				if dist <= 80 then
					table.insert(candidates, { Model = inst, Dist = dist })
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.Dist < b.Dist
	end)

	local out = {}
	for i = 1, math.min(maxCount, #candidates) do
		table.insert(out, candidates[i].Model)
	end
	return out
end

local function findNearestModel(predicate)
	local list = collectNearestModels(predicate, 1)
	return list[1]
end

local GUIDANCE_MAX_RECOMMENDED_HIGHLIGHTS = 30

local requiredGuidanceHighlight = Instance.new("Highlight")
requiredGuidanceHighlight.Enabled = false
requiredGuidanceHighlight.FillTransparency = 1
requiredGuidanceHighlight.OutlineTransparency = 0
requiredGuidanceHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
requiredGuidanceHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
requiredGuidanceHighlight.Parent = workspace

local recommendedGuidanceHighlights = {}
for i = 1, GUIDANCE_MAX_RECOMMENDED_HIGHLIGHTS do
	local h = Instance.new("Highlight")
	h.Name = "DS_GuidanceRecommended_" .. tostring(i)
	h.Enabled = false
	h.FillTransparency = 1
	h.OutlineTransparency = 0
	h.OutlineColor = Color3.fromRGB(255, 255, 255)
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = workspace
	table.insert(recommendedGuidanceHighlights, h)
end

local function applyGuidanceHighlights()
	for i, h in ipairs(recommendedGuidanceHighlights) do
		local model = guidanceTargets.Recommended[i]
		if model and model:IsDescendantOf(workspace) then
			h.Adornee = model
			h.Enabled = true
		else
			h.Adornee = nil
			h.Enabled = false
		end
	end

	local requiredModel = guidanceTargets.Required
	if requiredModel and requiredModel:IsDescendantOf(workspace) then
		requiredGuidanceHighlight.Adornee = requiredModel
		requiredGuidanceHighlight.Enabled = true
	else
		requiredGuidanceHighlight.Adornee = nil
		requiredGuidanceHighlight.Enabled = false
	end
end

-- Clears only the display (highlights off). Keeps guidance data so it
-- shows immediately once the glass finishes replicating to the character.
local function clearGuidanceDisplay()
	guidanceTargets.Recommended = {}
	guidanceTargets.Required = nil
	applyGuidanceHighlights()
	instructionLabel.Visible = false
end

-- Clears both data and display. Used on unequip so stale data doesn't linger.
local function resetGuidance()
	guidance.RecommendedIngredients = {}
	guidance.DisplayIngredients = {}
	guidance.RequiredItemType = nil
	guidance.Instruction = ""
	clearGuidanceDisplay()
end

local function refreshGuidanceTargets()
	if not playerIsHoldingGlass() then
		clearGuidanceDisplay()
		return
	end
	guidanceTargets.Recommended = collectGuidanceHighlightTargets(getDisplayNameSet(), GUIDANCE_MAX_RECOMMENDED_HIGHLIGHTS)
	guidanceTargets.Required = findNearestModel(isRequired)
	applyGuidanceHighlights()
	updateInstructionLabel()
end

GuidanceUpdate.listen(function(payload)
	-- Always store the data — server only sends this when the player has a glass.
	-- Don't gate on playerIsHoldingGlass() here: the packet can arrive before the
	-- tool fully replicates to the character, causing a dropped update and no guide.
	-- The 0.25s refresh loop handles showing/hiding based on glass state.
	guidance.RecommendedIngredients = payload.RecommendedIngredients or {}
	guidance.DisplayIngredients = payload.DisplayIngredients or {}
	guidance.RequiredItemType = payload.RequiredItemType
	guidance.Instruction = payload.Instruction or ""
	refreshGuidanceTargets()
end)

local function isGuidedClickAllowed(model: Model, itemType: string): boolean
	-- Placed drinks, glasses, shakers, and the trash are always clickable —
	-- guidance never blocks them
	if itemType == "Drink" or itemType == "Glass" or itemType == "Shaker" or itemType == "Sink" then return true end

	-- Water is drinkable any time — guidance never blocks it
	if itemType == "Bottle" and getIngredientName(model) == "Water" then return true end

	if guidance.RequiredItemType and itemType ~= guidance.RequiredItemType then
		return false
	end

	-- Bottles: clickable iff the pour is recipe-valid (count-aware, SECRET
	-- recipes included) — the exact rule the server enforces in onPour.
	-- Highlights only show non-secret suggestions, so secret combos like a
	-- second Vodqa are clickable without ever glowing.
	if itemType == "Bottle" then
		local ing = getIngredientName(model)
		if not ing then return false end
		local mixList = {}
		local char = player.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		local csv = tool and tool:GetAttribute("DS_IngredientListCsv")
		if type(csv) == "string" and csv ~= "" then
			for token in string.gmatch(csv, "([^,]+)") do
				table.insert(mixList, token)
			end
		end
		return RecipeRegistry.canAddIngredient(mixList, ing)
	end

	return true
end

---------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------
local tooltipGui = Instance.new("ScreenGui")
tooltipGui.Name = "DS_HoverTooltip"
tooltipGui.ResetOnSpawn = false
tooltipGui.IgnoreGuiInset = true
tooltipGui.DisplayOrder = 50
tooltipGui.Parent = player:WaitForChild("PlayerGui")

local tooltipFrame = Instance.new("Frame")
tooltipFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
tooltipFrame.BackgroundTransparency = 0.3
tooltipFrame.BorderSizePixel = 0
tooltipFrame.AutomaticSize = Enum.AutomaticSize.XY
tooltipFrame.Visible = false
tooltipFrame.Parent = tooltipGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 6)
tooltipCorner.Parent = tooltipFrame

local tooltipPadding = Instance.new("UIPadding")
tooltipPadding.PaddingLeft   = UDim.new(0, 8)
tooltipPadding.PaddingRight  = UDim.new(0, 8)
tooltipPadding.PaddingTop    = UDim.new(0, 4)
tooltipPadding.PaddingBottom = UDim.new(0, 4)
tooltipPadding.Parent = tooltipFrame

local tooltipLabel = Instance.new("TextLabel")
tooltipLabel.BackgroundTransparency = 1
tooltipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
tooltipLabel.TextSize = 14
tooltipLabel.Font = Enum.Font.GothamMedium
tooltipLabel.AutomaticSize = Enum.AutomaticSize.XY
tooltipLabel.Text = ""
tooltipLabel.Parent = tooltipFrame

local function setTooltip(text: string?)
	if text and text ~= "" then
		tooltipLabel.Text = text
		tooltipFrame.Visible = true
	else
		tooltipFrame.Visible = false
	end
end

local function updateTooltipPosition()
	local mouse = UIS:GetMouseLocation()
	tooltipFrame.Position = UDim2.new(0, mouse.X + 16, 0, mouse.Y + 8)
end

---------------------------------------------------------------------
-- Highlight Setup — parent to Workspace, NOT to the model
---------------------------------------------------------------------
local hoverHighlight = Instance.new("Highlight")
hoverHighlight.Enabled = false
hoverHighlight.FillTransparency = 0.5
hoverHighlight.OutlineTransparency = 0
hoverHighlight.FillColor = Color3.fromRGB(255, 255, 0)
hoverHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
hoverHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
hoverHighlight.Parent = workspace  -- ✅ 3D object, so keep it in Workspace

local currentModel = nil
local lastGuidanceRefreshAt = 0

---------------------------------------------------------------------
-- Raycast ignoring player's character
---------------------------------------------------------------------
local function getRaycastTarget()
	local char = player.Character
	if not char then return nil end

	local cam = workspace.CurrentCamera
	if not cam then return nil end

	local mousePos = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	return result and result.Instance or nil
end

---------------------------------------------------------------------
-- Highlight logic
---------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if now - lastGuidanceRefreshAt >= 0.25 then
		lastGuidanceRefreshAt = now
		refreshGuidanceTargets()
	end
	updateMixTimer()

	local target = getRaycastTarget()

	local hoveredModel = target and getRootModel(target) or nil
	local hoverType = hoveredModel and detectType(hoveredModel) or nil

	local function applyHighlight(model)
		if not model then
			hoverHighlight.Enabled = false
			currentModel = nil
			return
		end

		hoverHighlight.FillColor = Color3.fromRGB(255, 255, 0)
		hoverHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)

		if currentModel ~= model then
			currentModel = model
			hoverHighlight.Adornee = model
		end
		hoverHighlight.Enabled = true
	end

	if hoveredModel and hoverType then
		applyHighlight(hoveredModel)
		local label
		if hoverType == "Drink" then
			label = hoveredModel:GetAttribute("DS_DrinkName") or hoveredModel.Name
		elseif hoverType == "Bottle" then
			label = getIngredientName(hoveredModel) or hoveredModel.Name
		elseif hoverType == "Glass" then
			label = hoveredModel:GetAttribute("DS_Glass") or hoveredModel.Name
		elseif hoverType == "Shaker" then
			label = "Shaker"
		elseif hoverType == "Garnish" then
			label = hoveredModel:GetAttribute("DS_Garnish") or hoveredModel.Name
		elseif hoverType == "Sink" then
			label = "Dispose"
		end
		setTooltip(label)
		updateTooltipPosition()
	else
		hoverHighlight.Enabled = false
		currentModel = nil
		setTooltip(nil)
	end
end)

---------------------------------------------------------------------
-- Interaction on click
---------------------------------------------------------------------
local function tryInteract()
	if not currentModel then return end

	local t = detectType(currentModel)
	if not t then return end
	if not isGuidedClickAllowed(currentModel, t) then
		return
	end

	-- Do not consume click input while the player is holding a drink
	-- unless targeting a garnish station, another drink, Water, or the Sink.
	if t ~= "Garnish" and t ~= "Drink" and t ~= "Sink" and playerIsHoldingDrinkTool() then
		if not (t == "Bottle" and getIngredientName(currentModel) == "Water") then
			return
		end
	end

	-- Bottle pour
	if t == "Bottle" then
		-- Water is drunk directly from the source — no glass needed.
		-- Server replies with StartBottlePour (pour anim, no bottle clone).
		if getIngredientName(currentModel) == "Water" then
			RequestPourIngredient.send({ BottleModel = currentModel })
			return
		end
		if not playerIsHoldingGlass() then
			return
		end
		RequestPourIngredient.send({ BottleModel = currentModel })
		return
	end

	-- Sink: pour out the held mix/drink (glass resets to clean)
	if t == "Sink" then
		RequestSinkDrink.send({ Model = currentModel })
		return
	end

	if t == "Garnish" then
		if not playerIsHoldingDrinkTool() then
			return
		end
		RequestAddGarnish.send({ Model = currentModel })
		return
	end

	-- Shaker: pick up then finalize mix
	if t == "Shaker" then
		RequestPickupItem.send({ Model = currentModel })
		task.delay(0.12, function()
			RequestFinalizeMix.send({})
		end)
		return
	end

	-- Glass pickup
	if t == "Glass" then
		RequestPickupItem.send({ Model = currentModel })
		return
	end

	-- Finished drink pickup
	if t == "Drink" then
		RequestPickupItem.send({ Model = currentModel })
		return
	end
end
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tryInteract()
	end
end)

local equipDebounce: thread? = nil

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if not child:IsA("Tool") then return end
		if child:GetAttribute("DS_Drink") == true then return end
		local isGlass = child:GetAttribute("DS_GlassTool") == true
		if not isGlass then
			local allowedNames = Settings.GlassToolNames or {}
			for _, name in ipairs(allowedNames) do
				if child.Name == name then isGlass = true break end
			end
		end
		if not isGlass then return end

		-- Debounce: cancel any pending refresh so rapid switching settles first
		if equipDebounce then task.cancel(equipDebounce) end
		equipDebounce = task.delay(0.2, function()
			equipDebounce = nil
			refreshGuidanceTargets()
		end)
	end)

	character.ChildRemoved:Connect(function(child)
		if not child:IsA("Tool") then return end
		if equipDebounce then task.cancel(equipDebounce) equipDebounce = nil end
		if not playerIsHoldingGlass() then
			resetGuidance()
		end
	end)
end

if player.Character then watchCharacter(player.Character) end
player.CharacterAdded:Connect(function(character)
	-- Respawn = fresh join: no stale guidance data or highlights
	resetGuidance()
	watchCharacter(character)
end)
