--[[
	Assets — publishes authored models the CLIENT needs.

	WHY THIS EXISTS
	---------------
	ServerStorage is server-only. Clients cannot see into it at all, not
	even to clone from it.

	That's fine for anything the server spawns — hazards, kart art — but
	missiles are drawn by every client locally, on purpose: a
	server-driven anchored part replicates its CFrame at the network rate
	and stutters, so the server owns where a projectile IS and each
	client owns what it LOOKS like.

	Which leaves the rocket model unreachable by exactly the code that
	needs it. So it's copied into ReplicatedStorage once at startup.

	COPIED, NOT MOVED. The original stays in ServerStorage where it was
	authored, so opening the place still shows the model where you put
	it, and re-running the server can't consume it.

	WHAT REPLICATION COSTS
	----------------------
	One copy of the model, once, to everyone. The alternative — every
	client asking the server for it — is more traffic and more code.
	Models here should be art only: no scripts, no secrets. Anything in
	ReplicatedStorage is readable by any client, which is fine for a
	rocket and would not be for game logic.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local IT = Config.Items
-- Always on: this runs once at startup, prints one line per model, and
-- "did the rocket actually publish" is the first question when a missile
-- comes out looking like a plain box.
local log = Util.logger("Assets", true)

local Assets = {}

-- Where published art lands. Clients look here and nowhere else.
Assets.FOLDER = "Assets"

function Assets.start()
	local into = ReplicatedStorage:FindFirstChild(Assets.FOLDER)
	if not into then
		into = Instance.new("Folder")
		into.Name = Assets.FOLDER
		into.Parent = ReplicatedStorage
	end

	-- Only what a client actually draws. Hazard art is spawned by the
	-- server and stays in ServerStorage where it belongs.
	local wanted = { IT.ProjectileModel }

	for _, name in wanted do
		if name == "" then
			continue
		end
		if into:FindFirstChild(name) then
			continue -- already published, e.g. a soft restart
		end

		local source = ServerStorage:FindFirstChild(name)
		if not source then
			-- Not fatal: the client falls back to drawing a plain part, so
			-- a missing model is a missile that looks basic rather than a
			-- missile that doesn't exist.
			warn(
				("[Assets] no model named %q in ServerStorage — projectiles will use the plain fallback part. Put the model there, or set Items.ProjectileModel to \"\" to silence this."):format(
					name
				)
			)
			continue
		end

		local copy = source:Clone()
		-- Stripped on the way out. Art must not carry behaviour into a
		-- place every client can read, and a stray script inside a model
		-- that gets cloned per projectile would run per projectile.
		for _, d in copy:GetDescendants() do
			if d:IsA("BaseScript") then
				d:Destroy()
			end
		end
		copy.Parent = into
		log("published %s", name)
	end
end

return Assets
