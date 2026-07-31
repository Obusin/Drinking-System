--[[
	RewardHud — the end-of-race results and payout screen.

	Five panels over a dimmed world, uncovered by one angled wipe:

		top      currency balances
		left     RESULTS, finishing order, and the bonus line
		right    LEVEL progress and the daily quest checklist
		mid      DRIVE STATS
		low      the payout, and CONTINUE

	IT RENDERS A PAYLOAD AND NOTHING ELSE.

	`Show(payload)` is handed a table and draws it. It does not read the
	world, does not compute a reward, and does not know whether a number
	is real. That is the seam: when `DataService` and the single grant
	path exist, the server sends the same table with banked numbers in it
	and no layout changes.

	`preview()` below builds a payload from what the client can already
	see, so the screen is testable today. Those numbers are not saved
	anywhere and the panel says so — see Rewards.PreviewNote. An unsaved
	number presented as a balance is a lie the player finds out about
	later, which is worse than an empty panel now.

	PAYLOAD
	-------
		standings { place, name, kart, score, isSelf }
		bonus     { amount, reason }            -- optional
		level     { n, max, progress, note }    -- optional
		xpGained  number                        -- optional, "+N XP"
		quests    { { text, done, progress } }  -- optional
		stats     { { icon, value } }           -- optional
		record    { value, best, isNew }        -- optional
		payout    { bolt, nitro }               -- optional
		balance   { bolt, nitro }               -- optional
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))
local Names = require(BloxKart:WaitForChild("Names"))
local Shared = require(BloxKart:WaitForChild("Match"))
local Standings = require(BloxKart:WaitForChild("Standings"))

local R = Config.Rewards
local H = Config.Hud

local FONT = Util.font(H.FontName, H.FontWeight)

local RewardHud = {}
RewardHud.__index = RewardHud

--=====================================================================
--  SMALL BUILDERS
--=====================================================================
local function text(parent: Instance, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Text = ""
	l.Parent = parent
	return l
end

local function panel(parent: Instance, pos: UDim2, size: UDim2, anchor: Vector2): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = R.PanelColor
	f.BackgroundTransparency = R.PanelTransparency
	f.BorderSizePixel = 0
	f.AnchorPoint = anchor
	f.Position = pos
	f.Size = size
	f.Rotation = R.PanelTilt
	f.Parent = parent
	return f
end

local function icon(parent: Instance, id: string, px: number, tag: string): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.Size = UDim2.fromOffset(px, px)
	i.Image = id
	i.Parent = parent
	Util.verifyImage(i, id, tag)
	return i
end

-- Rolls a number up rather than snapping to it. Most of why a results
-- screen reads as a reward rather than as a receipt.
local function countUp(label: TextLabel, to: number, prefix: string, suffix: string?)
	local from = 0
	local t0 = os.clock()
	local conn
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / R.CountUpTime, 0, 1)
		local v = math.floor(from + (to - from) * Util.smoothstep(a) + 0.5)
		label.Text = prefix .. tostring(v) .. (suffix or "")
		if a >= 1 then
			conn:Disconnect()
		end
	end)
	return conn
end

--=====================================================================
--  PREVIEW PAYLOAD
--
--  Everything here is derived from what the client can already see. It
--  exists so the screen can be built and judged before the economy is,
--  and it goes away the day the server sends the real thing.
--=====================================================================
local function nameFor(kart: Instance): string
	local uid = kart:GetAttribute(Names.OWNER)
	local p = typeof(uid) == "number" and Players:GetPlayerByUserId(uid)
	if p then
		return p.DisplayName
	end
	-- Bots reach here. BotService stamps RACER_NAME so they arrive with
	-- the name they raced under rather than as "Racer".
	return tostring(kart:GetAttribute(Names.RACER_NAME) or "Racer")
end

function RewardHud.preview(): { [string]: any }
	local me = Players.LocalPlayer
	local standings, myPlace = {}, nil

	for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
		local place = kart:GetAttribute(Shared.FINISH_PLACE)
		if typeof(place) == "number" then
			local mine = kart:GetAttribute(Names.OWNER) == me.UserId
			if mine then
				myPlace = place
			end
			table.insert(standings, {
				place = place,
				name = nameFor(kart),
				kart = "BLOXKART",
				-- The real progress score the race already tracks, not a
				-- number derived from placement — deriving it would make
				-- the score column a second, worse rendering of the
				-- column next to it.
				score = kart:GetAttribute(Standings.ATTRIBUTE) or 0,
				isSelf = mine,
			})
		end
	end
	table.sort(standings, function(a, b)
		return a.place < b.place
	end)

	local bolt = 0
	if myPlace then
		bolt = R.BoltForPlace[myPlace] or R.BoltFloor
	end

	local mine = nil
	for _, e in standings do
		if e.isSelf then
			mine = e
		end
	end

	return {
		standings = standings,
		payout = { bolt = bolt, nitro = 0 },
		record = if mine then { value = mine.score, isNew = myPlace == 1 } else nil,
	}
end

--=====================================================================
--  BUILD
--=====================================================================
function RewardHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartRewards"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8 -- above MatchHud; this is the modal moment
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = gui

	----------------------------------------------------------------
	-- The wipe band. Oversized and rotated so its edges never enter
	-- frame — a wipe you can see the end of stops being a wipe.
	----------------------------------------------------------------
	local band = Instance.new("Frame")
	band.BackgroundColor3 = R.WipeColor
	band.BorderSizePixel = 0
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Size = UDim2.fromScale(1.4, 2.2)
	band.Rotation = R.WipeAngle
	band.Position = UDim2.fromScale(-0.8, 0.5)
	band.Visible = false
	band.ZIndex = 50
	band.Parent = gui

	----------------------------------------------------------------
	-- Top bar — balances
	----------------------------------------------------------------
	local top = panel(gui, UDim2.fromScale(0.5, 0), UDim2.new(1, 0, 0, 64), Vector2.new(0.5, 0))
	top.Rotation = 0
	top.BackgroundTransparency = 0

	local balBolt = text(top, R.ValueSize, R.TextColor)
	balBolt.AnchorPoint = Vector2.new(1, 0.5)
	balBolt.Position = UDim2.new(1, -76, 0.5, 0)
	balBolt.Size = UDim2.fromOffset(150, 40)
	balBolt.TextXAlignment = Enum.TextXAlignment.Right

	local balBoltIcon = icon(top, R.BoltIcon, 38, "RewardHud")
	balBoltIcon.AnchorPoint = Vector2.new(1, 0.5)
	balBoltIcon.Position = UDim2.new(1, -24, 0.5, 0)

	local balNitro = text(top, R.ValueSize, R.TextColor)
	balNitro.AnchorPoint = Vector2.new(1, 0.5)
	balNitro.Position = UDim2.new(1, -250, 0.5, 0)
	balNitro.Size = UDim2.fromOffset(120, 40)
	balNitro.TextXAlignment = Enum.TextXAlignment.Right

	local balNitroIcon = icon(top, R.NitroIcon, 34, "RewardHud")
	balNitroIcon.AnchorPoint = Vector2.new(1, 0.5)
	balNitroIcon.Position = UDim2.new(1, -206, 0.5, 0)

	----------------------------------------------------------------
	-- Results, left
	----------------------------------------------------------------
	local left = panel(gui, UDim2.fromScale(0.04, 0.14), UDim2.fromScale(0.42, 0.7), Vector2.new(0, 0))

	local resTitle = text(left, R.TitleSize, R.AccentColor)
	resTitle.Text = "RESULTS"
	resTitle.Position = UDim2.fromOffset(28, 14)
	resTitle.Size = UDim2.fromOffset(320, 44)

	local rows = Instance.new("Frame")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(22, 68)
	rows.Size = UDim2.new(1, -44, 1, -150)
	rows.Parent = left

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = rows

	local bonus = text(left, R.RowSize, R.AccentColor)
	bonus.AnchorPoint = Vector2.new(0.5, 1)
	bonus.Position = UDim2.new(0.5, 0, 1, -44)
	bonus.Size = UDim2.new(1, -40, 0, 30)
	bonus.TextXAlignment = Enum.TextXAlignment.Center

	local bonusWhy = text(left, R.SubSize, R.DimTextColor)
	bonusWhy.AnchorPoint = Vector2.new(0.5, 1)
	bonusWhy.Position = UDim2.new(0.5, 0, 1, -16)
	bonusWhy.Size = UDim2.new(1, -40, 0, 26)
	bonusWhy.TextXAlignment = Enum.TextXAlignment.Center
	bonusWhy.TextWrapped = true

	----------------------------------------------------------------
	-- Progression, right top — level bar + quest checklist
	----------------------------------------------------------------
	local right = panel(gui, UDim2.fromScale(0.96, 0.14), UDim2.fromScale(0.48, 0.32), Vector2.new(1, 0))

	local lvl = text(right, R.TitleSize, R.AccentColor)
	lvl.Position = UDim2.fromOffset(28, 12)
	lvl.Size = UDim2.fromOffset(360, 42)

	local barBack = Instance.new("Frame")
	barBack.BackgroundColor3 = Color3.fromRGB(58, 58, 62)
	barBack.BorderSizePixel = 0
	barBack.Position = UDim2.fromOffset(30, 58)
	barBack.Size = UDim2.new(0, 250, 0, 10)
	barBack.Parent = right

	local barFill = Instance.new("Frame")
	barFill.BackgroundColor3 = R.AccentColor
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.Parent = barBack

	local lvlNote = text(right, R.SubSize, R.DimTextColor)
	lvlNote.Position = UDim2.fromOffset(30, 76)
	lvlNote.Size = UDim2.fromOffset(260, 22)

	-- What THIS race earned, next to the bar it filled. The level number
	-- alone answers "where am I"; this answers "what did I just do",
	-- which is the question a results screen exists for.
	local xpGain = text(right, R.ValueSize, R.AccentColor)
	xpGain.Position = UDim2.fromOffset(30, 100)
	xpGain.Size = UDim2.fromOffset(260, 32)

	local quests = Instance.new("Frame")
	quests.BackgroundTransparency = 1
	quests.Position = UDim2.new(0, 310, 0, 16)
	quests.Size = UDim2.new(1, -336, 1, -32)
	quests.Parent = right

	local qLayout = Instance.new("UIListLayout")
	qLayout.Padding = UDim.new(0, 10)
	qLayout.SortOrder = Enum.SortOrder.LayoutOrder
	qLayout.Parent = quests

	----------------------------------------------------------------
	-- Drive stats, middle
	----------------------------------------------------------------
	local mid = panel(gui, UDim2.fromScale(0.505, 0.49), UDim2.fromScale(0.2, 0.35), Vector2.new(0, 0))

	local statTitle = text(mid, R.TitleSize - 6, R.TextColor)
	statTitle.Text = "DRIVE STATS"
	statTitle.Position = UDim2.fromOffset(20, 10)
	statTitle.Size = UDim2.fromOffset(240, 36)

	local statList = Instance.new("Frame")
	statList.BackgroundTransparency = 1
	statList.Position = UDim2.fromOffset(22, 52)
	statList.Size = UDim2.new(1, -44, 1, -70)
	statList.Parent = mid

	local sLayout = Instance.new("UIListLayout")
	sLayout.Padding = UDim.new(0, 8)
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sLayout.Parent = statList

	----------------------------------------------------------------
	-- Record + payout, lower right
	----------------------------------------------------------------
	local low = panel(gui, UDim2.fromScale(0.96, 0.49), UDim2.fromScale(0.44, 0.35), Vector2.new(1, 0))

	local recTitle = text(low, R.RowSize, R.AccentColor)
	recTitle.AnchorPoint = Vector2.new(0.5, 0)
	recTitle.Position = UDim2.new(0.5, 0, 0, 12)
	recTitle.Size = UDim2.new(1, -40, 0, 28)
	recTitle.TextXAlignment = Enum.TextXAlignment.Center

	local recValue = text(low, R.BigSize, R.TextColor)
	recValue.AnchorPoint = Vector2.new(0.5, 0)
	recValue.Position = UDim2.new(0.5, 0, 0, 40)
	recValue.Size = UDim2.new(1, -40, 0, 70)
	recValue.TextXAlignment = Enum.TextXAlignment.Center

	local recBest = text(low, R.SubSize, R.DimTextColor)
	recBest.AnchorPoint = Vector2.new(0.5, 0)
	recBest.Position = UDim2.new(0.5, 0, 0, 112)
	recBest.Size = UDim2.new(1, -40, 0, 22)
	recBest.TextXAlignment = Enum.TextXAlignment.Center

	-- The payout strip: the loudest thing on the panel, as in the
	-- reference. It is the answer to "what did I just earn".
	local pay = Instance.new("Frame")
	pay.BackgroundColor3 = R.AccentColor
	pay.BorderSizePixel = 0
	pay.AnchorPoint = Vector2.new(0.5, 1)
	pay.Position = UDim2.new(0.5, 0, 1, -16)
	pay.Size = UDim2.new(1, -36, 0, 74)
	pay.Parent = low

	local payBolt = text(pay, R.BigSize - 10, Color3.fromRGB(20, 20, 20))
	payBolt.AnchorPoint = Vector2.new(1, 0.5)
	payBolt.Position = UDim2.new(1, -74, 0.5, 0)
	payBolt.Size = UDim2.fromOffset(240, 60)
	payBolt.TextXAlignment = Enum.TextXAlignment.Right

	local payIcon = icon(pay, R.BoltIcon, 44, "RewardHud")
	payIcon.AnchorPoint = Vector2.new(1, 0.5)
	payIcon.Position = UDim2.new(1, -18, 0.5, 0)

	local payNitro = text(pay, R.ValueSize, Color3.fromRGB(20, 20, 20))
	payNitro.Position = UDim2.fromOffset(22, 0)
	payNitro.Size = UDim2.new(0, 200, 1, 0)

	local note = text(low, R.SubSize, R.DimTextColor)
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.new(0.5, 0, 1, -94)
	note.Size = UDim2.new(1, -40, 0, 20)
	note.TextXAlignment = Enum.TextXAlignment.Center

	----------------------------------------------------------------
	-- Continue
	----------------------------------------------------------------
	local go = Instance.new("TextButton")
	go.BackgroundColor3 = R.AccentColor
	go.BorderSizePixel = 0
	go.AnchorPoint = Vector2.new(1, 1)
	go.Position = UDim2.fromScale(1, 1)
	go.Size = UDim2.fromOffset(330, 84)
	go.FontFace = FONT
	go.TextSize = 40
	go.TextColor3 = Color3.fromRGB(18, 18, 18)
	go.Text = "DRIVE!  ▶"
	go.AutoButtonColor = true
	go.Parent = gui

	local self = setmetatable({
		gui = gui,
		dim = dim,
		band = band,
		panels = { top, left, right, mid, low },
		-- Captured ONCE, at build. Reading a panel's current position as
		-- its home is wrong the moment the screen is dismissed
		-- mid-tween: the partial position becomes the new home and every
		-- later show starts further off. Positions are authored here, so
		-- here is where they are remembered.
		homes = { top.Position, left.Position, right.Position, mid.Position, low.Position },
		rows = rows,
		rowPool = {},
		quests = quests,
		questPool = {},
		statList = statList,
		statPool = {},
		balBolt = balBolt,
		balNitro = balNitro,
		bonus = bonus,
		bonusWhy = bonusWhy,
		lvl = lvl,
		barFill = barFill,
		lvlNote = lvlNote,
		xpGain = xpGain,
		recTitle = recTitle,
		recValue = recValue,
		recBest = recBest,
		payBolt = payBolt,
		payNitro = payNitro,
		note = note,
		go = go,
		tweens = {},
		showing = false,
	}, RewardHud)

	go.Activated:Connect(function()
		self:Hide()
	end)

	return self
end

--=====================================================================
--  ROW POOLS
--
--  Pooled rather than rebuilt: this panel is shown once a round for a
--  fixed handful of rows, and destroying a dozen instances per race to
--  create a dozen identical ones is work with nothing to show for it.
--=====================================================================
function RewardHud:_row(i: number): Frame
	local row = self.rowPool[i]
	if row then
		return row
	end

	row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 42)
	row.LayoutOrder = i
	row.Parent = self.rows

	local place = text(row, R.RowSize, R.DimTextColor)
	place.Name = "Place"
	place.Size = UDim2.fromOffset(46, 42)

	local who = text(row, R.RowSize, R.TextColor)
	who.Name = "Who"
	who.Position = UDim2.fromOffset(52, -7)
	who.Size = UDim2.new(1, -190, 0, 42)

	local kart = text(row, R.SubSize, R.DimTextColor)
	kart.Name = "Kart"
	kart.Position = UDim2.fromOffset(52, 11)
	kart.Size = UDim2.new(1, -190, 0, 30)

	local score = text(row, R.ValueSize, R.TextColor)
	score.Name = "Score"
	score.AnchorPoint = Vector2.new(1, 0)
	score.Position = UDim2.new(1, 0, 0, 0)
	score.Size = UDim2.fromOffset(130, 42)
	score.TextXAlignment = Enum.TextXAlignment.Right

	self.rowPool[i] = row
	return row
end

function RewardHud:_quest(i: number): Frame
	local q = self.questPool[i]
	if q then
		return q
	end

	q = Instance.new("Frame")
	q.BackgroundTransparency = 1
	q.Size = UDim2.new(1, 0, 0, 34)
	q.LayoutOrder = i
	q.Parent = self.quests

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.BackgroundColor3 = Color3.fromRGB(58, 58, 62)
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(30, 30)
	box.Parent = q

	local tick = text(box, 26, Color3.fromRGB(20, 20, 20))
	tick.Name = "Tick"
	tick.Size = UDim2.fromScale(1, 1)
	tick.TextXAlignment = Enum.TextXAlignment.Center
	tick.Text = "✓"
	tick.Visible = false

	local what = text(q, R.RowSize, R.TextColor)
	what.Name = "What"
	what.Position = UDim2.fromOffset(44, 0)
	what.Size = UDim2.new(1, -50, 1, 0)

	self.questPool[i] = q
	return q
end

function RewardHud:_stat(i: number): Frame
	local s = self.statPool[i]
	if s then
		return s
	end

	s = Instance.new("Frame")
	s.BackgroundTransparency = 1
	s.Size = UDim2.new(1, 0, 0, 34)
	s.LayoutOrder = i
	s.Parent = self.statList

	local ic = icon(s, "", 28, "RewardHud")
	ic.Name = "Icon"

	local v = text(s, R.ValueSize, R.TextColor)
	v.Name = "Value"
	v.Position = UDim2.fromOffset(44, 0)
	v.Size = UDim2.new(1, -50, 1, 0)

	self.statPool[i] = s
	return s
end

--=====================================================================
--  SHOW
--=====================================================================
function RewardHud:Show(payload)
	if self.showing then
		return
	end
	self.showing = true
	payload = payload or {}

	----------------------------------------------------------------
	-- Standings
	----------------------------------------------------------------
	local standings = payload.standings or {}
	for i, row in self.rowPool do
		row.Visible = i <= #standings
	end
	for i, entry in standings do
		local row = self:_row(i)
		row.Visible = true
		row.Place.Text = ("%d."):format(entry.place or i)
		row.Who.Text = tostring(entry.name or "?")
		row.Kart.Text = string.upper(tostring(entry.kart or ""))
		row.Score.Text = tostring(entry.score or "")
		local c = if entry.isSelf then R.AccentColor else R.TextColor
		row.Who.TextColor3 = c
		row.Score.TextColor3 = c
	end

	----------------------------------------------------------------
	-- Bonus
	----------------------------------------------------------------
	local b = payload.bonus
	self.bonus.Visible = b ~= nil
	self.bonusWhy.Visible = b ~= nil
	if b then
		self.bonus.Text = ("BONUS  +%d"):format(b.amount or 0)
		self.bonusWhy.Text = tostring(b.reason or "")
	end

	----------------------------------------------------------------
	-- Level and quests
	----------------------------------------------------------------
	local lv = payload.level
	if lv then
		self.lvl.Text = ("LEVEL %d/%d"):format(lv.n or 0, lv.max or 0)
		self.lvlNote.Text = tostring(lv.note or "")
		-- The bar is animated from where the race STARTED, not snapped
		-- to where it ended. A bar that is already full when you look at
		-- it never rewarded anything.
		local to = math.clamp(lv.progress or 0, 0, 1)
		self.barFill.Size = UDim2.fromScale(0, 1)
		task.delay(R.WipeTime, function()
			if self.showing then
				TweenService
					:Create(
						self.barFill,
						TweenInfo.new(R.CountUpTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Size = UDim2.fromScale(to, 1) }
					)
					:Play()
			end
		end)
	else
		self.lvl.Text = ""
		self.barFill.Size = UDim2.fromScale(0, 1)
		self.lvlNote.Text = ""
	end

	local gained = payload.xpGained or 0
	self.xpGain.Visible = gained > 0
	self.xpGain.Text = "+0 XP"

	local qs = payload.quests or {}
	for i, q in self.questPool do
		q.Visible = i <= #qs
	end
	for i, q in qs do
		local w = self:_quest(i)
		w.Visible = true
		w.What.Text = tostring(q.text or "")
		w.Box.Tick.Visible = q.done == true
		w.Box.BackgroundColor3 = if q.done then R.AccentColor else Color3.fromRGB(58, 58, 62)
		w.What.TextColor3 = if q.done then R.TextColor else R.DimTextColor
	end

	----------------------------------------------------------------
	-- Drive stats
	----------------------------------------------------------------
	local st = payload.stats or {}
	for i, s in self.statPool do
		s.Visible = i <= #st
	end
	for i, s in st do
		local w = self:_stat(i)
		w.Visible = true
		w.Icon.Image = tostring(s.icon or "")
		w.Value.Text = tostring(s.value or 0)
	end

	----------------------------------------------------------------
	-- Record
	----------------------------------------------------------------
	local rec = payload.record
	self.recTitle.Visible = rec ~= nil
	self.recValue.Visible = rec ~= nil
	self.recBest.Visible = rec ~= nil
	if rec then
		self.recTitle.Text = if rec.isNew then "NEW RECORD!" else "SCORE"
		self.recValue.Text = "0"
		self.recBest.Text = if rec.best then ("Current record:  %d"):format(rec.best) else ""
	end

	----------------------------------------------------------------
	-- Payout
	----------------------------------------------------------------
	local pay = payload.payout or {}
	self.payBolt.Text = "+0"
	self.payNitro.Text = if (pay.nitro or 0) > 0 then ("+%d NITRO"):format(pay.nitro) else ""

	-- Says out loud that nothing was banked. The alternative is a
	-- number the player later discovers was never real.
	self.note.Text = if R.Preview then R.PreviewNote else ""
	self.note.Visible = R.Preview

	----------------------------------------------------------------
	-- Balances
	----------------------------------------------------------------
	local bal = payload.balance or {}
	self.balBolt.Text = tostring(bal.bolt or 0)
	self.balNitro.Text = tostring(bal.nitro or 0)

	----------------------------------------------------------------
	-- Reveal
	----------------------------------------------------------------
	self.gui.Enabled = true
	self:_wipe(function()
		if rec then
			table.insert(self.tweens, countUp(self.recValue, rec.value or 0, ""))
		end
		table.insert(self.tweens, countUp(self.payBolt, pay.bolt or 0, "+"))
		if gained > 0 then
			table.insert(self.tweens, countUp(self.xpGain, gained, "+", " XP"))
		end
	end)
end

-- The geometric wipe: one angled band crosses the screen, and the
-- panels are already in place behind it by the time it has passed.
-- Staggering them slightly behind the band's edge is what makes it read
-- as one gesture rather than five separate animations.
function RewardHud:_wipe(after: () -> ())
	local band = self.band
	band.Visible = true
	band.Position = UDim2.fromScale(-0.8, 0.5)

	TweenService
		:Create(
			self.dim,
			TweenInfo.new(R.WipeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 - R.Dim }
		)
		:Play()

	local sweep = TweenService:Create(
		band,
		TweenInfo.new(R.WipeTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(1.8, 0.5) }
	)
	sweep:Play()
	sweep.Completed:Connect(function()
		band.Visible = false
	end)

	for i, p in self.panels do
		local home = self.homes[i]
		p.Position = home - UDim2.fromScale(R.PanelSlide, 0)
		p.Visible = true
		task.delay(R.PanelStagger * (i - 1), function()
			if not self.showing then
				return
			end
			TweenService
				:Create(
					p,
					TweenInfo.new(R.PanelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Position = home }
				)
				:Play()
		end)
	end

	task.delay(R.WipeTime, function()
		if self.showing then
			after()
		end
	end)
end

function RewardHud:Hide()
	if not self.showing then
		return
	end
	self.showing = false
	for _, c in self.tweens do
		if c.Connected then
			c:Disconnect()
		end
	end
	table.clear(self.tweens)
	for i, p in self.panels do
		p.Position = self.homes[i]
	end
	self.gui.Enabled = false
	self.dim.BackgroundTransparency = 1
end

function RewardHud:IsShowing(): boolean
	return self.showing
end

function RewardHud:Destroy()
	self:Hide()
	self.gui:Destroy()
end

return RewardHud
