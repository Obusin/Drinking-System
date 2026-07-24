-- Bee Swarm: Maple Syrup + Sugar + Sugar → the sweetness attracts a swarm.
-- Thin wrapper around BeeSwarmService (already proven via the QA button).

local BeeSwarm = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function BeeSwarm.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_BeeSwarmTriggered") == true then
			return
		end
		tool:SetAttribute("DS_BeeSwarmTriggered", true)
	end

	local Services = ctx.Services
	if not Services.BeeSwarmService then
		return
	end
	Services.BeeSwarmService.Start(ctx.Player, Services.Settings.BeeSwarmDuration)
end

return BeeSwarm
