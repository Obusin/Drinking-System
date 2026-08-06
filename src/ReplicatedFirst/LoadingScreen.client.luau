--[[
	LoadingScreen — splash + geometric-wipe reveal.

	Lives in ReplicatedFirst so it can replace Roblox's default loading screen
	before anything else replicates. It shows a black cover + the brand icon
	from nothing (instant), holds until the game has loaded and the menu has
	been built underneath, then plays the SAME angled geometric wipe used
	everywhere else in the game (Config.Rewards.Wipe*) to reveal the menu.

	Self-contained on purpose: it does the wipe itself rather than handing off
	to KartClient's Transition module, so there's no cross-container timing to
	get wrong. It reuses Config.Rewards so the wipe reads as the same gesture.

	Place-agnostic: covers any join. In the lobby it waits for the menu to
	exist before wiping; in a race place there's no menu, so it just settles
	and wipes into the track.
--]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Kill the default screen first thing — before any WaitForChild could yield
-- and let it flash.
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- The splash is held for at least this long even if the game loads instantly
-- (it usually does in Studio), so it reads as a deliberate "getting ready"
-- beat instead of a blink — and gives real joins time to stream in behind it.
-- Tune within ~5–10s to taste.
local MIN_SHOWN = 6
local BG = Color3.fromRGB(0, 0, 0)
local GOLD = Color3.fromRGB(245, 197, 66)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=====================================================================
--  Black splash + icon — built from nothing so it shows this frame
--=====================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "BloxKartLoading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10000 -- above everything, including the menu underneath
gui.ResetOnSpawn = false
gui.Parent = playerGui

local cover = Instance.new("Frame")
cover.Name = "Cover"
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = BG
cover.BorderSizePixel = 0
cover.ZIndex = 1
cover.Parent = gui

-- Text stand-in up front; the real icon swaps in once it replicates.
local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromScale(0.5, 0.14)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.Text = "GO KARTS GO"
title.TextColor3 = GOLD
title.TextScaled = true
title.ZIndex = 2
title.Parent = cover

local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(0.24, 0.34)
icon.BackgroundTransparency = 1
icon.ScaleType = Enum.ScaleType.Fit
icon.ImageTransparency = 1 -- hidden until a real image loads
icon.ZIndex = 2
icon.Parent = cover

-- Gentle breathing pulse so a black screen doesn't read as frozen.
local pulseConn: RBXScriptConnection?
pulseConn = RunService.RenderStepped:Connect(function()
	local s = 1 + 0.04 * math.sin(os.clock() * 3)
	icon.Size = UDim2.fromScale(0.24 * s, 0.34 * s)
end)

--=====================================================================
--  Pull the shared wipe look (and icon) once BloxKart replicates
--=====================================================================
local R: any = nil
local bloxKart = ReplicatedStorage:WaitForChild("BloxKart", 20)
if bloxKart then
	pcall(function()
		local Config = require(bloxKart:WaitForChild("Config"))
		R = Config.Rewards
	end)
end

-- Try the brand image, but KEEP the text stand-in visible behind it: the
-- current WipeImage id is a Decal (won't render as an ImageLabel), so hiding
-- the text would leave a blank icon. A valid Image id will simply cover the
-- text; until then the text carries the splash.
local wipeImage = (R and R.WipeImage) or ""
if typeof(wipeImage) == "string" and wipeImage ~= "" then
	icon.Image = wipeImage
	icon.ImageTransparency = 0
end

local WIPE_COLOR = (R and R.WipeColor) or GOLD
local WIPE_ANGLE = (R and R.WipeAngle) or 14
local WIPE_TIME = (R and R.WipeTime) or 0.45
local WIPE_BAND_T = (R and R.WipeBandTransparency) or 0

--=====================================================================
--  Hold until loaded + the menu exists, then wipe to it
--=====================================================================
-- Kept as a literal rather than requiring Names: this runs in
-- ReplicatedFirst, before ReplicatedStorage is guaranteed populated, and a
-- loading screen that yields on a require is a loading screen that can hang.
-- If Names.PREVIEW_READY is ever renamed, rename it here too.
local READY_ATTR = "BloxKartPreviewReady"
local PREVIEW_WAIT = 6 -- seconds, then uncover regardless

local shownAt = os.clock()

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- In the lobby the menu is built right after load — wait for it so the wipe
-- uncovers onto a menu that is already there, not a blank frame. In a race
-- place this simply times out and we wipe into the track.
local isLobby = false
if bloxKart then
	pcall(function()
		isLobby = require(bloxKart:WaitForChild("Place")).isLobby()
	end)
end
if isLobby then
	playerGui:WaitForChild("BloxKartMainMenu", 6)

	-- AND WAIT FOR THE KART TO BE WEARING THE RIGHT THING.
	--
	-- The saved look comes from a DataStore round trip, so there is
	-- always a gap between the menu existing and the kart being dressed.
	-- Uncovering during that gap shows a stock kart that then changes,
	-- which reads as the customisation not having saved — and it is the
	-- only part of loading the player must not see.
	--
	-- So the splash covers it. This is the whole reason the wait is here
	-- rather than a fixed delay: it ends when the work is actually done,
	-- which is both faster on a warm join and correct on a cold one.
	--
	-- FAILS OPEN. If nothing ever raises the flag — no profile, no menu
	-- stage, a client that got here another way — we uncover anyway after
	-- the timeout. A stock kart is a bad outcome; a splash that never
	-- lifts is a much worse one.
	if not player:GetAttribute(READY_ATTR) then
		local waitUntil = os.clock() + PREVIEW_WAIT
		while os.clock() < waitUntil and not player:GetAttribute(READY_ATTR) do
			task.wait(0.05)
		end
	end
end

local elapsed = os.clock() - shownAt
if elapsed < MIN_SHOWN then
	task.wait(MIN_SHOWN - elapsed)
end

if pulseConn then
	pulseConn:Disconnect()
	pulseConn = nil
end

-- The angled band: same rotated rectangle the Transition module uses, big
-- enough to span the screen corner-to-corner at the midpoint.
local band = Instance.new("Frame")
band.Name = "Band"
band.BackgroundColor3 = WIPE_COLOR
band.BackgroundTransparency = WIPE_BAND_T
band.BorderSizePixel = 0
band.AnchorPoint = Vector2.new(0.5, 0.5)
band.Size = UDim2.fromScale(2.4, 3)
band.Rotation = WIPE_ANGLE
band.Position = UDim2.fromScale(-1.5, 0.5)
band.ZIndex = 5
band.Parent = gui

-- Icon fades as the band arrives.
TweenService:Create(icon, TweenInfo.new(WIPE_TIME * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	ImageTransparency = 1,
}):Play()
TweenService:Create(title, TweenInfo.new(WIPE_TIME * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	TextTransparency = 1,
}):Play()

-- Sweep in to full cover…
local inTween = TweenService:Create(
	band,
	TweenInfo.new(WIPE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	{ Position = UDim2.fromScale(0.5, 0.5) }
)
inTween:Play()
inTween.Completed:Wait()

-- …drop the black splash while the band hides it (menu is now behind us)…
cover.BackgroundTransparency = 1
icon.Visible = false
title.Visible = false

-- …then sweep out, revealing the menu, and clean up.
local outTween = TweenService:Create(
	band,
	TweenInfo.new(WIPE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
	{ Position = UDim2.fromScale(2.5, 0.5) }
)
outTween:Play()
outTween.Completed:Wait()

gui:Destroy()
