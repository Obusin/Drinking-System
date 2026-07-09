-- Sin Obu: one gulp of triple Vodqa → forced 60s ragdoll (can't stand).
-- Fires on every sip (Sin Obu has Sips = 1, so exactly once per drink).

local SinObu = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
-- Services: { DrinkEffectsService, Packets, Settings, Recipes }
function SinObu.OnSip(ctx)
	local Services = ctx.Services

	-- Small beat so the sip animation finishes before the fall
	task.delay(0.8, function()
		Services.DrinkEffectsService.forceCollapse(ctx.Player, 60)
	end)
end

return SinObu
