--[[
	ThreatHud — what is behind you, along the bottom edge of the screen.

	BOTTOM OF THE SCREEN IS BEHIND YOU
	----------------------------------
	The whole design rests on that one convention, and it needs no
	legend: a strip of segments sits at the very bottom, and the one
	that lights IS the bearing. Dead centre is directly behind, left of
	centre is over your left shoulder. Nothing to learn, nothing to read.

	TWO LAYERS, DIFFERENT IN KIND
	-----------------------------
	  PROXIMITY  faint and wide. On whenever anyone is close, which in a
	             pack is most of the race — so it is deliberately dim
	             enough to be furniture. "Someone is there."
	  THREAT     bright, narrow and pulsing. Something is actually
	             inbound. Rare, and allowed to interrupt.

	Making both of these the same kind of mark is how a threat display
	becomes noise: if the common case looks like the urgent case, the
	urgent case stops meaning anything.

	WHY NOT A MIRROR, A MINIMAP BLIP, OR A PORTRAIT
	-----------------------------------------------
	Phone first. A rear-view mirror or a floating headshot costs real
	estate in the middle of a small screen and covers the road at exactly
	the moment you need it — the "giant enemy head" problem. This is a
	few pixels tall, carries no text, and never crosses the driving line.

	The face is rationed for the same reason: knowing WHO is on your
	bumper changes what you do about it, so it earns its place, but only
	when they are genuinely on you (RearIconRange, 18 studs) and only
	underneath the cluster.

	READS ONLY WHAT THE CLIENT CAN ALREADY SEE. Kart positions are
	replicated and `Projectiles.threatTo` already answers "is something
	coming" locally. No new remote, and nothing here is authoritative —
	it is a display that can be wrong for a frame without consequence.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Util = require(BloxKart:WaitForChild("Util"))

local H = Config.Hud

local ThreatHud = {}
ThreatHud.__index = ThreatHud

-- Headshots are fetched once per user and kept. GetUserThumbnailAsync
-- YIELDS and can fail, so it never runs on the render path: a miss
-- starts a background fetch and this frame simply has no icon, which is
-- correct — the icon is a bonus, not the warning.
-- `false` means TRIED AND FAILED, and storing that is the whole point.
-- An absent entry means never asked.
local headshots: { [number]: string | boolean } = {}
local fetching: { [number]: boolean } = {}

local function headshotFor(userId: number): string?
	local cached = headshots[userId]
	if cached ~= nil then
		-- A remembered failure returns nil WITHOUT asking again.
		--
		-- The first version cleared the in-flight flag and stored nothing
		-- on failure, so a headshot that would not load was re-requested
		-- ON EVERY FRAME — sixty web calls a second, for as long as that
		-- racer stayed on your bumper. The comment claimed it cached the
		-- failure. It did not; only the success was ever recorded, and
		-- the failure path looked identical to "never asked".
		return if type(cached) == "string" then cached else nil
	end
	if fetching[userId] then
		return nil
	end
	fetching[userId] = true
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		-- Recorded BEFORE the in-flight flag is cleared, so there is never
		-- a moment where both say "go ahead and ask".
		headshots[userId] = if ok and type(content) == "string" then content else false
		fetching[userId] = nil
	end)
	return nil
end

function ThreatHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartThreat"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1 -- under the cluster; this is the floor of the HUD
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local strip = Instance.new("Frame")
	strip.Name = "RearStrip"
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.new(0.5, 0, 1, -H.RearStripBottom)
	strip.Size = UDim2.new(H.RearStripWidth, 0, 0, H.RearSegmentHeight)
	strip.BackgroundTransparency = 1
	strip.Parent = gui

	local n = H.RearSegments
	local segments = {}
	for i = 1, n do
		local seg = Instance.new("Frame")
		seg.Name = "Seg" .. i
		-- Scale width so the strip fills whatever it is given, with the
		-- gaps taken out in pixels. One expression, no per-device sizes.
		seg.Size = UDim2.new(1 / n, -H.RearSegmentGap, 1, 0)
		seg.Position = UDim2.new((i - 1) / n, H.RearSegmentGap * 0.5, 0, 0)
		seg.BackgroundColor3 = H.RearIdleColor
		seg.BackgroundTransparency = H.RearIdleTransparency
		seg.BorderSizePixel = 0
		seg.Parent = strip

		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, H.RearSegmentRadius)
		round.Parent = seg

		segments[i] = seg
	end

	-- The face. Parented to the gui rather than the strip so it can sit
	-- ABOVE the strip without inheriting its four-pixel height.
	local icon = Instance.new("ImageLabel")
	icon.Name = "RearFace"
	icon.AnchorPoint = Vector2.new(0.5, 1)
	icon.Size = UDim2.fromOffset(H.RearIconSize, H.RearIconSize)
	icon.BackgroundTransparency = 1
	icon.ImageTransparency = 1
	icon.Visible = false
	icon.Parent = gui

	local iconRound = Instance.new("UICorner")
	iconRound.CornerRadius = UDim.new(1, 0)
	iconRound.Parent = icon

	return setmetatable({
		gui = gui,
		strip = strip,
		segments = segments,
		icon = icon,
		iconAlpha = 0,
		pulse = 0,
		visible = true,
		-- Throttled scan: the last reading, and when the next one is due.
		scanIn = 0,
		scanDist = nil,
		scanRight = 0,
		scanKart = nil,
		-- What is DRAWN, eased toward the scan above.
		at = 0.5,
		close = 0,
	}, ThreatHud)
end

function ThreatHud:SetVisible(on: boolean)
	self.visible = on
	self.gui.Enabled = on
end

-- Nearest kart BEHIND us, as (distance, rightness) where rightness is
-- -1 hard left, 0 dead astern, +1 hard right.
--
-- Measured against the simulation's own forward/up rather than world
-- axes, so it stays correct upside down on a loop — the same rule the
-- controller runs on.
local function nearestBehind(sim): (number?, number, Model?)
	local me = sim.model
	local pos = sim.pos
	local forward = sim.forward
	local right = forward:Cross(sim.up)
	if right.Magnitude < 1e-4 then
		return nil, 0, nil
	end
	right = right.Unit

	local bestDist, bestRight, bestKart = nil, 0, nil
	for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
		if kart == me then
			continue
		end
		local hitbox = kart.PrimaryPart
		if not hitbox then
			continue
		end
		local toward = hitbox.Position - pos
		local dist = toward.Magnitude
		if dist < 1e-3 or dist > H.RearRange then
			continue
		end
		-- BEHIND, not merely "not in front". A kart level with us
		-- alongside is not something the rear strip is about, and
		-- lighting it there is what makes a proximity display useless in
		-- a pack.
		local along = toward:Dot(forward)
		if along >= 0 then
			continue
		end
		if not bestDist or dist < bestDist then
			bestDist = dist
			bestRight = math.clamp(toward.Unit:Dot(right), -1, 1)
			bestKart = kart
		end
	end
	return bestDist, bestRight, bestKart
end

-- `eta` is seconds to impact from Projectiles.threatTo, or nil. Passed
-- in rather than recomputed: init.client already asks for it to drive
-- the INCOMING banner, and asking twice is two answers to one question.
function ThreatHud:Update(sim, eta: number?, dt: number)
	if not self.visible or not sim or not sim.model then
		return
	end

	-- SCANNED ON A CLOCK, DRAWN EVERY FRAME.
	--
	-- `nearestBehind` walks every tagged kart and allocates a fresh table
	-- from GetTagged each time. Doing that at frame rate is real work for
	-- a display whose answer changes over tenths of a second, and the
	-- simulation is on a MaxTimestep of 1/20 — so anything that drags the
	-- client under 20fps makes the KART ITSELF move slower than real
	-- time. A HUD is never worth that risk.
	--
	-- The reading is then eased toward, so a 12Hz scan still sweeps
	-- smoothly instead of stepping between cells.
	self.scanIn -= dt
	if self.scanIn <= 0 then
		self.scanIn = 1 / math.max(H.RearScanHz, 1)
		self.scanDist, self.scanRight, self.scanKart = nearestBehind(sim)
	end
	local dist, rightness, kart = self.scanDist, self.scanRight, self.scanKart
	-- The cached kart can be destroyed between scans.
	if kart and not kart.Parent then
		dist, kart = nil, nil
	end

	-- 0 far away, 1 on the bumper.
	local closeness = 0
	if dist then
		local span = math.max(H.RearRange - H.RearNearRange, 1e-3)
		closeness = 1 - math.clamp((dist - H.RearNearRange) / span, 0, 1)
	end

	-- The threat layer runs off the projectile warning, not off who is
	-- behind: the thing you act on is the missile, and it may have been
	-- fired by someone who is no longer there.
	local threat = 0
	if eta then
		threat = 1 - math.clamp(eta / H.IncomingLead, 0, 1)
	end

	if threat > 0 then
		local rate = H.RearPulseSlow + (H.RearPulseFast - H.RearPulseSlow) * threat
		self.pulse += dt * rate
	else
		self.pulse = 0
	end
	-- Biased into 0..1 so it never blinks fully out — a warning that
	-- disappears between pulses is easy to miss in exactly the moment it
	-- matters. Same rule as the wrong-way alert.
	local blink = (math.sin(self.pulse * math.pi * 2) + 1) * 0.5

	-- Where along the strip, 0..1. `rightness` is already a projection
	-- onto our own right vector, so it compresses toward the edges by
	-- itself and never needs an angle or an atan2.
	--
	-- Eased rather than taken raw: the scan above only runs at RearScanHz,
	-- and easing is what turns those steps back into a sweep.
	local atTarget = 0.5 + rightness * 0.5
	self.at = Util.approach(self.at, atTarget, H.RearEaseRate, dt)
	self.close = Util.approach(self.close, closeness, H.RearEaseRate, dt)
	local at = self.at
	closeness = self.close

	local n = #self.segments
	for i, seg in self.segments do
		-- Centre of this segment in the same 0..1 space.
		local centre = (i - 0.5) / n
		-- Spread stops the indicator stepping between cells like a
		-- stepper motor, which reads as broken rather than precise.
		local near = 1 - math.clamp(math.abs(centre - at) / math.max(H.RearSpread, 1e-3), 0, 1)
		local lit = closeness * near

		local colour = H.RearIdleColor
		local alpha = H.RearIdleTransparency
		if lit > 0 then
			colour = H.RearIdleColor:Lerp(H.RearCloseColor, lit)
			alpha = H.RearIdleTransparency + (0.15 - H.RearIdleTransparency) * lit
		end
		if threat > 0 then
			-- The threat layer paints the WHOLE strip, not a bearing.
			-- A missile you cannot see the source of has no bearing to
			-- report, and pretending otherwise points you the wrong way.
			local hot = threat * blink
			colour = colour:Lerp(H.RearThreatColor, hot)
			alpha = alpha + (0.05 - alpha) * hot
		end
		seg.BackgroundColor3 = colour
		seg.BackgroundTransparency = math.clamp(alpha, 0, 1)
	end

	----------------------------------------------------------------
	-- THE FACE — only when they are genuinely on you.
	----------------------------------------------------------------
	local image = nil
	if kart and dist and dist <= H.RearIconRange then
		local uid = kart:GetAttribute(Names.OWNER)
		-- Bots have no UserId and get no face. That is the honest answer:
		-- a placeholder head would say "a player is on you" when one is
		-- not, and who is behind you is the entire point of showing it.
		if typeof(uid) == "number" and uid > 0 then
			image = headshotFor(uid)
		end
	end

	local wanted = if image then 1 else 0
	self.iconAlpha = Util.approach(self.iconAlpha, wanted, 1 / math.max(H.RearIconFadeTime, 1e-3), dt)

	if image then
		self.icon.Image = image
	end
	if self.iconAlpha <= 0.01 then
		self.icon.Visible = false
	else
		self.icon.Visible = true
		self.icon.ImageTransparency = 1 - self.iconAlpha
		-- Sits on the strip's own bearing, so the face and the lit
		-- segment are the same piece of information rather than two.
		self.icon.Position = UDim2.new(
			0.5 + (at - 0.5) * H.RearStripWidth,
			0,
			1,
			-(H.RearStripBottom + H.RearSegmentHeight + 4)
		)
	end
end

function ThreatHud:Destroy()
	self.gui:Destroy()
end

return ThreatHud
