--[[
	Match — the shared contract between MatchService (server) and the
	client. Names only; no logic and no state.

	HOW PHASE IS REPLICATED
	-----------------------
	One Folder under BloxKart with attributes on it. The server writes,
	every client reads. No remote, no per-frame traffic, and a client
	that joins mid-round sees the correct phase immediately because
	attributes replicate on join.

	THE CLOCK
	---------
	The server publishes an absolute DEADLINE, not a remaining time:

		PhaseEndsAt = workspace:GetServerTimeNow() + duration

	Clients subtract their own GetServerTimeNow() to get the countdown.
	GetServerTimeNow is synchronised, so every screen shows the same
	number without the server sending a single tick. Sending "3… 2… 1…"
	over a remote would drift, cost traffic, and land on a different
	frame for every player.

	FINISH ORDER
	------------
	Written as attributes on each kart, same as progress. A results
	board is then just a read of the karts already in the world — no
	separate list to keep in sync, and it survives a client joining
	late.
--]]

local Match = {}

Match.FOLDER = "MatchState"

-- Attributes on the folder.
Match.PHASE = "Phase"
Match.ENDS_AT = "PhaseEndsAt" -- server time, or 0 for "no deadline"
Match.RACERS = "Racers"
-- Racers with a person behind them. Published separately because the
-- round is gated on HUMANS while the field is mostly AI, and one number
-- cannot answer both "how big is the grid" and "is anyone here".
Match.HUMANS = "Humans"
Match.READY = "Ready" -- how many have readied up
Match.ROUND = "Round" -- increments per race; clients watch it to reset
-- The server's active lap target. It defaults to Config.Race.TotalLaps,
-- but is published separately so an authorised live-match override reaches
-- both player clients and BotService without a server restart.
Match.LAPS = "TotalLaps"

-- Attributes on each kart.
Match.FINISH_PLACE = "FinishPlace"
Match.FINISH_TIME = "FinishTime"

-- SERVER TIME the kart leaves the world, set when it finishes or is
-- eliminated. A timestamp rather than a countdown because the client has
-- to know it too, and a countdown would need re-sending every second —
-- and because os.clock() means nothing across the wire. Compare against
-- workspace:GetServerTimeNow().
Match.RETIRE_AT = "RetireAt"

-- Remotes.
Match.FINISH_REMOTE = "KartMatchFinish"
Match.READY_REMOTE = "KartMatchReady"
-- Client -> server once its own kart has received and applied GridCF. The
-- server uses this only to decide when the countdown may begin; it never
-- accepts a position from the client.
Match.GRID_READY_REMOTE = "KartMatchGridReady"
-- Client -> server after ReplicatedFirst's splash has fully uncovered. This
-- starts the intermission clock only when the cinematic is actually visible.
Match.INTERMISSION_VISIBLE_REMOTE = "KartMatchIntermissionVisible"
-- Client -> server: "I just fell in the void". The victim respawns
-- either way; this is only so the server can work out whether somebody
-- put them there and deserves the credit. Only the server knows who hit
-- this kart last, and the client gets no vote on who is rewarded.
Match.VOID_REMOTE = "KartVoid"

-- Attribute the server stamps with where this kart starts the round.
Match.GRID_CF = "GridCF"

-- Which slot on the grid, 0-based, as a plain number. The CFrame above
-- says WHERE; this says WHICH, and "finish above where you started" is a
-- question about the number.
Match.GRID_SLOT = "GridSlot"

Match.Phase = {
	Waiting = "Waiting", -- not enough racers
	Intermission = "Intermission", -- countdown to the grid
	Grid = "Grid", -- on the line, held, 3-2-1
	Racing = "Racing",
	Results = "Results",
}

-- True only in the one phase where the kart may move. Everything that
-- asks "can I drive?" goes through this rather than comparing strings,
-- so adding a phase can't silently make karts drivable in it.
function Match.isDriving(phase: string?): boolean
	return phase == Match.Phase.Racing
end

-- KARTS STILL MOVE, even though the race is decided.
--
-- Distinct from isDriving, which answers "does anything still count".
-- Results used to answer no to both, so the flag dropped and the entire
-- world stopped: bots parked, karts froze, and the board appeared over a
-- photograph. A race should end with the track still running under it.
function Match.isRolling(phase: string?): boolean
	return phase == Match.Phase.Racing or phase == Match.Phase.Results
end

-- Seconds left on the current phase, never negative. 0 when there's no
-- deadline (Waiting).
function Match.timeLeft(endsAt: number?): number
	if not endsAt or endsAt <= 0 then
		return 0
	end
	return math.max(endsAt - workspace:GetServerTimeNow(), 0)
end

return Match
