--[[
	Standings — who is where in the race.

	HOW PROGRESS IS MEASURED
	------------------------
	One monotonic number per racer:

		score = laps * 1e6  +  checkpoints * 1e3  +  metres past the last one

	Sorting descending gives the running order. Using a single scalar
	rather than comparing lap-then-checkpoint-then-distance means the
	comparison can't disagree with itself at a boundary, and it's one
	attribute to replicate instead of three.

	WHY IT GOES THROUGH THE SERVER
	------------------------------
	Each client knows its OWN progress — it owns its simulation — but
	nothing about anyone else's. Attributes set by a client don't
	replicate, so clients report progress up and the server writes it
	back onto each kart as an attribute, which every client then reads.

	That's a deliberately thin relay: the server isn't validating times
	yet. It's the seam where that validation goes when the race stops
	being a placeholder, and it's why targeting an opponent already works
	off replicated state rather than a client guessing.
--]]

local Standings = {}

Standings.ATTRIBUTE = "KartProgress"
Standings.REMOTE = "KartProgressReport"

-- Collapse lap / checkpoint / distance into one comparable number.
function Standings.score(laps: number, checkpoints: number, distance: number): number
	return laps * 1e6 + checkpoints * 1e3 + math.clamp(distance, 0, 999)
end

-- Every kart in the world with a progress attribute, best first.
-- Returns { { kart = Model, score = number, player = Player? } }
function Standings.order(karts: { Model }): { { kart: Model, score: number } }
	local list = {}
	for _, kart in karts do
		local score = kart:GetAttribute(Standings.ATTRIBUTE)
		if typeof(score) == "number" then
			table.insert(list, { kart = kart, score = score })
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	return list
end

-- 1-based place of `kart`, and the field size. 0 if it isn't ranked.
function Standings.placeOf(order, kart: Model): (number, number)
	for i, entry in order do
		if entry.kart == kart then
			return i, #order
		end
	end
	return 0, #order
end

-- The kart directly ahead of `kart`, or nil if it's leading. This is
-- what a targeting item aims at — you can only hit the racer in front,
-- which keeps items a catch-up tool rather than a way to extend a lead.
function Standings.ahead(order, kart: Model): Model?
	local place = Standings.placeOf(order, kart)
	if place <= 1 then
		return nil
	end
	return order[place - 1].kart
end

return Standings
