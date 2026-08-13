--[[
	Items registry — every power-up, and the weighted roll between them.

	An item is a MODULE, not a config row. Config rows work while items
	are alike and collapse the moment they aren't: a boost changes one
	number, a shield spawns a bubble and lives for six seconds, a missile
	reaches across the network to another player. Adding an item here is
	one new file and one line in `list`, never an edit to the framework.

	Each module provides:
		Id, Name, Weight, Scope ("self" | "world")
		Use(ctx) -> ok, reason
		Update(ctx, dt)   optional, while active
		Finish(ctx)       optional, cleanup
--]]

local Items = {}

local list = {
	require(script.Turbo),
	require(script.Missile),
	require(script.Mine),
	require(script.OilSpill),
	require(script.Shield),
	require(script.Refill),
	require(script.Lightning),
	require(script.Scramble),
	require(script.FakeBox),
	require(script.Rainbow),
}

Items.All = list

function Items.byId(id: string)
	for _, item in list do
		if item.Id == id then
			return item
		end
	end
	return nil
end

-- Weighted pick, biased by race position.
--
-- Leaders roll weaker items, trailers roll stronger ones. This is the
-- fairness lever in every kart racer, and it's better than cheating the
-- physics: nobody's kart is secretly faster, the pool just tilts. A
-- player can see they got a good item and understand why.
--
-- `place` / `field` are optional — with no standings the roll is flat.
function Items.roll(rng: Random?, place: number?, field: number?)
	-- 0 = leading, 1 = last.
	local behind = 0
	if place and field and field > 1 and place > 0 then
		behind = (place - 1) / (field - 1)
	end

	local total = 0
	local weights = {}
	for i, item in list do
		local w = item.Weight or 1
		-- Offensive and utility items get better the further back you are.
		-- Items marked Filler keep a flat weight so the floor never drops:
		-- a leader always has SOMETHING worth holding.
		--
		-- Declared per item rather than matched on Id — an `Id ~= "Turbo"`
		-- test silently stops working the moment that item is renamed or a
		-- second filler is added.
		if not item.Filler then
			w *= 0.55 + behind * 0.9
		end
		weights[i] = w
		total += w
	end
	if total <= 0 then
		return nil
	end

	local pick = if rng then rng:NextNumber(0, total) else math.random() * total
	for i, item in list do
		pick -= weights[i]
		if pick <= 0 then
			return item
		end
	end
	return list[#list]
end

return Items
