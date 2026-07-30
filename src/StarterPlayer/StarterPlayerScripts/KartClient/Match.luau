--[[
	Match (client) — mirrors the server's phase and applies it locally.

	Logic only; MatchHud draws it.

	WHAT THIS ACTUALLY DOES
	-----------------------
		Grid     resets the lap counter, puts the kart on its grid slot,
		         and holds it there
		Racing   releases the hold and starts the clock, on the frame the
		         deadline passes
		finish   reports our total time up to the server, once

	The countdown is computed from the server's published deadline rather
	than received tick by tick — see the Match shared module for why.

	IMPORTANT: the kart is released by the LOCAL clock reaching the
	server's deadline, not by waiting for the server to say "go". That
	way there's no round trip between the lights and control returning.
	The server's own transition happens within a tick either way, and it
	is still the only thing that decides whether a finish counts.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Shared = require(BloxKart:WaitForChild("Match"))

local M = Config.Match
local P = Shared.Phase

local Match = {}
Match.__index = Match

--=====================================================================
--  BINDING COLLISION CHECK
--
--  ReadyKey lives in a different config module from every other
--  binding, so nothing stops it being set to a key that's already
--  taken — and a doubled key fires BOTH actions silently, which is
--  miserable to debug. Cheaper to notice at startup.
--=====================================================================
local function checkReadyKey()
	local taken: { [Enum.KeyCode]: string } = {}
	local function claim(keys, what: string)
		for _, k in keys do
			taken[k] = what
		end
	end
	claim(Config.Respawn.ResetKeys, "reset to checkpoint")
	claim(Config.Items.UseKeys, "use item")
	claim(Config.Input.DriftKeys, "hop-drift")
	claim(Config.Input.NitroKeys, "nitro")
	claim(Config.Input.LookBackKeys, "look back")
	claim(Config.Input.ExitKeys, "exit kart")
	claim({ Config.Hud.ControlsToggleKey }, "controls toggle")

	local clash = taken[M.ReadyKey]
	if clash then
		warn(("[Match] ReadyKey (%s) is already bound to %q — both will fire."):format(M.ReadyKey.Name, clash))
	end
end

function Match.new()
	local state = BloxKart:WaitForChild(Shared.FOLDER, 10)
	local finishRemote = BloxKart:WaitForChild(Shared.FINISH_REMOTE, 10)
	local readyRemote = BloxKart:WaitForChild(Shared.READY_REMOTE, 10)

	if not state then
		warn("[Match] no MatchState folder — is MatchService running?")
	end
	checkReadyKey()

	return setmetatable({
		state = state,
		finishRemote = finishRemote,
		readyRemote = readyRemote,

		phase = P.Waiting,
		round = -1,
		lastWhole = -1, -- last countdown integer announced

		gridApplied = false,
		reported = false,
		isReady = false,
	}, Match)
end

--=====================================================================
--  READS
--=====================================================================
function Match:Phase(): string
	if not self.state then
		return P.Waiting
	end
	return self.state:GetAttribute(Shared.PHASE) or P.Waiting
end

function Match:TimeLeft(): number
	if not self.state then
		return 0
	end
	return Shared.timeLeft(self.state:GetAttribute(Shared.ENDS_AT))
end

function Match:IsRacing(): boolean
	return Shared.isDriving(self:Phase())
end

function Match:Racers(): number
	if not self.state then
		return 0
	end
	return self.state:GetAttribute(Shared.RACERS) or 0
end

function Match:ReadyCount(): number
	if not self.state then
		return 0
	end
	return self.state:GetAttribute(Shared.READY) or 0
end

function Match:MinRacers(): number
	return M.MinRacers
end

function Match:IsReady(): boolean
	return self.isReady
end

--=====================================================================
--  READY UP
--=====================================================================
function Match:SetReady()
	if self.isReady or self:Phase() ~= P.Intermission then
		return
	end
	self.isReady = true
	if self.readyRemote then
		self.readyRemote:FireServer()
	end
end

--=====================================================================
--  FRAME
--
--  Returns { phase = string?, countdown = n?, go = true?,
--            finished = true? }
--=====================================================================
function Match:Update(_dt: number, sim, race): { [string]: any }
	local events = {}
	local phase = self:Phase()
	local left = self:TimeLeft()

	local round = self.state and self.state:GetAttribute(Shared.ROUND) or 0
	if round ~= self.round then
		-- New round. Everything per-round resets here rather than on a
		-- phase edge, so a client that joined mid-race still starts clean
		-- when the next one begins.
		self.round = round
		self.gridApplied = false
		self.reported = false
		self.isReady = false
		race:Reset()
		-- Nitro doesn't carry over. Items don't either, but this module
		-- has no handle on them, so the caller clears those on the event.
		sim:ResetForRound()
		events.newRound = true
	end

	if phase ~= self.phase then
		self.phase = phase
		self.lastWhole = -1
		events.phase = phase
	end

	----------------------------------------------------------------
	-- GRID — reset, place, hold
	----------------------------------------------------------------
	if phase == P.Grid then
		sim:Hold(true)

		-- Retried every frame until it lands: the grid CFrame and the
		-- phase are separate attributes on separate instances, so there's
		-- no guarantee the CFrame arrived first.
		if not self.gridApplied and sim.model then
			local cf = sim.model:GetAttribute(Shared.GRID_CF)
			if typeof(cf) == "CFrame" then
				sim:RespawnAt(cf)
				self.gridApplied = true
				-- The kart just teleported across the map. The camera has to
				-- cut rather than sweep, or the countdown is spent watching
				-- it fly in from wherever the last round ended.
				events.gridded = true
			end
		end

		-- One event per whole second, so the HUD and the audio both fire
		-- exactly once per number instead of every frame.
		local whole = math.ceil(left)
		if whole ~= self.lastWhole then
			self.lastWhole = whole
			if whole > 0 then
				events.countdown = whole
			end
		end
		return events
	end

	----------------------------------------------------------------
	-- RACING
	----------------------------------------------------------------
	if phase == P.Racing then
		if sim.held then
			-- The lights just went out. Release and start the clock on the
			-- same frame, so the timer can never include held time.
			sim:Hold(false)
			race:Begin()
			events.go = true
		elseif not race.running then
			-- Joined (or spawned) mid-round. No GO for them, but they get a
			-- working lap counter instead of a dead HUD until the next
			-- round — without this, `locked` from Reset would never clear.
			race:Begin()
		end

		-- Crossed the line for the last time. Reported once; the server
		-- assigns the actual place.
		if race.finished and not self.reported then
			self.reported = true
			if self.finishRemote then
				self.finishRemote:FireServer(race:TotalElapsed())
			end
			events.finished = true
		end
		return events
	end

	----------------------------------------------------------------
	-- WAITING / INTERMISSION / RESULTS
	--
	-- Free to drive, but nothing counts — the race is locked, so laps
	-- and checkpoints are ignored. Rolling around between rounds feels
	-- better than being frozen, and warming up on the track is how you
	-- learn it.
	----------------------------------------------------------------
	sim:Hold(false)
	race.locked = true
	return events
end

return Match
