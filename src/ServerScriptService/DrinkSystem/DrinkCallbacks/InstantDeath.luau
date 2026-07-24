-- Instant Death secrets (NOX Society, Skyline): a short beat after the sip
-- so the animation reads, then straight to 0 HP. Respawn is handled by the
-- game's normal death/respawn flow — nothing special needed here.

local InstantDeath = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function InstantDeath.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_InstantDeathTriggered") == true then
			return
		end
		tool:SetAttribute("DS_InstantDeathTriggered", true)
	end

	local char = ctx.Player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	task.delay(0.8, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
end

return InstantDeath
