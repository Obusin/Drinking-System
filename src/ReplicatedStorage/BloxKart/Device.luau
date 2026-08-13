--[[
	Device — "is this a touch layout?", answered in one place.

	Every HUD that has to move out of a thumb's way needs this, and the
	answer has to be identical for all of them: if TouchHud thinks it's
	mobile and SpeedHud doesn't, the drift button lands on top of the
	speedometer. Which is exactly what happened.

TOUCH OWNS THE COMPOSITION
--------------------------
Roblox's mobile emulator reports both TouchEnabled and KeyboardEnabled.
Treating a keyboard as an automatic desktop verdict therefore left the mobile
HUD in its large desktop layout exactly where a phone needs compact controls.
An actual touch-capable laptop can opt out with Touch.Mode = "never"; a touch
device otherwise gets the touch-safe composition.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config"))

local Device = {}

-- True when the on-screen pad should be used and every HUD should lay
-- itself out for thumbs. `Config.Touch.Mode` can force it either way,
-- which is how you check the mobile layout on a PC.
function Device.touchLayout(): boolean
	local mode = Config.Touch.Mode
	if mode == "always" then
		return true
	end
	if mode == "never" then
		return false
	end
	if RunService:IsStudio() and Config.Touch.StudioPreview then
		return true
	end
	return UserInputService.TouchEnabled
end

return Device
