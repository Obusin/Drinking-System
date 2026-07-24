-- Relapse Drink: Fonador x4 → movement stays completely free the whole
-- time (no WalkSpeed/state lock). RelapseService handles the actual
-- idle-triggered stumble loop for a bounded duration.

local RelapseDrink = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function RelapseDrink.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_RelapseTriggered") == true then
			return
		end
		tool:SetAttribute("DS_RelapseTriggered", true)
	end

	local Services = ctx.Services
	if not Services.RelapseService then
		return
	end
	Services.RelapseService.Start(ctx.Player, Services.Settings.RelapseEffectDuration)
end

return RelapseDrink
