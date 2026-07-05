local uis = game:GetService("UserInputService")
local humanoid = script.Parent:WaitForChild("Humanoid")


uis.InputBegan:Connect(function(key, pressed)
	if key.KeyCode == Enum.KeyCode.L and not pressed then
		humanoid.Health = 0
	end
end)

