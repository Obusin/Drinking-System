--[[
	Loadout — the client's single answer to "what should a kart look like".

	WHY THIS EXISTS
	---------------
	The menu stage kart had TWO owners: MainMenuHud built it, GarageHud
	dressed it. That is this project's oldest bug shape — one question
	answered in two places — and it produced the exact symptom you would
	expect. GarageHud dressed the kart ONCE, in a window it had to guess
	at, and anything that created or replaced the kart outside that window
	won. On a cold join the stage was usually built after the guess, so
	the menu showed the default kart while the profile was perfectly
	correct.

	Chasing it with a longer poll is not a fix, it is a longer guess.

	SO: ONE OWNER, AND IT KEEPS WATCHING
	------------------------------------
	This module holds the current look and re-applies it whenever EITHER
	side changes:

	  the look changes    -> every tracked kart is re-dressed
	  the kart changes    -> the new one is dressed

	`track` takes a GETTER rather than a model, which is the important
	part: the menu stage is cloned lazily and can be rebuilt, so a
	reference captured once goes stale. Asking again every tick cannot.

	It is deliberately dumb about WHY a kart changed. A rebuild, a fresh
	clone, a stage that only appears when the menu first opens — all the
	same event, all handled, none of them special-cased.

	CLIENT ONLY in practice, but it lives in ReplicatedStorage because
	KartDress does and there is nothing server-hostile in it. The server
	has its own path (KartService.dressKart) and must keep it: only the
	server can be trusted about what a player actually owns.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local KartDress = require(BloxKart:WaitForChild("KartDress"))

local G = Config.Garage

local Loadout = {}

-- Equipped IDS, not meshes. Same shape the server replies with, so this
-- can be handed the payload untouched.
local current = { Body = "stock", Wheels = "stock", Paint = "stock" }

-- Bumped on every change. A tracker compares (generation, model) against
-- what it last applied, which is what lets one loop cover both "the look
-- changed" and "the kart changed" without two mechanisms.
local generation = 0

-- True once the SERVER has told us something. Before that we are showing
-- a guess, and callers that care — the loading screen, mainly — need to
-- know the difference between "stock because that is what they wear" and
-- "stock because nobody has said yet".
local confirmed = false

local function itemById(list, id: string)
	for _, item in list do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Loadout.isConfirmed(): boolean
	return confirmed
end

function Loadout.get(): { [string]: string }
	return table.clone(current)
end

-- Resolve ids to the thing KartDress wants. Kept here rather than in the
-- HUD so the catalogue is read in one place.
function Loadout.look(): { body: string?, wheel: string?, paint: Color3? }
	local body = itemById(G.Bodies, current.Body or "stock")
	local wheel = itemById(G.Wheels, current.Wheels or "stock")
	local paint = itemById(G.Paints, current.Paint or "stock")
	return {
		body = body and body.mesh or nil,
		wheel = wheel and wheel.mesh or nil,
		paint = paint and paint.colour or nil,
	}
end

-- Merge in whatever we were told. Only known slots, only strings, so a
-- malformed payload cannot wipe a good state.
--
-- `fromServer` marks it authoritative. A local preview pick changes the
-- look WITHOUT confirming it, so the loading screen is never released by
-- the player idly clicking a body in the garage.
function Loadout.set(equipped: any, fromServer: boolean?)
	if type(equipped) ~= "table" then
		return
	end
	local changed = false
	for slot, id in equipped do
		if current[slot] ~= nil and type(id) == "string" and current[slot] ~= id then
			current[slot] = id
			changed = true
		end
	end

	-- BECOMING CONFIRMED IS ITSELF A CHANGE, even when no id moved.
	--
	-- This was a real bug and the log named it exactly. A fresh profile
	-- replies `Body=stock Wheels=stock Paint=stock`, which matches the
	-- defaults this module starts on — so nothing "changed", the
	-- generation did not move, the tracker had no reason to re-run, and
	-- its callback (the only thing that raises PREVIEW_READY) never
	-- fired. The loading screen then sat on its full 8s timeout before
	-- giving up, on a join where the answer had arrived in 1.3s.
	--
	-- Consumers do not only care WHAT the look is; they care whether it
	-- is known yet. Treating the false -> true transition as a change is
	-- what makes "we now know" observable at all.
	local becameConfirmed = (fromServer == true) and not confirmed
	if fromServer then
		confirmed = true
	end
	if changed or becameConfirmed then
		generation += 1
	end
end

-- STAMPED, so "is this kart already wearing the right thing" is a
-- question with an answer instead of an assumption.
local STAMP = "BloxKartLook"

-- A short signature of the current look. Two looks are the same iff this
-- string matches, which is all the verifier needs.
local function signature(): string
	return ("%s|%s|%s"):format(
		tostring(current.Body),
		tostring(current.Wheels),
		tostring(current.Paint)
	)
end

function Loadout.dress(model: Instance)
	KartDress.apply(model, Loadout.look(), Config.Rig)
	-- Stamped on the MODEL after a successful apply. A kart that is
	-- replaced arrives without it; a kart whose look is stale carries the
	-- wrong one. Either way the verifier below re-dresses it.
	pcall(function()
		(model :: any):SetAttribute(STAMP, signature())
	end)
end

-- IS THIS KART ACTUALLY WEARING WHAT WE THINK?
--
-- The previous tracker compared (model identity, generation) and dressed
-- when either moved. That assumes nothing else ever touches the kart —
-- and something does. The menu builds its stage asynchronously and can
-- rebuild the art under an existing model, which changes NEITHER the
-- model identity NOR the loadout, so the tracker had no reason to look
-- again and the kart sat there in stock. That is the "works sometimes"
-- report: whether it looked right came down to which of two async jobs
-- happened to finish last.
--
-- Asking the kart instead of remembering what we did to it removes the
-- ordering question entirely. Whoever wrote last, the next tick notices
-- and corrects it.
function Loadout.isDressed(model: Instance): boolean
	local ok, stamp = pcall(function()
		return (model :: any):GetAttribute(STAMP)
	end)
	return ok and stamp == signature()
end

-- KEEP A KART DRESSED, whatever happens to it or to the loadout.
--
-- `getModel` is called on every tick rather than the model being passed
-- in, because the thing it returns is allowed to change identity — the
-- menu stage is cloned lazily and rebuilt — and a captured reference
-- would silently keep dressing a model nobody is looking at any more.
--
-- Returns a stop function. Nothing calls it today; it exists so a tracker
-- cannot outlive its owner by accident later.
function Loadout.track(getModel: () -> Instance?, onApplied: (() -> ())?)
	local running = true
	task.spawn(function()
		while running do
			-- Asked fresh every tick. The model is allowed to change
			-- identity — the stage is cloned lazily and can be rebuilt —
			-- so a captured reference would go stale.
			local model = getModel()
			if model and not Loadout.isDressed(model) then
				-- pcall: a kart destroyed mid-dress is normal, and must
				-- not kill the tracker for the rest of the session.
				local ok = pcall(Loadout.dress, model)
				if ok and onApplied then
					pcall(onApplied)
				end
			end
			task.wait(G.TrackInterval or 0.4)
		end
	end)
	return function()
		running = false
	end
end

return Loadout
