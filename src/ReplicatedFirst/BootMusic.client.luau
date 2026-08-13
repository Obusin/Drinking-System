--[[
	BootMusic — lobby music during the loading splash.

	ReplicatedFirst so it can start playing before KartClient's phase-aware
	Music system even exists. It plays a single lobby track, fades it in, and
	then hands off: the moment KartClient's real music (the "BloxKartMusic"
	sound) starts, this fades out and destroys itself.

	Deliberately dumb — one looping track, no shuffle/phase logic. That all
	lives in KartClient/Music, which needs the live match phase to switch
	lobby↔race and so can't run this early. This only has to cover the gap
	between "joined" and "KartClient started".
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local bloxKart = ReplicatedStorage:WaitForChild("BloxKart", 20)
if not bloxKart then
	return
end
local ok, Config = pcall(function()
	return require(bloxKart:WaitForChild("Config"))
end)
if not ok then
	return
end

local M = Config.Music
local lobby = M and M.Lobby
local loading = M and M.Loading
-- Loading music is now owned by KartClient/Music during the *visible*
-- Intermission, not by this early ReplicatedFirst script. That prevents a
-- song spending its entire opening behind the splash and avoids two tracks
-- fighting the moment the normal music controller attaches.
if typeof(loading) == "string" and loading ~= "" then
	return
end
if (typeof(loading) ~= "string" or loading == "") and (not lobby or #lobby == 0) then
	return -- no tracks yet — stay silent, exactly like the main system does
end

local sound = Instance.new("Sound")
sound.Name = "BloxKartBootMusic"
-- Loading has its own authored track. Keep the lobby fallback so a bad or
-- removed Loading id degrades to the previous boot experience rather than
-- making joins silently mute.
sound.SoundId = if typeof(loading) == "string" and loading ~= "" then loading else lobby[math.random(#lobby)]
sound.Looped = true
sound.Volume = 0
sound.Parent = SoundService
sound:Play()

local target = M.Volume or 0.5
local fadeRate = M.FadeRate or 2

-- Fade in; once the real music is audibly up, crossfade out and clean up.
local conn: RBXScriptConnection?
conn = RunService.Heartbeat:Connect(function(dt)
	local real = SoundService:FindFirstChild("BloxKartMusic")
	local handingOff = real ~= nil and real:IsA("Sound") and real.IsPlaying and real.Volume > 0.02
	local want = if handingOff then 0 else target
	sound.Volume += (want - sound.Volume) * math.clamp(dt * fadeRate, 0, 1)
	if handingOff and sound.Volume < 0.02 then
		if conn then
			conn:Disconnect()
			conn = nil
		end
		sound:Destroy()
	end
end)
