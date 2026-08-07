--[[
	DevConsoleClient — remote plumbing and the local cache.

	THIS MODULE HAS NO AUTHORITY AND KNOWS IT.
	------------------------------------------
	It builds request ids, invokes the remote, caches the last snapshot
	and hands responses back to the UI. It contains no permission check
	worth the name — `probe()` below asks the server whether we may open
	the console, and the answer is a convenience for hiding the window,
	never a gate. Every command is re-checked server-side regardless.

	The reason to ask at all: an unauthorized player should not build an
	Iris window they cannot use, and should not poll a snapshot that will
	only ever be refused.

	INVOKESERVER YIELDS AND CAN THROW. A RemoteFunction call errors if the
	server handler errors or the player leaves mid-call, so every call is
	wrapped — an unhandled error here would break the console's own UI
	loop, which is the least useful place for one.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Protocol = require(BloxKart:WaitForChild("DeveloperConsole"):WaitForChild("Protocol"))

local DevConsoleClient = {}

local remote: RemoteFunction? = nil
local counter = 0

-- Request ids only need to be unique PER PLAYER, since the server's
-- replay window is per user. Time plus a counter is enough and needs no
-- randomness source.
local function newRequestId(): string
	counter += 1
	return ("%d_%d"):format(math.floor(os.clock() * 1000), counter)
end

local function getRemote(): RemoteFunction?
	if remote and remote.Parent then
		return remote
	end
	local found = BloxKart:FindFirstChild(Protocol.CALL_REMOTE)
	remote = if found and found:IsA("RemoteFunction") then found else nil
	return remote
end

-- Returns a Protocol.Response, always — never nil, never a throw, so
-- callers can branch on `.success` without guarding.
function DevConsoleClient.call(command: string, payload: any?): Protocol.Response
	local id = newRequestId()
	local r = getRemote()
	if not r then
		return Protocol.fail(id, Protocol.Code.UNAVAILABLE, "Console remote not present.")
	end
	local ok, result = pcall(function()
		return r:InvokeServer(id, command, payload)
	end)
	if not ok then
		return Protocol.fail(id, Protocol.Code.INTERNAL, "Call failed: " .. tostring(result))
	end
	if type(result) ~= "table" or type(result.success) ~= "boolean" then
		-- A malformed reply means the server changed shape underneath us.
		return Protocol.fail(id, Protocol.Code.INTERNAL, "Malformed response.")
	end
	return result
end

-- May this client show the console?
--
-- The cheapest authorized-only command is the probe. A non-developer
-- gets NOT_AUTHORIZED and simply never builds the UI.
--
-- Yields. Called once at startup, off the critical path.
function DevConsoleClient.probe(): (boolean, string?)
	local response = DevConsoleClient.call("ping", {})
	if response.success then
		local role = response.data and response.data.role
		return true, if type(role) == "string" then role else "developer"
	end
	return false, nil
end

--=====================================================================
--  CACHE
--
--  The UI renders from here, never from a call. Iris redraws every
--  frame; a remote call per frame would be thousands of invocations a
--  minute and would rate-limit the console against itself.
--=====================================================================

local cache = {
	snapshot = nil :: any,
	snapshotAt = 0,
	player = nil :: any,
	playerAt = 0,
	logs = nil :: any,
	logsAt = 0,
	dressing = nil :: any,
	lastMessage = "",
	lastOk = true,
}

DevConsoleClient.cache = cache

function DevConsoleClient.note(response: Protocol.Response)
	cache.lastOk = response.success
	cache.lastMessage = ("[%s] %s"):format(response.code, response.message)
end

-- Refresh helpers. Each is throttled by `minAge` so holding a tab open
-- does not hammer the server; the router's rate limit is the backstop,
-- not the mechanism.
function DevConsoleClient.refreshSnapshot(minAge: number?)
	if os.clock() - cache.snapshotAt < (minAge or 2) then
		return
	end
	cache.snapshotAt = os.clock()
	task.spawn(function()
		local response = DevConsoleClient.call("snapshot", {})
		if response.success then
			cache.snapshot = response.data
		else
			DevConsoleClient.note(response)
		end
	end)
end

function DevConsoleClient.refreshPlayer(userId: number, force: boolean?)
	if not force and os.clock() - cache.playerAt < 2 then
		return
	end
	cache.playerAt = os.clock()
	task.spawn(function()
		local response = DevConsoleClient.call("inspect_player", { targetUserId = userId })
		if response.success then
			cache.player = response.data
		else
			cache.player = nil
			DevConsoleClient.note(response)
		end
	end)
end

function DevConsoleClient.refreshLogs(force: boolean?)
	if not force and os.clock() - cache.logsAt < 3 then
		return
	end
	cache.logsAt = os.clock()
	task.spawn(function()
		local response = DevConsoleClient.call("logs", { limit = 60 })
		if response.success then
			cache.logs = response.data and response.data.entries
		else
			DevConsoleClient.note(response)
		end
	end)
end

-- Not throttled: it is only ever fired by an explicit button press, and
-- the answer is worth having immediately when you press it.
function DevConsoleClient.refreshDressing(userId: number)
	task.spawn(function()
		local response = DevConsoleClient.call("inspect_dressing", { targetUserId = userId })
		if response.success then
			cache.dressing = response.data
		else
			cache.dressing = nil
			DevConsoleClient.note(response)
		end
	end)
end

-- Fire-and-note. Used by every button: the UI never blocks on a command.
function DevConsoleClient.send(command: string, payload: any?)
	task.spawn(function()
		DevConsoleClient.note(DevConsoleClient.call(command, payload))
		-- Anything that changes the world invalidates the snapshot.
		cache.snapshotAt = 0
	end)
end

function DevConsoleClient.localUserId(): number
	return Players.LocalPlayer.UserId
end

-- SERVER -> CLIENT PUSH.
--
-- The client never fires this remote, so it adds no inbound surface. The
-- only payload acted on is a CFrame the SERVER resolved — the client is
-- not trusted to pick where it goes, only to apply it, because it is the
-- one that owns its kart's position.
function DevConsoleClient.listen(hooks: any)
	local found = BloxKart:FindFirstChild(Protocol.PUSH_REMOTE)
	if not found or not found:IsA("RemoteEvent") then
		return
	end
	found.OnClientEvent:Connect(function(topic, data)
		if topic == "teleport" and typeof(data) == "table" and typeof(data.cf) == "CFrame" then
			if hooks and hooks.teleport then
				hooks.teleport(data.cf)
			end
		end
	end)
end

return DevConsoleClient
