--[[
	LoadingBar — "still loading", without taking the menu away.

	The splash covers the part the player MUST NOT see: the menu half-built
	and the kart wearing the wrong thing. Everything after that — icons,
	banners, item art — can arrive late without hurting anything, and
	holding a black screen for it would be spending the player's time to
	avoid a cosmetic pop.

	So the menu opens on time and this says the rest is still coming. A
	thin bar at the bottom edge, no modal, no input blocking.

	IT REPORTS REAL WORK. The progress is the fraction of assets actually
	resolved by ContentProvider, not a timer dressed up as one. A fake bar
	that finishes before the game does is worse than no bar: it teaches
	the player that the bar means nothing, and the one time something IS
	genuinely stuck they will not believe it either.

	It removes itself when done and leaves nothing behind.
--]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local H = Config.Hud
local L = Config.Loading

local LoadingBar = {}
LoadingBar.__index = LoadingBar

-- EVERY ASSET THE CONFIG NAMES, found by walking it.
--
-- Deliberately generic rather than a hand-kept list: the catalogue,
-- rewards, items and HUD all carry rbxassetid strings, and a list would
-- be wrong the first time anybody added an icon. Walking the tables
-- cannot go stale.
--
-- Cycle-safe via `seen`, because Config tables do reference each other.
local function collectAssets(node: any, out: { string }, seen: { [any]: boolean }, depth: number)
	if depth > 6 or type(node) ~= "table" or seen[node] then
		return
	end
	seen[node] = true
	for _, v in node do
		if type(v) == "string" then
			if v:match("^rbxassetid://%d+$") then
				table.insert(out, v)
			end
		elseif type(v) == "table" then
			collectAssets(v, out, seen, depth + 1)
		end
	end
end

function LoadingBar.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartLoadingBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40 -- above the menu, below the transition wipe
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -L.BarBottom)
	root.Size = UDim2.fromOffset(L.BarWidth, L.BarHeight + 18)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -L.BarHeight - 4)
	label.Size = UDim2.fromOffset(L.BarWidth, 14)
	label.BackgroundTransparency = 1
	label.FontFace = Util.font(H.FontName, H.FontWeight)
	label.Text = L.BarText
	label.TextSize = L.BarTextSize
	label.TextColor3 = L.BarTextColor
	label.TextTransparency = 0.25
	label.Parent = root

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, 0)
	track.Size = UDim2.fromOffset(L.BarWidth, L.BarHeight)
	track.BackgroundColor3 = L.BarTrackColor
	track.BackgroundTransparency = L.BarTrackTransparency
	track.BorderSizePixel = 0
	track.Parent = root

	local trackRound = Instance.new("UICorner")
	trackRound.CornerRadius = UDim.new(1, 0)
	trackRound.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = L.BarFillColor
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillRound = Instance.new("UICorner")
	fillRound.CornerRadius = UDim.new(1, 0)
	fillRound.Parent = fill

	return setmetatable({ gui = gui, root = root, fill = fill, label = label, done = false }, LoadingBar)
end

function LoadingBar:Set(fraction: number)
	-- Tweened rather than snapped: batches land in chunks, and a bar that
	-- jumps in steps reads as broken even when the numbers are right.
	TweenService:Create(
		self.fill,
		TweenInfo.new(L.BarEase, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) }
	):Play()
end

function LoadingBar:Finish()
	if self.done then
		return
	end
	self.done = true
	self:Set(1)
	task.delay(L.BarHoldWhenDone, function()
		-- Faded, not destroyed on the spot: the bar reaching full is the
		-- only confirmation the player gets that it finished rather than
		-- gave up, so it has to be visible for a moment at 100%.
		local info = TweenInfo.new(L.BarFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self.fill, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.label, info, { TextTransparency = 1 }):Play()
		local track = self.fill.Parent :: Frame
		TweenService:Create(track, info, { BackgroundTransparency = 1 }):Play()
		task.delay(L.BarFadeTime + 0.05, function()
			self.gui:Destroy()
		end)
	end)
end

-- Preload everything the config names, reporting real progress.
--
-- Batched so the bar moves: PreloadAsync on one huge list yields until
-- the whole lot is done and the bar would sit at zero and then snap.
--
-- Runs on its own thread and never blocks the menu — that is the entire
-- point of showing this instead of extending the splash.
function LoadingBar:Start()
	task.spawn(function()
		local assets, seen = {}, {}
		collectAssets(Config, assets, seen, 0)

		-- Deduplicated: the same icon appears in several tables and
		-- preloading it twice would make the total wrong as well as slow.
		local unique, added = {}, {}
		for _, id in assets do
			if not added[id] then
				added[id] = true
				table.insert(unique, id)
			end
		end

		if #unique == 0 then
			self:Finish()
			return
		end

		local batch = math.max(L.BarBatch, 1)
		local doneCount = 0
		for i = 1, #unique, batch do
			local slice = {}
			for j = i, math.min(i + batch - 1, #unique) do
				table.insert(slice, unique[j])
			end
			-- pcall: a bad or unapproved asset id THROWS here, and one of
			-- those must not strand the bar at 60% forever. The offending
			-- ids are already named by Util.verifyImage elsewhere.
			pcall(function()
				ContentProvider:PreloadAsync(slice)
			end)
			doneCount += #slice
			self:Set(doneCount / #unique)
		end
		self:Finish()
	end)
end

function LoadingBar:Destroy()
	self.gui:Destroy()
end

return LoadingBar
