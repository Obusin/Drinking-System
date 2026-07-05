-- GlassClass.lua
-- One Glass Object = One Drink

local GlassClass = {}
GlassClass.__index = GlassClass

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local GlassPresentation = require(SharedModules:WaitForChild("GlassPresentation"))

function GlassClass.new(toolInstance: Tool)
	local self = setmetatable({}, GlassClass)

	self.Tool = toolInstance
	self.DrinkPart = toolInstance:FindFirstChild("DrinkPart", true)

	self.FillStep = 0
	self.MaxIngredients = 4
	self.Color = Color3.new(1, 1, 1)

	if self.DrinkPart and self.DrinkPart:IsA("BasePart") then
		self.BaseSize = self.DrinkPart.Size
		self.BaseCF = self.DrinkPart.CFrame
	end

	self.Ingredients = {}

	local storedStage = toolInstance:GetAttribute("DS_FillStage")
	if typeof(storedStage) == "number" and storedStage > 0 then
		self.FillStep = math.clamp(storedStage, 0, self.MaxIngredients)
	end

	local storedColor = toolInstance:GetAttribute("DS_Color")
	if typeof(storedColor) == "Color3" then
		self.Color = storedColor
	end

	local ingredientsCsv = toolInstance:GetAttribute("DS_IngredientListCsv")
	if type(ingredientsCsv) == "string" and ingredientsCsv ~= "" then
		for token in string.gmatch(ingredientsCsv, "([^,]+)") do
			table.insert(self.Ingredients, token)
		end
	end

	if self.FillStep > 0 then
		GlassPresentation.applyFillState(self.Tool, self.FillStep, self.Color)
	else
		GlassPresentation.reset(self.Tool)
	end

	return self
end

local function blendColor(oldColor: Color3, newColor: Color3, step: number)
	if step <= 1 then return newColor end

	return Color3.new(
		(oldColor.R * (step - 1) + newColor.R) / step,
		(oldColor.G * (step - 1) + newColor.G) / step,
		(oldColor.B * (step - 1) + newColor.B) / step
	)
end

function GlassClass:ApplyIngredient(color: Color3, tweenTime)
	self.FillStep += 1
	if self.FillStep > self.MaxIngredients then
		self.FillStep = self.MaxIngredients
	end

	self.Color = blendColor(self.Color, color, self.FillStep)

	table.insert(self.Ingredients, color)
	GlassPresentation.applyFillState(self.Tool, self.FillStep, self.Color)
end

function GlassClass:Reset()
	self.FillStep = 0
	self.Ingredients = {}
	self.Color = Color3.new(1, 1, 1)

	if self.DrinkPart and self.DrinkPart:IsA("BasePart") and self.BaseSize and self.BaseCF then
		self.DrinkPart.Size = self.BaseSize
		self.DrinkPart.CFrame = self.BaseCF
		self.DrinkPart.Transparency = 1
	end

	GlassPresentation.reset(self.Tool)
end

return GlassClass
