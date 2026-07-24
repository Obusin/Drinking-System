-- IceCube: fires the freeze/trap on an actual SIP of a Water drink carrying
-- the Ice/Ice Cube garnish. The shake flourish already played the moment
-- the garnish was added (see DrinkSystemController.onAddGarnish) — this is
-- purely "you drank it, now you're frozen."

local IceCube = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function IceCube.OnSip(ctx)
	local tool = ctx.Tool
	if not tool then
		return
	end

	local garnishCsv = tool:GetAttribute("DS_GarnishesCsv") or ""
	local hasIce = false
	for token in string.gmatch(garnishCsv, "([^,]+)") do
		if token == "Ice" or token == "Ice Cube" then
			hasIce = true
			break
		end
	end
	if not hasIce then
		return -- plain Water — normal sober-up sip, nothing special
	end

	if tool:GetAttribute("DS_IceCubeTriggered") == true then
		return
	end
	tool:SetAttribute("DS_IceCubeTriggered", true)

	local Services = ctx.Services
	task.delay(0.3, function()
		Services.IceCubeService.Trap(ctx.Player, Services.Settings.IceCubeDuration or 20)
	end)
end

return IceCube
