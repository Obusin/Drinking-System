--[[
	Device — "is this a touch layout?", answered in one place.

	Every HUD that has to move out of a thumb's way needs this, and the
	answer has to be identical for all of them: if TouchHud thinks it's
	mobile and SpeedHud doesn't, the drift button lands on top of the
	speedometer. Which is exactly what happened.

	A KEYBOARD DISQUALIFIES, A TOUCHSCREEN DOESN'T QUALIFY
	-----------------------------------------------------
	Deliberately that way round. Plenty of laptops have touchscreens and
	their owners are using the keyboard; a phone has no keyboard. Testing
	`TouchEnabled` alone puts thumb controls on a desktop.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return Device
