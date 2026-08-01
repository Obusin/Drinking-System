--[[
	MatchHud — everything the round loop puts on screen:

		centre    the 3-2-1-GO countdown
		top       a status line (waiting for racers / race starts in N)
		results   the finishing order when the round ends

	Same house style as the rest: no panels, outlined text, Zekton.

	The countdown deliberately owns the centre of the screen and nothing
	else ever does. It's the one moment the game needs you looking at one
	place, and it's the only time the middle isn't track.
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

local M = Config.Match
local H = Config.Hud
local P = Shared.Phase

local MatchHud = {}
MatchHud.__index = MatchHud

local FONT = Util.font(H.FontName, H.FontWeight)

local function label(parent: Instance, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = colour
	l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	l.TextStrokeTransparency = H.StrokeTransparency
	l.Text = ""
	l.Parent = parent
	return l
end

function MatchHud.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartMatch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5 -- above the instruments; it's a modal moment
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	----------------------------------------------------------------
	-- Countdown, dead centre
	----------------------------------------------------------------
	local count = label(gui, M.CountdownSize, M.CountdownColor)
	count.AnchorPoint = Vector2.new(0.5, 0.5)
	count.Position = UDim2.fromScale(0.5, 0.44)
	count.Size = UDim2.fromOffset(400, 220)
	count.TextTransparency = 1

	----------------------------------------------------------------
	-- Status line, under the lap counter
	----------------------------------------------------------------
	local status = label(gui, M.StatusSize, M.StatusColor)
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = M.StatusPosition
	status.Size = UDim2.fromOffset(560, 30)

	----------------------------------------------------------------
	-- Results board
	----------------------------------------------------------------
	local board = Instance.new("Frame")
	board.Name = "Results"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.5)
	board.Size = UDim2.fromOffset(M.ResultsWidth, 120)
	board.BackgroundTransparency = 1
	board.Visible = false
	board.Parent = gui

	local title = label(board, M.ResultsTitleSize, M.ResultsColor)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Text = "RESULTS"

	local rows = Instance.new("Frame")
	rows.Position = UDim2.fromOffset(0, 46)
	rows.Size = UDim2.new(1, 0, 1, -46)
	rows.BackgroundTransparency = 1
	rows.Parent = board

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 2)
	layout.Parent = rows

	return setmetatable({
		gui = gui,
		count = count,
		status = status,
		board = board,
		rows = rows,
		rowPool = {},
		shownRound = -1,
	}, MatchHud)
end

--=====================================================================
--  COUNTDOWN
--=====================================================================

-- One number, punched in and faded out. Scale-in rather than a plain
-- fade: a number that grows reads as a beat, and a beat is what a
-- countdown is.
function MatchHud:Countdown(n: number)
	self.count.Text = tostring(n)
	self.count.TextColor3 = M.CountdownColor
	self.count.TextSize = M.CountdownSize
	self.count.TextTransparency = 0

	TweenService:Create(self.count, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
end

function MatchHud:Go()
	self.count.Text = "GO!"
	self.count.TextColor3 = M.CountdownGoColor
	self.count.TextSize = M.CountdownGoSize
	self.count.TextTransparency = 0

	TweenService:Create(self.count, TweenInfo.new(M.CountdownFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
end

-- CROSSED THE LINE. Same slot as the countdown, because it is the same
-- kind of moment: one word, dead centre, and nothing else on screen
-- competing with it.
function MatchHud:Finish(place: number?)
	self.count.Text = if place then ("FINISH  ·  P%d"):format(place) else "FINISH"
	self.count.TextColor3 = M.CountdownGoColor
	self.count.TextSize = M.CountdownGoSize
	self.count.TextTransparency = 0

	TweenService:Create(self.count, TweenInfo.new(M.FinishFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
end

-- Who you're watching, on the status line.
--
-- Reuses the status label rather than adding a second one: while you're
-- spectating there is no lap time to show and nothing else wants that
-- row, so a second label would just be one more thing to keep in sync.
--
-- Nil clears it and hands the row back to Update().
function MatchHud:SetSpectating(name: string?)
	self.spectating = name
	if name then
		self.status.Text = ("SPECTATING  %s"):format(name:upper())
		self.status.TextColor3 = M.StatusColor
	end
end

--=====================================================================
--  RESULTS
--=====================================================================
local function nameFor(kart: Model): string
	local id = kart:GetAttribute(Names.OWNER)
	local player = id and Players:GetPlayerByUserId(id)
	if player then
		return player.DisplayName
	end
	return "Racer"
end

local function isSelf(kart: Model): boolean
	return kart:GetAttribute(Names.OWNER) == Players.LocalPlayer.UserId
end

local function clockText(t: number): string
	local mins = math.floor(t / 60)
	local secs = t - mins * 60
	return ("%d:%05.2f"):format(mins, secs)
end

function MatchHud:_row(i: number): TextLabel
	local row = self.rowPool[i]
	if not row then
		row = label(self.rows, M.ResultsRowSize, M.ResultsColor)
		row.Size = UDim2.new(1, 0, 0, M.ResultsRowHeight)
		row.TextXAlignment = Enum.TextXAlignment.Center
		row.LayoutOrder = i
		self.rowPool[i] = row
	end
	return row
end

-- Rebuilt from the karts in the world rather than from a list the
-- server sent: the finish attributes are already replicated, so there's
-- nothing extra to keep in sync and a late joiner sees the board too.
function MatchHud:ShowResults()
	local finished = {}
	for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
		local place = kart:GetAttribute(Shared.FINISH_PLACE)
		if typeof(place) == "number" then
			table.insert(finished, {
				place = place,
				kart = kart,
				time = kart:GetAttribute(Shared.FINISH_TIME) or 0,
			})
		end
	end
	table.sort(finished, function(a, b)
		return a.place < b.place
	end)

	for i, row in self.rowPool do
		row.Visible = i <= #finished
	end

	for i, entry in finished do
		local row = self:_row(i)
		row.Visible = true
		row.Text = ("%d.   %s   —   %s"):format(entry.place, nameFor(entry.kart), clockText(entry.time))
		row.TextColor3 = if isSelf(entry.kart) then M.ResultsSelfColor else M.ResultsColor
	end

	if #finished == 0 then
		local row = self:_row(1)
		row.Visible = true
		row.Text = "nobody finished"
		row.TextColor3 = M.ResultsDimColor
	end

	self.board.Size = UDim2.fromOffset(M.ResultsWidth, 46 + math.max(#finished, 1) * (M.ResultsRowHeight + 2))
	self.board.Visible = true
end

function MatchHud:HideResults()
	self.board.Visible = false
end

-- RewardHud draws the same finishing order, larger. When it is up this
-- board stays down rather than showing through it.
function MatchHud:SuppressResults(on: boolean)
	self.suppressed = on
	if on then
		self.board.Visible = false
	end
end

--=====================================================================
--  FRAME
--=====================================================================
function MatchHud:Update(match)
	local phase = match:Phase()

	-- SPECTATING OWNS THE STATUS ROW, AND ONLY THE STATUS ROW.
	--
	-- This used to return outright, which skipped the results board with
	-- it — so the one moment a spectator most wants the board, the end of
	-- the round they are watching, was the one moment it never appeared.
	--
	-- The flicker being avoided is two writers on a single TextLabel.
	-- That is a reason to guard the label, not the function.
	if not self.spectating then
		if phase == P.Waiting then
			local racers, need = match:Humans(), match:MinRacers()
			self.status.Text = ("WAITING FOR RACERS   %d / %d"):format(racers, need)
		elseif phase == P.Intermission then
			local suffix = if match:IsReady()
				then "READY"
				else ("PRESS %s TO READY"):format(M.ReadyKey.Name)
			self.status.Text = ("NEXT RACE IN %d   ·   %s   ·   %d/%d READY"):format(
				math.ceil(match:TimeLeft()),
				suffix,
				match:ReadyCount(),
				match:Racers()
			)
		elseif phase == P.Results then
			self.status.Text = ("NEXT RACE IN %d"):format(math.ceil(match:TimeLeft()))
		else
			self.status.Text = ""
		end
	end

	-- Built once per entry into Results, not per frame: the board is a
	-- dozen instances and rebuilding it at 60fps for ten seconds would
	-- be pure waste.
	if phase == P.Results and not self.suppressed then
		if not self.board.Visible then
			self:ShowResults()
		end
	elseif self.board.Visible then
		self:HideResults()
	end
end

-- Off in a lobby. The countdown, the ready line and the standings all
-- describe a round; with no round they describe nothing, and a frozen
-- "0 / 1 PLAYERS" in a hub reads as a broken game rather than an idle
-- one.
--
-- The decision lives in the entry point, not here — this only obeys.
function MatchHud:SetVisible(on: boolean)
	self.gui.Enabled = on
end

function MatchHud:Destroy()
	self.gui:Destroy()
end

return MatchHud
