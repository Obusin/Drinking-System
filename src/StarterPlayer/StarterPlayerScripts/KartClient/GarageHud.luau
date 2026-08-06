--[[
	GarageHud — customising the kart on the menu stage.

	PREVIEW UNTIL DONE.
	-------------------
	Picking a part dresses the LOCAL MenuStage kart and NOTHING ELSE. The
	profile is written only when the player presses DONE, and CANCEL puts
	back whatever the server last confirmed.

	This replaced a write-per-click, which had no way to back out: by the
	time you had looked at four bodies all four had been saved, and the
	last one you happened to glance at was what you owned. "Cancel" could
	not exist because there was nothing left to cancel.

	Batching also collapses five profile writes and five mesh swaps on the
	live kart into one of each.

	`Close()` on its own is CANCEL. Anything that dismisses the garage
	without the player pressing Done — a hotkey, a teleport, the menu
	closing underneath it — must not silently save a half-finished look.

	INTENT ONLY, STILL. What crosses the remote is slot names and
	catalogue ids, never a mesh or a colour, so the server stays the thing
	that decides and an invented id is refused by name.

	SELECTION IS PER SLOT. Body, Wheels and Paint are chosen independently
	and re-applied as a whole look, so switching a body never silently
	drops the paint you had.
--]]

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Loadout = require(BloxKart:WaitForChild("Loadout"))
local Util = require(BloxKart:WaitForChild("Util"))
local UiSound = require(script.Parent:WaitForChild("UiSound"))

local G = Config.Garage
local log = Util.logger("GarageHud", G.Debug)
local FONT = Util.font(Config.Hud.FontName, Config.Hud.FontWeight)

local BLACK = Color3.fromRGB(7, 8, 10)
local GOLD = Color3.fromRGB(255, 198, 28)
local WHITE = Color3.fromRGB(252, 252, 245)
local MUTED = Color3.fromRGB(198, 197, 186)
local PANEL = Color3.fromRGB(15, 16, 19)

local GarageHud = {}
GarageHud.__index = GarageHud

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function itemsFor(slot: string)
	if slot == "Body" then
		return G.Bodies
	elseif slot == "Wheels" then
		return G.Wheels
	end
	return G.Paints
end

--=====================================================================
--  BUILD
--=====================================================================
function GarageHud.new(opts: {
	getKart: () -> Instance?,
	onZoom: (number) -> (),
	onClose: () -> (),
})
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartGarage"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 32 -- above the menu, below the transition wipe
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Fixed design canvas, same trick the menu uses: lay out once at 16:9
	-- and scale the whole thing to fit, so nothing reflows on a narrow
	-- window.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(1600, 900)
	root.Parent = gui

	local rootScale = Instance.new("UIScale")
	rootScale.Parent = root

	-- The panel sits on ONE side, so the kart it is describing stays
	-- visible beside it rather than behind it.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.fromRGB(9, 10, 13)
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromScale(0.685, 0.135)
	panel.Size = UDim2.fromScale(0.285, 0.73)
	panel.Parent = root
	corner(panel, 14)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.06, 0.02)
	title.Size = UDim2.fromScale(0.6, 0.07)
	title.FontFace = FONT
	title.Text = "GARAGE"
	title.TextColor3 = WHITE
	title.TextSize = 26
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	-- DONE and CANCEL, and the difference is real now: picking a part is
	-- a preview until Done writes it. The button was already labelled
	-- DONE while only closing the panel, which was the honest word for
	-- what it did and the wrong word for what a player expected.
	--
	-- Gold on DONE, muted on CANCEL: the committing action is the one
	-- that should read as the default.
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Done"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.fromScale(0.95, 0.022)
	closeBtn.Size = UDim2.fromScale(0.12, 0.058)
	closeBtn.BackgroundColor3 = PANEL
	closeBtn.BorderSizePixel = 0
	closeBtn.FontFace = FONT
	closeBtn.Text = "DONE"
	closeBtn.TextColor3 = GOLD
	closeBtn.TextSize = 15
	closeBtn.Parent = panel
	corner(closeBtn, 8)
	UiSound.bind(closeBtn)

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "Cancel"
	cancelBtn.AnchorPoint = Vector2.new(1, 0)
	-- Immediately left of DONE: 0.95 - its 0.12 width - a 0.015 gap.
	cancelBtn.Position = UDim2.fromScale(0.815, 0.022)
	cancelBtn.Size = UDim2.fromScale(0.12, 0.058)
	cancelBtn.BackgroundColor3 = PANEL
	cancelBtn.BorderSizePixel = 0
	cancelBtn.FontFace = FONT
	cancelBtn.Text = "CANCEL"
	cancelBtn.TextColor3 = MUTED
	cancelBtn.TextSize = 15
	cancelBtn.Parent = panel
	corner(cancelBtn, 8)
	UiSound.bind(cancelBtn)

	-- Slot tabs
	local tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromScale(0.05, 0.105)
	tabRow.Size = UDim2.fromScale(0.9, 0.062)
	tabRow.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	-- Item grid
	local grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromScale(0.05, 0.185)
	grid.Size = UDim2.fromScale(0.9, 0.715)
	grid.ScrollBarThickness = 4
	grid.ScrollBarImageColor3 = Color3.fromRGB(60, 62, 70)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = panel
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(126, 126)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.fromScale(0.5, 0.985)
	hint.Size = UDim2.fromScale(0.9, 0.05)
	hint.FontFace = FONT
	hint.Text = "RIGHT-DRAG TO ORBIT  ·  SCROLL TO ZOOM"
	hint.TextColor3 = MUTED
	hint.TextSize = 13
	hint.Parent = panel

	local self = setmetatable({
		gui = gui,
		root = root,
		rootScale = rootScale,
		grid = grid,
		tabRow = tabRow,
		tabs = {},
		slot = G.Slots[1],
		-- What is currently worn. Kept whole so re-applying one slot never
		-- drops another.
		chosen = { Body = "stock", Wheels = "stock", Paint = "stock" },
		-- The last state the SERVER confirmed. Cancel restores to this,
		-- and it is deliberately not "whatever was on screen when the
		-- garage opened" — those differ when a commit was partly refused,
		-- and the server's answer is the one that is true.
		committed = { Body = "stock", Wheels = "stock", Paint = "stock" },
		opts = opts,
		open = false,
	}, GarageHud)

	for i, slot in G.Slots do
		local tab = Instance.new("TextButton")
		tab.Name = slot
		tab.Size = UDim2.new(1 / #G.Slots, -4, 1, 0)
		tab.LayoutOrder = i
		tab.BackgroundColor3 = PANEL
		tab.BorderSizePixel = 0
		tab.FontFace = FONT
		tab.Text = G.SlotLabels[slot] or slot:upper()
		tab.TextColor3 = MUTED
		tab.TextSize = 14
		tab.AutoButtonColor = false
		tab.Parent = tabRow
		corner(tab, 8)
		UiSound.bind(tab)
		tab.Activated:Connect(function()
			self:SetSlot(slot)
		end)
		self.tabs[slot] = tab
	end

	closeBtn.Activated:Connect(function()
		self:Done()
	end)
	cancelBtn.Activated:Connect(function()
		self:Cancel()
	end)

	self:SetSlot(self.slot)

	-- STARTED IMMEDIATELY, before the remote is even resolved.
	--
	-- Its first act is to hide the stage kart, and every millisecond
	-- before that is a millisecond of stock kart on screen. Waiting for
	-- WaitForChild(GARAGE_REMOTE) first would hand back exactly the flash
	-- this exists to remove. It waits on `gotState` internally and has
	-- its own timeout, so it does not care when the listener below
	-- attaches — or whether it ever does.
	self:_primePreview()

	-- The server pushes `equipped` on profile load and after every equip, so
	-- the garage opens on what the player is actually wearing rather than on
	-- defaults. Asked for as well, in case this built after the push landed.
	task.spawn(function()
		local remote = BloxKart:WaitForChild(Names.GARAGE_REMOTE, 20)
		if not remote then
			return
		end
		remote.OnClientEvent:Connect(function(action, equipped)
			if action == "equipped" then
				self:ApplyEquipped(equipped)
			end
		end)
		remote:FireServer("refresh")
	end)

	return self
end

--=====================================================================
--  ITEM TILES
--=====================================================================

-- A mesh preview. Built in its own thread because CreateMeshPartAsync
-- fetches over the network — a grid of these must not block the UI.
local function meshPreview(parent: Instance, meshId: string)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Position = UDim2.fromScale(0.08, 0.06)
	vp.Size = UDim2.fromScale(0.84, 0.62)
	vp.Ambient = Color3.fromRGB(190, 190, 200)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.5)
	vp.Parent = parent

	task.spawn(function()
		local ok, part = pcall(function()
			return AssetService:CreateMeshPartAsync(meshId)
		end)
		if not ok or not part or not vp.Parent then
			return
		end
		part.Anchored = true
		part.CFrame = CFrame.new()
		part.Parent = vp

		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		-- Framed off the part's own size so a big body and a small wheel
		-- both fill the tile instead of one being a speck.
		local extent = math.max(part.Size.X, part.Size.Y, part.Size.Z)
		local dist = (extent * 0.5) / math.tan(math.rad(15)) * 1.35
		cam.CFrame = CFrame.lookAt(Vector3.new(0.5, 0.4, 1).Unit * dist, Vector3.zero)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end)
	return vp
end

function GarageHud:_tile(item, index: number)
	local isPaint = self.slot == "Paint"
	local selected = self.chosen[self.slot] == item.id

	local tile = Instance.new("TextButton")
	tile.Name = item.id
	tile.LayoutOrder = index
	tile.BackgroundColor3 = if selected then Color3.fromRGB(32, 33, 40) else PANEL
	tile.BorderSizePixel = 0
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.Parent = self.grid
	corner(tile, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Transparency = if selected then 0 else 1
	stroke.Parent = tile

	if isPaint then
		local sw = Instance.new("Frame")
		sw.Position = UDim2.fromScale(0.14, 0.1)
		sw.Size = UDim2.fromScale(0.72, 0.56)
		sw.BorderSizePixel = 0
		-- No colour = factory finish. Shown dark rather than white so it
		-- does not read as "paint it white".
		sw.BackgroundColor3 = item.colour or Color3.fromRGB(70, 72, 80)
		sw.Parent = tile
		corner(sw, 8)
	elseif item.mesh ~= "" then
		meshPreview(tile, item.mesh)
	else
		local stock = Instance.new("TextLabel")
		stock.BackgroundTransparency = 1
		stock.Position = UDim2.fromScale(0.08, 0.06)
		stock.Size = UDim2.fromScale(0.84, 0.62)
		stock.FontFace = FONT
		stock.Text = "◇"
		stock.TextColor3 = MUTED
		stock.TextSize = 40
		stock.Parent = tile
	end

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.96)
	label.Size = UDim2.fromScale(0.92, 0.24)
	label.FontFace = FONT
	label.Text = item.name
	label.TextColor3 = if selected then GOLD else WHITE
	label.TextSize = 13
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = tile

	UiSound.bind(tile)
	tile.Activated:Connect(function()
		self:Choose(item.id)
	end)
end

function GarageHud:SetSlot(slot: string)
	self.slot = slot
	for id, tab in self.tabs do
		local on = id == slot
		tab.BackgroundColor3 = if on then GOLD else PANEL
		tab.TextColor3 = if on then BLACK else MUTED
	end
	for _, c in self.grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i, item in itemsFor(slot) do
		self:_tile(item, i)
	end
end

--=====================================================================
--  WEARING IT
--=====================================================================

-- Everything currently chosen, resolved from keys to what the kart needs.
function GarageHud:_look()
	local look = {}
	for _, item in G.Bodies do
		if item.id == self.chosen.Body then
			look.body = item.mesh
		end
	end
	for _, item in G.Wheels do
		if item.id == self.chosen.Wheels then
			look.wheel = item.mesh
		end
	end
	for _, item in G.Paints do
		if item.id == self.chosen.Paint then
			look.paint = item.colour
		end
	end
	return look
end

function GarageHud:Choose(id: string)
	if self.chosen[self.slot] == id then
		return
	end
	self.chosen[self.slot] = id
	self:SetSlot(self.slot) -- redraw so the selection ring moves

	-- Re-applies the WHOLE look, not just the slot that changed: a mesh
	-- swap arrives with its own colour, so changing a body would drop the
	-- paint if paint were not restated with it.
	self:_dressStage()

	-- NOTHING IS SENT HERE ANY MORE. Picking is a PREVIEW; the save
	-- happens on Done. See Commit/Revert below for why.
	log("preview %s = %q (unsaved)", self.slot, id)
end

-- SAVE ON DONE, NOT ON EVERY CLICK.
--
-- Firing a write per selection meant there was no such thing as backing
-- out: by the time you had looked at four bodies, all four had been
-- saved and the last one you glanced at was what you owned. "Cancel"
-- could not exist, because there was nothing left to cancel.
--
-- Batching also collapses five profile writes and five mesh swaps on the
-- live kart into one of each.
--
-- The client still sends INTENT ONLY — slot names and catalogue ids,
-- never a mesh or a colour — so the server remains the thing that
-- decides, and a client that invents an id gets it refused by name.
-- Put whatever we currently believe is equipped onto the stage kart.
--
-- Factored out because it is needed at FOUR moments and the stage kart
-- may not exist at any given one: on a pick, when the server pushes
-- state, when the garage is opened, and after a Cancel. Missing any of
-- them leaves the preview on stock while the profile says otherwise —
-- which is exactly how a rejoin looked like it had lost the customisation.
--
-- Safe to call with no kart. That is the NORMAL case on join: the server
-- pushes `equipped` as soon as the profile loads, which is routinely
-- before the MenuStage clone has been built.
function GarageHud:_dressStage()
	local kart = self.opts.getKart()
	if not kart then
		log("stage kart not built yet — preview will be dressed on open")
		return
	end
	-- Through Loadout, so the tracker and the garage cannot disagree
	-- about what is currently on the kart.
	Loadout.set(self.chosen)
	task.spawn(Loadout.dress, kart)
end

-- Show/hide the stage kart WITHOUT touching its authored look.
--
-- LocalTransparencyModifier is render-only and client-side: it never
-- writes Transparency, so art with deliberately see-through parts is not
-- flattened by hiding and then restored wrong. Setting Transparency
-- directly here would permanently destroy that information the first
-- time the menu opened.
local function setStageAlpha(kart: Instance, hidden: number)
	for _, d in kart:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = hidden
		end
	end
end

local function fadeStageIn(kart: Instance, seconds: number)
	if seconds <= 0 then
		setStageAlpha(kart, 0)
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			setStageAlpha(kart, 1 - a)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end


-- FIRST PAINT. The one job: never show a kart wearing the wrong thing.
--
-- The profile comes from a DataStore round trip, so there is always a
-- gap between the menu appearing and the look being known. Nothing can
-- close that gap. The only decision is what is on screen during it, and
-- showing a stock kart that later pops into the real one reads exactly
-- like the customisation having been lost — which is how it was reported.
--
-- So: hide the kart the moment it exists, wait for the server's state,
-- dress it, then fade in. Bounded by PreviewMaxWait, because an
-- invisible kart is a worse failure than a stock one and a profile that
-- never loads must not leave the menu empty.
--
-- Runs once. Later pushes go through EnsurePreview, which dresses a kart
-- that is already visible and needs no fade.
function GarageHud:_primePreview()
	if self.primed then
		return
	end
	self.primed = true

	-- TRACKED, NOT CHASED. This used to poll for the stage kart once,
	-- dress it, and stop — so anything that built or rebuilt that kart
	-- outside that one window won, and on a cold join the stage was
	-- usually built AFTER the window closed. That is why the menu kept
	-- showing the default kart while the profile was perfectly correct.
	--
	-- Loadout.track keeps asking, for the whole session, and re-dresses
	-- whenever EITHER the kart or the look changes. A late stage, a
	-- rebuilt stage and an equip are all the same event to it.
	Loadout.track(self.opts.getKart, function()
		-- Raised the first time a kart is actually wearing the right
		-- thing. Only once, and only after a SERVER-confirmed look — a
		-- local preview pick must not release the loading screen.
		if Loadout.isConfirmed() and not self.revealed then
			self.revealed = true
			-- SAY SO OUT LOUD. Every line this module printed was about
			-- something not working yet, so a correct run looked
			-- identical to a broken one — you had to infer success from
			-- the absence of complaints. This is the line that says it
			-- worked, and what it landed on.
			local eq = Loadout.get()
			log(
				"preview dressed and revealed: Body=%s Wheels=%s Paint=%s",
				tostring(eq.Body),
				tostring(eq.Wheels),
				tostring(eq.Paint)
			)
			Players.LocalPlayer:SetAttribute(Names.PREVIEW_READY, true)
			local kart = self.opts.getKart()
			if kart then
				fadeStageIn(kart, G.PreviewFadeTime or 0)
			end
		end
	end)

	-- HIDE IT UNTIL THEN, and release regardless after PreviewMaxWait.
	--
	-- Fails open on purpose: a profile that never loads must cost a stock
	-- kart, never an invisible one or a splash that will not lift.
	task.spawn(function()
		local kart
		for _ = 1, 40 do
			kart = self.opts.getKart()
			if kart then
				break
			end
			task.wait(0.25)
		end
		if not kart then
			log("no stage kart to prime")
			Players.LocalPlayer:SetAttribute(Names.PREVIEW_READY, true)
			return
		end
		if (G.PreviewFadeTime or 0) > 0 and not self.revealed then
			setStageAlpha(kart, 1)
		end
		-- REVEAL ON THE CONDITION, NOT ON A CALLBACK.
		--
		-- This waited only for the tracker's onApplied, so a run where
		-- the tracker had nothing to dress — no kart found yet — sat on
		-- the full timeout even though the look had been confirmed
		-- seconds earlier. The log said exactly that: `<- server:` at
		-- :08, then `no confirmed look after 8s` at :16.
		--
		-- Polling the two facts that actually matter — do we know the
		-- look, and is the kart wearing it — does not care which async
		-- job finished first, or whether either bothered to call back.
		local deadline = os.clock() + (G.PreviewMaxWait or 8)
		while os.clock() < deadline and not self.revealed do
			local now = self.opts.getKart()
			if now and Loadout.isConfirmed() and Loadout.isDressed(now) then
				self.revealed = true
				local eq = Loadout.get()
				-- NAMES THE KART. "preview ready" was reported once on a
				-- kart nobody could see — a stage the menu does not
				-- display — and without the path there was nothing in the
				-- log to tell that apart from a real success.
				log(
					"preview ready on %s: Body=%s Wheels=%s Paint=%s",
					now:GetFullName(),
					tostring(eq.Body),
					tostring(eq.Wheels),
					tostring(eq.Paint)
				)
				Players.LocalPlayer:SetAttribute(Names.PREVIEW_READY, true)
				fadeStageIn(now, G.PreviewFadeTime or 0)
			end
			task.wait(0.1)
		end

		if not self.revealed then
			log("no confirmed look after %.0fs — showing the kart as built", G.PreviewMaxWait or 8)
			self.revealed = true
			Players.LocalPlayer:SetAttribute(Names.PREVIEW_READY, true)
		end

		-- BACKSTOP, and it runs whether or not the reveal already
		-- happened. This is the one thing in the whole path that is
		-- allowed to be unconditional, because the failure it prevents —
		-- an INVISIBLE kart — is worse than every problem it could mask.
		--
		-- Hiding and revealing are two async jobs, and if any ordering
		-- ever lets a hide land after a reveal the kart is gone for the
		-- session with nothing to say so. Forcing it visible here costs
		-- one loop and removes that outcome entirely.
		local now = self.opts.getKart()
		if now then
			setStageAlpha(now, 0)
		end
	end)
end

-- DRESS THE PREVIEW AS SOON AS THERE IS SOMETHING TO DRESS.
--
-- `StageKart()` resolves lazily — the MenuStage is cloned and its rig
-- built asynchronously — so on join the server's `equipped` push
-- routinely lands BEFORE the kart exists. `_dressStage` then no-ops and
-- nothing ever comes back, which is why a rejoin showed a stock kart on
-- the menu while the profile was perfectly correct.
--
-- So this WAITS for it, briefly, instead of firing once into nothing.
--
-- The generation counter matters: two pushes arriving close together
-- (the boot refresh, then the real one once the profile loads) would
-- otherwise leave two loops racing, and the older could win and paint
-- stale state over the newer. Bumping `previewGen` retires whatever is
-- in flight.
function GarageHud:EnsurePreview()
	self.previewGen = (self.previewGen or 0) + 1
	local gen = self.previewGen
	task.spawn(function()
		for _ = 1, 24 do -- ~12s, then give up quietly
			if gen ~= self.previewGen then
				return -- a newer push superseded this one
			end
			if self.opts.getKart() then
				self:_dressStage()
				return
			end
			task.wait(0.5)
		end
		log("stage kart never appeared — preview left undressed")
	end)
end

function GarageHud:Commit()
	local remote = BloxKart:FindFirstChild(Names.GARAGE_REMOTE)
	if not remote then
		-- Genuinely broken rather than merely refused, and worth a warn
		-- rather than a debug line: the garage cannot save at all.
		warn("[GarageHud] GARAGE_REMOTE is missing — nothing can be saved. Is GarageService.start() running?")
		return
	end
	local picks = table.clone(self.chosen)
	log("commit -> Body=%s Wheels=%s Paint=%s", tostring(picks.Body), tostring(picks.Wheels), tostring(picks.Paint))
	remote:FireServer("commit", picks)
end

-- Back to the last state the SERVER confirmed, not to whatever was on
-- screen when the garage opened. Those differ if a previous commit was
-- partly refused, and the server's answer is the one that is true.
function GarageHud:Revert()
	local restored = false
	for slot, id in self.committed do
		if self.chosen[slot] ~= id then
			restored = true
		end
		self.chosen[slot] = id
	end
	log("revert -> Body=%s Wheels=%s Paint=%s", tostring(self.chosen.Body), tostring(self.chosen.Wheels), tostring(self.chosen.Paint))
	if not restored then
		return
	end
	self:SetSlot(self.slot)
	self:_dressStage()
end

-- The server's answer, authoritative. Applied whether it agreed or refused,
-- so a rejected pick cannot leave the garage showing something the player
-- does not actually own.
function GarageHud:ApplyEquipped(equipped)
	if type(equipped) ~= "table" then
		-- NOT A WARNING. This fires on EVERY join and always has.
		--
		-- `refresh` is sent the moment the remote resolves, which is
		-- normally about a second before the profile finishes loading, so
		-- the first reply is always nil. It is a race we start on purpose
		-- and the real push follows.
		--
		-- It was a warn, and that was a mistake that cost two rounds of
		-- debugging: a warning that fires every single time is not a
		-- warning, it is noise wearing a warning's clothes, and it sent
		-- us hunting a failure on a run where nothing had failed.
		--
		-- The genuine version of this — a look that NEVER arrives — is
		-- reported by the primer after PreviewMaxWait, once, and means it.
		log("no equipped state yet (profile still loading) — waiting for the push")
		return
	end
	-- The primer waits on this before it reveals the kart.
	self.gotState = true
	-- AUTHORITATIVE. The tracker re-dresses every kart it watches off
	-- this, so the menu stage is corrected even if it was built long
	-- after the push arrived.
	Loadout.set(equipped, true)
	log(
		"<- server: Body=%s Wheels=%s Paint=%s",
		tostring(equipped.Body),
		tostring(equipped.Wheels),
		tostring(equipped.Paint)
	)
	for slot, id in equipped do
		if self.chosen[slot] ~= nil and type(id) == "string" then
			self.chosen[slot] = id
			-- This is now the confirmed baseline that Cancel returns to.
			self.committed[slot] = id
		end
	end
	self:SetSlot(self.slot)
	-- WAITS for the stage kart, because this fires on profile load and
	-- that is normally before the menu has built one.
	self:EnsurePreview()
end

--=====================================================================
--  OPEN / CLOSE
--=====================================================================
function GarageHud:Open()
	if self.open then
		return
	end
	self.open = true
	self.gui.Enabled = true
	UiSound.play("Open")

	-- RE-DRESS ON EVERY OPEN, and ask the server again.
	--
	-- The server pushes `equipped` once, when the profile finishes
	-- loading. That push regularly lands BEFORE the MenuStage kart exists
	-- — the stage is cloned and its rig built asynchronously — so
	-- ApplyEquipped had nothing to dress and the preview sat on stock for
	-- the rest of the session. That is the "rejoin shows a default kart"
	-- symptom, and it is a timing bug, not a persistence one.
	--
	-- `self.chosen` is already the authoritative state from that push, so
	-- this needs no new data: it applies what we were told to a kart that
	-- did not exist at the time. The refresh covers the opposite order,
	-- where the garage opened before the profile resolved at all.
	self:_dressStage()
	local remote = BloxKart:FindFirstChild(Names.GARAGE_REMOTE)
	if remote then
		remote:FireServer("refresh")
	end

	self:Fit()
	self.root.Position = UDim2.fromScale(0.52, 0.5)
	TweenService:Create(
		self.root,
		TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.5) }
	):Play()
end

-- Two ways out, and they are not the same thing.
--
--   Done   commit what is on screen, then leave.
--   Cancel put back what the server last confirmed, then leave.
--
-- `Close()` on its own is Cancel — anything that dismisses the garage
-- without the player pressing Done (a hotkey, a teleport, the menu
-- closing under it) must not silently save a half-finished look.
function GarageHud:Done()
	self:Commit()
	self:Close()
end

function GarageHud:Cancel()
	self:Revert()
	self:Close()
end

function GarageHud:Close()
	if not self.open then
		return
	end
	self.open = false
	self.gui.Enabled = false
	UiSound.play("Close")
	-- The camera goes back where it was. Leaving a player zoomed into a
	-- wheel arch after they have left the garage reads as a stuck camera.
	self.opts.onZoom(0)
	self.opts.onClose()
end

function GarageHud:IsOpen(): boolean
	return self.open
end

function GarageHud:Fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.Y > 0 then
		self.rootScale.Scale = math.clamp(math.min(vp.X / 1600, vp.Y / 900), 0.2, 1.35)
	end
end

function GarageHud:Destroy()
	self.gui:Destroy()
end

return GarageHud
