--[[
	RemoteKarts — smooths karts this client doesn't own.

	THE PROBLEM
	-----------
	Your own kart is simulated on your machine, so it moves at your frame
	rate. Every other kart arrives over the network: a bot's is written by
	the server, and an anchored part's CFrame replicates as a plain
	property update roughly twenty times a second. At racing speed that's
	six studs a step, and it reads as stuttering or teleporting.

	Interpolating on the receiving end is how every networked game has
	solved this since the nineties. The server stays the single authority
	on where a kart IS; this only decides what to draw between the moments
	it says so.

	WHY NOT JUST MAKE THE SERVER SEND MORE
	--------------------------------------
	Because it doesn't matter how often it sends — you're always drawing
	between two updates. More traffic narrows the gap; it doesn't remove
	it. And it scales with racers, which is exactly the wrong direction.

	WHAT THIS DOES NOT DO
	---------------------
	It never moves a kart anywhere the server didn't say. It lags the
	truth by one update and catches up — so a kart is drawn a fraction
	behind where the server has it, which is the trade every game makes
	and nobody notices.

	Hits, items and standings all read server state, not this. Being
	drawn a few studs back can't change who got hit.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))

local R = Config.Rig

local RemoteKarts = {}

local tracked: { [BasePart]: { shown: CFrame, target: CFrame } } = {}

-- Our own kart is simulated locally and must never be touched: it's
-- already at the right place every frame, and smoothing it would add lag
-- to the one kart whose lag you'd feel.
local function isOurs(kart: Model): boolean
	return kart:GetAttribute(Names.OWNER) == Players.LocalPlayer.UserId
end

local function step(dt: number)
	local alpha = math.min(R.RemoteSmoothing * dt, 1)

	for _, kart in CollectionService:GetTagged("Kart") do
		local hitbox = kart.PrimaryPart
		if not hitbox or not kart.Parent or isOurs(kart) then
			continue
		end

		local state = tracked[hitbox]
		if not state then
			tracked[hitbox] = { shown = hitbox.CFrame, target = hitbox.CFrame }
			continue
		end

		-- A CFrame we didn't write is a new update from the server. Ours
		-- is whatever we drew last frame, so anything else is news.
		if not hitbox.CFrame:FuzzyEq(state.shown, 1e-4) then
			state.target = hitbox.CFrame
		end

		-- Too far to be an update — a respawn, a grid placement, a kart
		-- rebuilt. Easing across that would fly the kart over the scenery,
		-- which is precisely the thing this exists to stop looking like.
		if (state.target.Position - state.shown.Position).Magnitude > R.RemoteSnapDistance then
			state.shown = state.target
		else
			state.shown = state.shown:Lerp(state.target, alpha)
		end

		hitbox.CFrame = state.shown
	end
end

function RemoteKarts.start()
	if not R.RemoteSmoothing or R.RemoteSmoothing <= 0 then
		return
	end

	-- Dropped when a kart goes, or the table grows forever across a
	-- session's worth of respawns.
	CollectionService:GetInstanceRemovedSignal("Kart"):Connect(function(kart)
		for part in tracked do
			if not part.Parent or part:IsDescendantOf(kart) then
				tracked[part] = nil
			end
		end
	end)

	-- After the simulation, so our own kart has already been placed for
	-- this frame and we're only ever smoothing other people's.
	RunService.Heartbeat:Connect(step)
end

return RemoteKarts
