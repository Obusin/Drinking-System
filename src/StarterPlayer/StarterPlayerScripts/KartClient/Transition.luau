--[[
	Transition — the geometric wipe, used as a scene change.

	ONE BAND FOR THE WHOLE GAME. An angled bar crosses the screen; at the
	moment it covers everything a callback fires, and whatever changed
	behind it is already done by the time the far edge passes.

	That midpoint is the entire point. A teleport to the grid, a results
	panel opening, a results panel closing — each of them is a cut, and a
	cut you can see is a glitch while a cut you can't is a transition.

	WHY A CALLBACK AND NOT TWO FUNCTIONS
	------------------------------------
	`cover()` then `reveal()` invites a caller to forget the second one,
	or to do its work on a different frame than the one the screen was
	actually covered on. One call that hands you the covered moment is
	the version that cannot be half-used.

	Shares Config.Rewards for angle and colour, so the wipe reads as the
	same gesture wherever it happens.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local R = Config.Rewards

local Transition = {}
Transition.__index = Transition

local function safeCall(fn: (() -> ())?)
	if not fn then
		return
	end
	local ok, err = pcall(fn)
	if not ok then
		warn("[Transition] covered callback failed: " .. tostring(err))
	end
end

function Transition.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartTransition"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above every other HUD by a clear margin. A transition that
	-- something else draws over is not covering anything.
	gui.DisplayOrder = 50
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Big enough that a rotated rectangle still spans the screen corner
	-- to corner at the midpoint. A band you can see the end of stops
	-- being a wipe and becomes a passing shape.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BackgroundColor3 = R.WipeColor
	band.BackgroundTransparency = R.WipeBandTransparency
	band.BorderSizePixel = 0
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Size = UDim2.fromScale(2.4, 3)
	band.Rotation = R.WipeAngle
	band.Position = UDim2.fromScale(-1.5, 0.5)
	band.Parent = gui

	-- The mark, on the band but not rotated with it. Parented to the GUI
	-- rather than to the band so the band's angle does not tip it: a logo
	-- at 14 degrees reads as a mistake rather than as style.
	local mark = Instance.new("ImageLabel")
	mark.Name = "Mark"
	-- No plate behind the art. An ImageLabel defaults to a solid white
	-- box, which reads as a border around a transparent PNG.
	mark.BackgroundTransparency = 1
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromOffset(R.WipeImageSize, R.WipeImageSize)
	mark.ScaleType = Enum.ScaleType.Fit
	mark.Image = R.WipeImage
	mark.ImageTransparency = 1
	mark.Visible = R.WipeImage ~= ""
	mark.Parent = gui
	if R.WipeImage ~= "" then
		Util.verifyImage(mark, R.WipeImage, "Transition")
	end

	return setmetatable({ gui = gui, band = band, mark = mark, busy = false, held = false }, Transition)
end

-- Sweeps once. `onCovered` fires on the frame the band is across the
-- screen. Returns false if one is already running — a second wipe
-- stacked on the first would uncover what the first was hiding.
function Transition:Play(onCovered: (() -> ())?): boolean
	if self.busy then
		-- Still do the work. Dropping it would leave the caller's change
		-- unmade, which is worse than making it a frame early.
		safeCall(onCovered)
		return false
	end
	self.busy = true
	self.held = false

	local half = R.WipeTime
	self.band.Position = UDim2.fromScale(-1.5, 0.5)
	self.gui.Enabled = true

	-- In: eases OUT, so it arrives fast and settles. Out: eases IN, so
	-- it leaves lazily and then goes. Both halves easing the same way
	-- reads as one slide passing by rather than as a cut.
	local inTween = TweenService:Create(
		self.band,
		TweenInfo.new(half, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.5) }
	)
	inTween:Play()

	-- The mark fades up behind the band as it arrives, so it is already
	-- there when the screen is covered rather than appearing after.
	if self.mark.Visible then
		self.mark.ImageTransparency = 1
		TweenService
			:Create(self.mark, TweenInfo.new(half * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = 0,
			})
			:Play()
	end

	inTween.Completed:Connect(function()
		-- Guarded: a callback that throws must not leave the screen
		-- covered in yellow forever.
		safeCall(onCovered)

		-- Held at full cover before leaving, so the mark is read rather
		-- than glimpsed. This is the only pause in the whole transition
		-- and it is what makes it feel authored.
		if self.mark.Visible and R.WipeImageHold > 0 then
			task.wait(R.WipeImageHold)
		end

		if self.mark.Visible then
			TweenService
				:Create(self.mark, TweenInfo.new(half * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					ImageTransparency = 1,
				})
				:Play()
		end

		local outTween = TweenService:Create(
			self.band,
			TweenInfo.new(half, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(2.5, 0.5) }
		)
		outTween:Play()
		outTween.Completed:Connect(function()
			self.gui.Enabled = false
			self.busy = false
		end)
	end)

	return true
end

-- Covers the screen and STAYS covered. This is for cross-place
-- teleports: once Roblox starts moving the player, uncovering is worse
-- than holding the stinger because there is no local scene to reveal.
function Transition:CoverHold(onCovered: (() -> ())?): boolean
	if self.busy then
		safeCall(onCovered)
		return false
	end
	self.busy = true
	self.held = true

	local half = R.WipeTime
	self.band.Position = UDim2.fromScale(-1.5, 0.5)
	self.gui.Enabled = true

	local inTween = TweenService:Create(
		self.band,
		TweenInfo.new(half, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.5) }
	)
	inTween:Play()

	if self.mark.Visible then
		self.mark.ImageTransparency = 1
		TweenService
			:Create(self.mark, TweenInfo.new(half * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = 0,
			})
			:Play()
	end

	inTween.Completed:Connect(function()
		safeCall(onCovered)
	end)

	return true
end

-- Escape hatch for failed teleports. Successful teleports never call
-- this; the destination place replaces the whole client while covered.
function Transition:Release()
	if not self.gui.Enabled then
		self.busy = false
		self.held = false
		return
	end

	self.held = false
	if self.mark.Visible then
		TweenService
			:Create(self.mark, TweenInfo.new(R.WipeTime * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				ImageTransparency = 1,
			})
			:Play()
	end

	local outTween = TweenService:Create(
		self.band,
		TweenInfo.new(R.WipeTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Position = UDim2.fromScale(2.5, 0.5) }
	)
	outTween:Play()
	outTween.Completed:Connect(function()
		self.gui.Enabled = false
		self.busy = false
	end)
end

function Transition:Destroy()
	self.gui:Destroy()
end

return Transition
