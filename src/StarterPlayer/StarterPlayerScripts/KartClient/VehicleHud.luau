--[[
	VehicleHud — calling your kart, in the lobby.

	A KEY PROMPT on desktop, a real button on touch. A slab in the middle
	of the screen is menu furniture, and the hub is a place rather than a
	menu — so what belongs on screen is the binding, which is what the
	player will actually use after the first ten seconds.

	It is a TextButton either way, so a click still works for anyone who
	tries that first. It just stops asking to be clicked.

	It holds NO authority. It sends "spawn" or "despawn" and then waits to
	be told what happened — the server decides, including whether there is
	room. So the label follows the server's answer rather than flipping
	optimistically on click, and a refusal can say why.

	Only built in a lobby. A race place hands you a kart because a round
	is starting; there is nothing to ask for.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Device = require(BloxKart:WaitForChild("Device"))
local Names = require(BloxKart:WaitForChild("Names"))

local LOBBY = Config.Lobby
local H = Config.Hud

local FONT = Font.fromEnum(Enum.Font.GothamBold)

-- The first bound key, named the way a player would say it. Gamepad
-- bindings are skipped: a controller shows its own glyphs elsewhere and
-- "BUTTONY" on a desktop prompt helps nobody.
local function keyLabel(): string
	for _, key in LOBBY.ToggleKeys do
		local name = key.Name
		if not name:match("^Button") and not name:match("^DPad") then
			return name
		end
	end
	return "?"
end

local VehicleHud = {}
VehicleHud.__index = VehicleHud

function VehicleHud.new()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartVehicle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- TOUCH GETS A BUTTON. EVERYTHING ELSE GETS THE KEY.
	--
	-- A slab in the middle of the screen is menu furniture, and the hub
	-- is a place rather than a menu. On a keyboard the useful thing is
	-- the binding, because that is what the player will use for the rest
	-- of the session.
	local touch = Device.touchLayout()

	local button = Instance.new("TextButton")
	button.Name = "CallKart"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = LOBBY.ButtonPosition
	button.BorderSizePixel = 0
	button.FontFace = FONT
	button.Parent = gui

	if touch then
		button.Size = LOBBY.ButtonSize
		button.BackgroundColor3 = LOBBY.ButtonColor
		button.BackgroundTransparency = 0
		button.AutoButtonColor = true
		button.TextSize = 18
		button.TextColor3 = LOBBY.ButtonTextColor

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
	else
		-- Still a TextButton so a mouse click works too — some people
		-- will click it once before believing the key. It just does not
		-- look like something demanding to be clicked.
		button.Size = UDim2.fromOffset(300, 26)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.TextSize = 17
		button.TextColor3 = LOBBY.KeyPromptTextColor
		button.TextStrokeColor3 = Color3.new(0, 0, 0)
		button.TextStrokeTransparency = 0.5
		button.RichText = true
	end

	-- Refusals and confirmations land here, just above the button. One
	-- line, fading — a hub message is not worth a panel.
	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = LOBBY.ButtonPosition - UDim2.fromOffset(0, LOBBY.ButtonSize.Y.Offset + 10)
	note.Size = UDim2.fromOffset(420, 22)
	note.BackgroundTransparency = 1
	note.FontFace = FONT
	note.TextSize = 15
	note.TextColor3 = H.WrongWayColor
	note.TextStrokeColor3 = Color3.new(0, 0, 0)
	note.TextStrokeTransparency = 0.4
	note.Text = ""
	note.Parent = gui

	local remote = BloxKart:WaitForChild(Names.VEHICLE_REMOTE, 10) :: RemoteEvent?

	local self = setmetatable({
		gui = gui,
		button = button,
		touch = touch,
		keyName = keyLabel(),
		note = note,
		remote = remote,
		-- What the SERVER last told us. Never set on click: an optimistic
		-- flip means a blocked spawn leaves the button saying PUT AWAY
		-- for a kart that was never built.
		hasKart = false,
		noteUntil = 0,
	}, VehicleHud)

	button.Activated:Connect(function()
		self:Toggle()
	end)

	UserInputService.InputBegan:Connect(function(input, typing)
		if typing then
			return
		end
		for _, key in LOBBY.ToggleKeys do
			if input.KeyCode == key then
				self:Toggle()
				return
			end
		end
	end)

	button.Text = self:_label()

	if remote then
		remote.OnClientEvent:Connect(function(result)
			self:_result(result)
		end)
	else
		warn("[VehicleHud] no vehicle remote — is PlayerVehicleService running?")
	end

	return self
end

function VehicleHud:Toggle()
	if not self.remote then
		return
	end
	self.remote:FireServer(if self.hasKart then "despawn" else "spawn")
end

function VehicleHud:_note(text: string)
	self.note.Text = text
	self.note.TextTransparency = 0
	self.noteUntil = os.clock() + 2.5
end

-- One place decides how the prompt reads, so the touch and desktop
-- forms cannot drift into saying different things.
function VehicleHud:_label()
	local words = if self.hasKart then LOBBY.DespawnText else LOBBY.SpawnText
	if self.touch then
		return words
	end
	return ('<font color="#%s">[%s]</font>  %s'):format(
		LOBBY.KeyPromptColor:ToHex(),
		self.keyName,
		words
	)
end

function VehicleHud:_result(result: unknown)
	if result == "spawned" then
		self.hasKart = true
		self.button.Text = self:_label()
	elseif result == "despawned" then
		self.hasKart = false
		self.button.Text = self:_label()
	elseif result == "blocked" then
		self:_note(LOBBY.BlockedMessage)
	elseif result == "failed" then
		self:_note("COULD NOT BUILD YOUR KART — TRY AGAIN")
	end
end

-- Fades the note out. Called from the client's frame loop rather than
-- given its own connection, so the hub costs one update like everything
-- else on screen.
function VehicleHud:Update(dt: number)
	if self.note.Text == "" then
		return
	end
	if os.clock() > self.noteUntil then
		self.note.TextTransparency = math.min(1, self.note.TextTransparency + dt * 2)
		if self.note.TextTransparency >= 1 then
			self.note.Text = ""
		end
	end
end

function VehicleHud:Destroy()
	self.gui:Destroy()
end

return VehicleHud
