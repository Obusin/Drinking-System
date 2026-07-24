-- Chicken Dinner: Soda Water + Vermix + Caffemo → a few staggered clucks
-- from ONE audio clip, slightly pitch-varied so it reads as "random chicken
-- sounds" rather than one clean loop.

local ChickenDinner = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function ChickenDinner.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_ChickenDinnerTriggered") == true then
			return
		end
		tool:SetAttribute("DS_ChickenDinnerTriggered", true)
	end

	local Services = ctx.Services
	local soundId = Services.Settings.ChickenDinnerSoundId
	if not soundId then
		return
	end

	for i = 1, 3 do
		task.delay((i - 1) * 0.4 + math.random() * 0.15, function()
			Services.DrinkEffectsService.playCharacterSound(
				ctx.Player,
				soundId,
				Services.Settings.ChickenDinnerSoundVolume or 0.5,
				0.9 + math.random() * 0.3
			)
		end)
	end
end

return ChickenDinner
