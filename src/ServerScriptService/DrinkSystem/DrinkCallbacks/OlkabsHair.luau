-- Olkab's Hair: Absmith x4 → yoink sound + hair accessories physically POP
-- OFF (a free-flying, weld-stripped clone launches with a random tumble —
-- unmissable, wahaha), then restores exactly what was removed after a while.
-- The REAL accessory is stored offline immediately (unmodified, weld
-- intact) — only a disposable CLONE does the flying, so restoration stays
-- exact and simple regardless of where the clone ends up landing.

local OlkabsHair = {}

type ActiveState = {
	Removed: { Instance },
}

local active: { [Player]: ActiveState } = {}

local function isHairAccessory(inst: Instance): boolean
	if inst:IsA("Accessory") then
		return inst.AccessoryType == Enum.AccessoryType.Hair
	end
	if inst:IsA("Hat") then
		return true -- legacy Hat class, still common for hair on older avatars
	end
	return false
end

-- Launches a disposable, weld-stripped clone from the accessory's current
-- position — the ORIGINAL is untouched, this is purely the visual "pop."
local function popOff(original: Instance)
	-- Recursive lookup + a BasePart fallback: some accessories nest their
	-- mesh a level deeper than a direct "Handle" child, and a non-recursive
	-- lookup silently finding nothing here used to mean the pop just never
	-- happened (while the accessory still vanished right after).
	local handle = (original:FindFirstChild("Handle", true) :: BasePart?)
		or original:FindFirstChildWhichIsA("BasePart", true)
	if not handle then
		warn("[OlkabsHair] No BasePart found on", original:GetFullName(), "- pop effect skipped")
		return
	end

	local clone = original:Clone()
	local cloneHandle = (clone:FindFirstChild(handle.Name, true) :: BasePart?)
		or clone:FindFirstChildWhichIsA("BasePart", true)
	if not cloneHandle then
		clone:Destroy()
		return
	end

	-- Strip anything that would still yank it back toward the character —
	-- we want it genuinely free-flying, not welded mid-air.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
		end
	end

	clone.Parent = workspace
	cloneHandle.CFrame = handle.CFrame

	local horizontal = Vector3.new((math.random() - 0.5) * 16, 0, (math.random() - 0.5) * 16)
	cloneHandle.AssemblyLinearVelocity = Vector3.new(0, 18, 0) + horizontal
	cloneHandle.AssemblyAngularVelocity = Vector3.new(
		(math.random() - 0.5) * 12,
		(math.random() - 0.5) * 12,
		(math.random() - 0.5) * 12
	)

	task.delay(3, function()
		if clone.Parent then
			clone:Destroy()
		end
	end)
end

local function restore(player: Player)
	local state = active[player]
	if not state then
		return
	end
	active[player] = nil
	local char = player.Character
	if not char then
		return
	end
	for _, acc in ipairs(state.Removed) do
		if acc and acc.Parent == nil then
			pcall(function()
				acc.Parent = char
			end)
		end
	end
end

-- Called by AvatarRefreshService before a live outfit swap: the stored
-- accessory instances would be stale against whatever new outfit is about
-- to apply, so this abandons them (destroyed, not reparented back) rather
-- than trying to restore hair that no longer matches. Safe no-op if the
-- player isn't currently affected.
function OlkabsHair.CancelForRefresh(player: Player)
	local state = active[player]
	if not state then
		return
	end
	active[player] = nil
	for _, acc in ipairs(state.Removed) do
		if acc and acc.Parent == nil then
			acc:Destroy()
		end
	end
end

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function OlkabsHair.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_OlkabsHairTriggered") == true then
			return
		end
		tool:SetAttribute("DS_OlkabsHairTriggered", true)
	end

	local player = ctx.Player
	if active[player] then
		return -- already bald (or already queued to go bald)
	end
	active[player] = { Removed = {} } -- claim the slot now so a second sip mid-delay can't double-trigger

	local Services = ctx.Services
	local yoinkDelay = Services.Settings.OlkabsHairYoinkDelay or 1.5

	task.delay(yoinkDelay, function()
		-- Bail cleanly if they got un-claimed somehow (e.g. character gone)
		if not active[player] then
			return
		end

		local char = player.Character
		if not char then
			active[player] = nil
			return
		end

		local toRemove = {}
		for _, inst in ipairs(char:GetChildren()) do
			if isHairAccessory(inst) then
				table.insert(toRemove, inst)
			end
		end
		if #toRemove == 0 then
			active[player] = nil
			return -- nothing to remove
		end

		Services.DrinkEffectsService.playCharacterSound(
			player,
			Services.Settings.OlkabsHairYoinkSoundId,
			Services.Settings.OlkabsHairYoinkVolume or 0.6
		)

		local removed = {}
		for _, inst in ipairs(toRemove) do
			popOff(inst) -- fling a disposable clone BEFORE detaching the real one
			inst.Parent = nil
			table.insert(removed, inst)
		end

		active[player] = { Removed = removed }

		local duration = Services.Settings.OlkabsHairDuration or 20
		task.delay(duration, function()
			restore(player)
		end)
	end)
end

return OlkabsHair
