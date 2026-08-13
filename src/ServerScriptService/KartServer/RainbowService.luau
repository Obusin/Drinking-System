local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Names = require(BloxKart.Names)
local Items = require(BloxKart.Items)
local KartService = require(script.Parent.KartService)
local MatchService = require(script.Parent.MatchService)

local RainbowService = {}

function RainbowService.start()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "KartRainbow"
	remote.Parent = BloxKart
	remote.OnServerEvent:Connect(function(player)
		local function deny()
			remote:FireClient(player, false)
		end
		if not MatchService.itemsLive() then
			deny()
			return
		end
		local kart = KartService.kartFor(player)
		local item = Items.byId("Rainbow")
		if not (kart and item) or kart:GetAttribute(Names.RAINBOW_ACTIVE) then
			deny()
			return
		end
		-- The receipt is the server-side proof that this player actually
		-- picked up (or was deliberately granted) a Rainbow. Never treating
		-- a missing receipt as "probably old" made this remote a free boost
		-- button for any modified client.
		local held = player:GetAttribute(Names.RAINBOW_HELD)
		if typeof(held) ~= "number" or held < 1 then
			deny()
			return
		end
		player:SetAttribute(Names.RAINBOW_HELD, if held > 1 then held - 1 else nil)
		local duration = if item.StressTest then item.StressDuration else item.DurationHardMax
		kart:SetAttribute(Names.RAINBOW_ACTIVE, true)
		kart:SetAttribute(Names.RAINBOW_UNTIL, workspace:GetServerTimeNow() + duration)
		local glow = Instance.new("Highlight")
		glow.Name = "RainbowActiveGlow"
		glow.FillColor = Color3.fromRGB(255, 120, 220)
		glow.FillTransparency = 0.45
		glow.OutlineColor = Color3.fromRGB(90, 220, 255)
		glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		glow.Adornee = kart
		glow.Parent = kart
		remote:FireClient(player, true)
		-- A living colour cycle reads as Rainbow immediately, including to
		-- other racers who cannot see the owner's local guide dots.
		task.spawn(function()
			while glow.Parent and kart.Parent and kart:GetAttribute(Names.RAINBOW_ACTIVE) == true do
				local now = workspace:GetServerTimeNow()
				local hue = (now * 0.35) % 1
				glow.FillColor = Color3.fromHSV(hue, 0.82, 1)
				glow.OutlineColor = Color3.fromHSV((hue + 0.38) % 1, 0.72, 1)
				local left = (kart:GetAttribute(Names.RAINBOW_UNTIL) or now) - now
				glow.FillTransparency = if left < 0.8 and math.floor(now * 8) % 2 == 0 then 0.9 else 0.45
				task.wait(0.1)
			end
		end)
		task.delay(duration, function()
			if kart.Parent then
				kart:SetAttribute(Names.RAINBOW_ACTIVE, nil)
				kart:SetAttribute(Names.RAINBOW_UNTIL, nil)
				if glow.Parent then glow:Destroy() end
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local kart = KartService.kartFor(player)
		if kart then kart:SetAttribute(Names.RAINBOW_ACTIVE, nil) end
		player:SetAttribute(Names.RAINBOW_HELD, nil)
	end)
end

return RainbowService
