local ServerStorage = game:GetService("ServerStorage")
local RagdollCounterSys = ServerStorage.RagdollCounterSys

local diedCounted = false
local function decay()
	if RagdollCounterSys.charactersDied.Value > 0 and diedCounted == false then
		diedCounted = true
		repeat
			task.wait(RagdollCounterSys.characterDiedDecay.Value)
			RagdollCounterSys.charactersDied.Value -= 1
		until RagdollCounterSys.charactersDied.Value <= 0 
		diedCounted = false
	end
end	

RagdollCounterSys.charactersDied:GetPropertyChangedSignal("Value"):Connect(decay)

--Removes characterDied at a reasonable rate to reduce from characterDiedMax to continue operation