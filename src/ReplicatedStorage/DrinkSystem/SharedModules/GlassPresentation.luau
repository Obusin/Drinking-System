local GlassPresentation = {}

local VISIBLE_TRANSPARENCY = 0
local HIDDEN_TRANSPARENCY = 1

local STAGE_NAMES = {
	[1] = { "1", "Stage1" },
	[2] = { "2", "Stage2" },
	[3] = { "3", "Stage3" },
}

local GARNISH_NAMES = {
	"Cherry",
	"Lemon",
	"Lime",
	"Orange",
	"Ice",
	"Shade Umbrella",
	"ShadeUmbrella",
}

-- Roblox Highlights outline fully-transparent parts, so hiding via
-- Transparency=1 alone leaves hidden garnishes/stages glowing inside hover
-- and guidance outlines. Hidden parts are ALSO shrunk to near-zero (original
-- size stored in attributes and restored on reveal — welds keep positions).
local HIDDEN_SIZE = Vector3.new(0.01, 0.01, 0.01)

local function applyPartVisibility(part: BasePart, transparency: number)
	part.Transparency = transparency
	if transparency >= 1 then
		if part:GetAttribute("DS_OrigSize") == nil then
			part:SetAttribute("DS_OrigSize", part.Size)
		end
		part.Size = HIDDEN_SIZE
	else
		local orig = part:GetAttribute("DS_OrigSize")
		if typeof(orig) == "Vector3" then
			part.Size = orig
		end
	end
	-- SpecialMesh scale renders independently of part size — shrink it too
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		if transparency >= 1 then
			if mesh:GetAttribute("DS_OrigScale") == nil then
				mesh:SetAttribute("DS_OrigScale", mesh.Scale)
			end
			mesh.Scale = HIDDEN_SIZE
		else
			local origScale = mesh:GetAttribute("DS_OrigScale")
			if typeof(origScale) == "Vector3" then
				mesh.Scale = origScale
			end
		end
	end
end

local function setVisualTransparency(instance: Instance, transparency: number)
	if instance:IsA("BasePart") then
		applyPartVisibility(instance, transparency)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			applyPartVisibility(descendant, transparency)
		end
	end
end

local function setVisualColor(instance: Instance, color: Color3)
	if instance:IsA("BasePart") then
		instance.Color = color
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

local function findByNames(container: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local match = container:FindFirstChild(name, true)
		if match then
			return match
		end
	end
	return nil
end

local function normalizeGarnishName(name: string): string
	return string.gsub(name, "%s+", "")
end

local function collectKnownGarnishes(container: Instance): { [string]: Instance }
	local garnishes = {}
	for _, garnishName in ipairs(GARNISH_NAMES) do
		local match = container:FindFirstChild(garnishName, true)
		if match then
			garnishes[normalizeGarnishName(garnishName)] = match
		end
	end
	return garnishes
end

function GlassPresentation.setStage(container: Instance, stage: number?)
	for stageIndex, stageNames in pairs(STAGE_NAMES) do
		local stageInstance = findByNames(container, stageNames)
		if stageInstance then
			local transparency = if stage ~= nil and stageIndex == stage then VISIBLE_TRANSPARENCY else HIDDEN_TRANSPARENCY
			setVisualTransparency(stageInstance, transparency)
		end
	end

	local drinkPart = container:FindFirstChild("DrinkPart", true)
	if drinkPart and drinkPart:IsA("BasePart") then
		applyPartVisibility(drinkPart, if stage ~= nil and stage > 0 then 0.05 else HIDDEN_TRANSPARENCY)
	end

	local liquidPart = container:FindFirstChild("LiquidPart", true)
	if liquidPart and liquidPart:IsA("BasePart") then
		applyPartVisibility(liquidPart, if stage ~= nil and stage > 0 then 0.1 else HIDDEN_TRANSPARENCY)
	end
end

-- Override the transparency of the visible liquid (stage parts + drink/liquid
-- parts). Used for see-through drinks like Water.
function GlassPresentation.setLiquidTransparency(container: Instance, transparency: number)
	for _, stageNames in pairs(STAGE_NAMES) do
		local stageInstance = findByNames(container, stageNames)
		if stageInstance then
			for _, d in ipairs(stageInstance:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 0.9 then
					d.Transparency = transparency
				end
			end
			if stageInstance:IsA("BasePart") and stageInstance.Transparency < 0.9 then
				stageInstance.Transparency = transparency
			end
		end
	end
	local drinkPart = container:FindFirstChild("DrinkPart", true)
	if drinkPart and drinkPart:IsA("BasePart") and drinkPart.Transparency < 0.9 then
		drinkPart.Transparency = transparency
	end
	local liquidPart = container:FindFirstChild("LiquidPart", true)
	if liquidPart and liquidPart:IsA("BasePart") and liquidPart.Transparency < 0.9 then
		liquidPart.Transparency = transparency
	end
end

function GlassPresentation.setFillColor(container: Instance, color: Color3?)
	if typeof(color) ~= "Color3" then
		return
	end

	for _, stageNames in pairs(STAGE_NAMES) do
		local stageInstance = findByNames(container, stageNames)
		if stageInstance then
			setVisualColor(stageInstance, color)
		end
	end

	local drinkPart = container:FindFirstChild("DrinkPart", true)
	if drinkPart and drinkPart:IsA("BasePart") then
		drinkPart.Color = color
	end

	local liquidPart = container:FindFirstChild("LiquidPart", true)
	if liquidPart and liquidPart:IsA("BasePart") then
		liquidPart.Color = color
	end
end

function GlassPresentation.setGarnishes(container: Instance, garnishList: { string }?)
	local active = {}
	for _, garnishName in ipairs(garnishList or {}) do
		active[normalizeGarnishName(garnishName)] = true
	end

	local garnishes = collectKnownGarnishes(container)
	for garnishName, garnishInstance in pairs(garnishes) do
		local transparency = if active[garnishName] then VISIBLE_TRANSPARENCY else HIDDEN_TRANSPARENCY
		setVisualTransparency(garnishInstance, transparency)
	end
end

function GlassPresentation.reset(container: Instance)
	GlassPresentation.setStage(container, nil)
	GlassPresentation.setGarnishes(container, {})
end

function GlassPresentation.applyFillState(container: Instance, ingredientCount: number, color: Color3?)
	local stage = math.clamp(ingredientCount, 0, 3)
	GlassPresentation.setFillColor(container, color)
	GlassPresentation.setStage(container, if stage > 0 then stage else nil)
	GlassPresentation.setGarnishes(container, {})
end

function GlassPresentation.applyFinalPresentation(container: Instance, ingredientCount: number, color: Color3?, garnishList: { string }?)
	local stage = math.clamp(ingredientCount, 1, 3)
	GlassPresentation.setFillColor(container, color)
	GlassPresentation.setStage(container, stage)
	GlassPresentation.setGarnishes(container, garnishList or {})
end

return GlassPresentation
