--[[
	Names — every string that crosses a boundary, in one place.

	Tags and attribute names are how the client and server talk about the
	same object without sharing memory. Written as raw literals they're
	invisible to the analyser, invisible to a rename, and a typo in one of
	five copies fails silently: the tag simply never matches, so a kart
	stops being found or a hazard stops arming, with no error anywhere.

	`OwnerUserId` was in five files. The `Kart` tag was in five. This file
	is one require and one autocomplete instead.

	WHAT BELONGS HERE
	-----------------
	Strings both ends must agree on. Tunables don't — those are Config,
	because you change them to change behaviour. Nothing here should ever
	be changed to tune anything; changing a name here only renames it.

	(Standings and Match own their own names, because those come with
	protocol rules the name alone doesn't convey. Don't move them here.)
--]]

local Names = {}

--== TAGS ==============================================================
Names.KART_TAG = "Kart"

--== ATTRIBUTES ========================================================

-- On a kart. Maps a model back to the player who owns it, which is how
-- every system that starts from a kart finds the human.
Names.OWNER = "OwnerUserId"

-- On a power-up box. Server-owned: set when collected, cleared when it
-- respawns. Clients read it to avoid asking for a box already taken.
Names.TAKEN = "Taken"

-- On a dropped hazard. The time it becomes dangerous to its own dropper,
-- so driving away from your own mine doesn't spin you.
Names.ARM_AT = "ArmAt"

-- On a dropped hazard. Which item it is, so one code path serves mines,
-- oil, fake boxes and anything added later.
Names.HAZARD_ITEM = "HazardItem"

-- On a road wheel's Motor6D. True for the front pair, which steer as
-- well as roll.
Names.WHEEL_FRONT = "IsFront"

-- On a kart, written by its own driver's client. Steering as the DRIVER
-- knows it, which on a touch device the VehicleSeat never sees — see
-- Rider. Client-set, so it does NOT replicate; remote karts fall back to
-- SteerFloat, which is correct for anyone on a keyboard.
Names.STEER = "KartSteer"

-- On a kart, written by its own driver's client alongside STEER. The
-- visual drift angle in radians — how far the body is yawed away from
-- where it's actually travelling. The front wheels cancel it so they
-- stay pointed down the road; see Rider.
Names.DRIFT = "KartDrift"

return Names
