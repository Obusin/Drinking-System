local Utility = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local IngredientRegistry = require(SharedModules:WaitForChild("IngredientRegistry"))

local function toColor3(value)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local entry = IngredientRegistry.get(value)
		if entry and typeof(entry.Color) == "Color3" then
			return entry.Color
		end
	end
	return nil
end

function Utility.averageColors(values)
	if type(values) ~= "table" or #values == 0 then
		return Color3.fromRGB(255, 255, 255)
	end

	local r, g, b = 0, 0, 0
	local count = 0
	for _, value in ipairs(values) do
		local c = toColor3(value)
		if c then
			r += c.R
			g += c.G
			b += c.B
			count += 1
		end
	end

	if count <= 0 then
		return Color3.fromRGB(255, 255, 255)
	end

	return Color3.new(r / count, g / count, b / count)
end

return Utility
