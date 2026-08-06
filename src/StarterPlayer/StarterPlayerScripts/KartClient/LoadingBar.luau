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

	-- Edge-to-edge along the very bottom. Scale width, not offset, so it
	-- spans any window without a resize handler.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 0, 1, -L.BarBottom)
	track.Size = UDim2.new(1, 0, 0, L.BarHeight)
	track.BackgroundColor3 = L.BarTrackColor
	-- Built hidden. Revealed by Start() once the splash is gone — see
	-- Config.Loading.BarSplashName for why.
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = L.BarFillColor
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Parent = track

	-- Faded toward the TAIL, so the bright end is the leading edge and it
	-- reads as a sweep rather than a growing rectangle.
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, L.BarGradientTail),
		NumberSequenceKeypoint.new(1, 0),
	})
	grad.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, L.BarTextInset, 1, -(L.BarBottom + L.BarHeight + L.BarTextBottom))
	label.Size = UDim2.fromOffset(320, 14)
	label.BackgroundTransparency = 1
	label.FontFace = Util.font(H.FontName, H.FontWeight)
	label.Text = L.BarText
	label.TextSize = L.BarTextSize
	label.TextColor3 = L.BarTextColor
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTransparency = 1
	-- Readable over a bright menu as well as a dark one.
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 1
	label.Parent = gui

	local self = setmetatable({
		gui = gui,
		track = track,
		fill = fill,
		label = label,
		done = false,
	}, LoadingBar)

	-- TRAILING DOTS. A batch can take seconds, and a bar that has not
	-- moved is indistinguishable from a game that has hung. The dots cost
	-- nothing and say "still here" during exactly those gaps.
	task.spawn(function()
		local n = 0
		while not self.done and self.gui.Parent do
			n = (n + 1) % 4
			self.label.Text = L.BarText .. string.rep(".", n)
			task.wait(1 / math.max(L.BarDotRate, 0.1))
		end
	end)

	return self
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
	self.done = true -- also stops the dot animation
	self.label.Text = L.BarDoneText
	self:Set(1)

	-- Held for BarMinShown from when it BECAME VISIBLE, not from now. A
	-- preload that finishes in 300ms would otherwise be a flicker, and a
	-- flicker reads as "something flashed", not as "it loaded".
	local visibleFor = os.clock() - (self.shownAt or os.clock())
	local hold = math.max(L.BarHoldWhenDone, L.BarMinShown - visibleFor)
	task.delay(hold, function()
		-- Faded, not destroyed on the spot: the bar reaching full is the
		-- only confirmation the player gets that it finished rather than
		-- gave up, so it has to be visible for a moment at 100%.
		local info = TweenInfo.new(L.BarFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self.fill, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(self.track, info, { BackgroundTransparency = 1 }):Play()
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
		-- The splash owns the screen until it destroys its own ScreenGui.
		-- Bounded, so a splash that never lifts cannot hide this forever.
		local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
		local deadline = os.clock() + L.BarSplashWait
		while os.clock() < deadline and pg:FindFirstChild(L.BarSplashName) do
			task.wait(0.1)
		end

		self.shownAt = os.clock()
		self.track.BackgroundTransparency = L.BarTrackTransparency
		self.fill.BackgroundTransparency = 0
		self.label.TextTransparency = 0.3
		self.label.TextStrokeTransparency = 0.55

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
