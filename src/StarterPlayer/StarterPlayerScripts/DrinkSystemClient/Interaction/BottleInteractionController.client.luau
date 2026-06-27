-- StarterPlayerScripts/DrinkSystemClient/BottleInteractionController

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local DrinkSystemFolder = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystemFolder:WaitForChild("SharedModules")
local ConfigFolder = DrinkSystemFolder:WaitForChild("Config")

local Network = require(SharedModules:WaitForChild("Network"))
local Settings = require(ConfigFolder:WaitForChild("Settings"))
local Packets = Network.Packets

local RequestPourIngredient = Packets.RequestPourIngredient

if Settings.EnableBottleInteractionController ~= true then
	return
end

local function findBottleModelFromTarget(target: Instance?): Model?
	if not target then return nil end
	-- We expect DS_Drinks = true on a Model or one of its children
	local model = target:FindFirstAncestorOfClass("Model")
	if not model then return nil end
	if model:GetAttribute("DS_Drinks") == true then
		return model
	end
	return nil
end

local function onClick()
	local target = mouse.Target
	if not target then return end

	local bottleModel = findBottleModelFromTarget(target)
	if not bottleModel then return end

	-- Fire the model to the server; server will resolve ingredient based on attributes/name.
	RequestPourIngredient.send({ BottleModel = bottleModel })
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		onClick()
	end
end)
