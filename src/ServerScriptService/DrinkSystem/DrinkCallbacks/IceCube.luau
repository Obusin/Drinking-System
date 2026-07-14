-- IceCube: garnish-gated Water variant. Pour a plain Water, add "Ice" as a
-- garnish, then sip it → the drinker gets frozen and trapped in a sliding
-- ice cube (see Services/IceCubeService.luau) for a short time.
--
-- Plain Water (no Ice garnish) is completely untouched — this only reacts
-- to the garnished variant, checked at sip time via DS_GarnishesCsv.

local IceCube = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
-- Services: { DrinkEffectsService, Packets, Settings, Recipes, IceCubeService }
function IceCube.OnSip(ctx)
	local tool = ctx.Tool
	if not tool then
		return
	end

	local garnishCsv = tool:GetAttribute("DS_GarnishesCsv") or ""
	local hasIce = false
	for token in string.gmatch(garnishCsv, "([^,]+)") do
		if token == "Ice" then
			hasIce = true
			break
		end
	end
	if not hasIce then
		return -- plain Water — normal sober-up sip, nothing special
	end

	-- Multi-sip water: only trap once per drink
	if tool:GetAttribute("DS_IceCubeTriggered") == true then
		return
	end
	tool:SetAttribute("DS_IceCubeTriggered", true)

	local Services = ctx.Services
	-- Small beat so the sip animation finishes before they get frozen solid
	task.delay(0.5, function()
		Services.IceCubeService.Trap(ctx.Player, Services.Settings.IceCubeDuration or 20)
	end)
end

return IceCube
