-- DrinkSystemServerMain (Legacy Wrapper)
-- Preserved as an entrypoint that forwards to the SSA controller.

local controller = require(script.Parent:WaitForChild("DrinkSystemController"))
controller.init()
