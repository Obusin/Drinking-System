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

local R = Config.Rewards

local Transition = {}
Transition.__index = Transition

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
	band.BorderSizePixel = 0
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Size = UDim2.fromScale(2.4, 3)
	band.Rotation = R.WipeAngle
	band.Position = UDim2.fromScale(-1.5, 0.5)
	band.Parent = gui

	return setmetatable({ gui = gui, band = band, busy = false }, Transition)
end

-- Sweeps once. `onCovered` fires on the frame the band is across the
-- screen. Returns false if one is already running — a second wipe
-- stacked on the first would uncover what the first was hiding.
function Transition:Play(onCovered: (() -> ())?): boolean
	if self.busy then
		-- Still do the work. Dropping it would leave the caller's change
		-- unmade, which is worse than making it a frame early.
		if onCovered then
			onCovered()
		end
		return false
	end
	self.busy = true

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

	inTween.Completed:Connect(function()
		if onCovered then
			-- Guarded: a callback that throws must not leave the screen
			-- covered in yellow forever.
			local ok, err = pcall(onCovered)
			if not ok then
				warn("[Transition] covered callback failed: " .. tostring(err))
			end
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

function Transition:Destroy()
	self.gui:Destroy()
end

return Transition
