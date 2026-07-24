-- Owner's Delight: Caffemo x4 → inverted controls for a while. The actual
-- inversion runs client-side (see InvertControlsClient.client.luau) — this
-- just tells the drinker's own client to start, for how long.

local OwnersDelight = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function OwnersDelight.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_OwnersDelightTriggered") == true then
			return
		end
		tool:SetAttribute("DS_OwnersDelightTriggered", true)
	end

	local Services = ctx.Services
	local duration = Services.Settings.OwnersDelightDuration or 12
	Services.Packets.InvertControls.sendTo({ Duration = duration }, ctx.Player)
end

return OwnersDelight
