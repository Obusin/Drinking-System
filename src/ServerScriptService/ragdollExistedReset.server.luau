local ServerStorage = game:GetService("ServerStorage")
local RagdollCounterSys = ServerStorage.RagdollCounterSys

local diedCounted = false
local function checkZero()
	if RagdollCounterSys.ragdollsExisted.Value ~= 0 and diedCounted == false then
		diedCounted = true
		repeat
			RagdollCounterSys.ragdollsExisted.Value -= 1
			task.wait(2)
		until RagdollCounterSys.ragdollsExisted.Value <= 0 
		task.wait(120)
		diedCounted = false
	end
end	

if RagdollCounterSys.ragdollsLdEnable.Value == true  then
	RagdollCounterSys.ragdollsExisted:GetPropertyChangedSignal("Value"):Connect(checkZero)
end

--For use incase ragdollsExisted cannot get to 0. For use with LdEnable.