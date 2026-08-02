--[[
	KeyPrompt — one lobby prompt: a key, some words, and a note line.

	The hub has more than one of these now (call your kart, go and race)
	and will have more (garage, party). Built once here rather than in
	each of them, because "consistent with the other UI" is a promise you
	can only keep if there is one thing to be consistent WITH.

	A KEY PROMPT ON DESKTOP, A REAL BUTTON ON TOUCH.

	A slab in the middle of the screen is menu furniture, and the lobby is
	deliberately a place rather than a menu. On a keyboard the useful
	thing to show is the binding — that is what the player will use for
	the rest of the session. Touch has no keyboard, so there it stays a
	button. Decided by Device.touchLayout, the same answer the rest of the
	client already uses for this question.

	It is a TextButton either way, so a click works for anyone who tries
	that first. It just stops asking to be clicked.

	HOLDS NO STATE ABOUT THE GAME. The owner sets the label and the note;
	this only draws them. That keeps the "wait for the server before you
	claim anything happened" rule where it belongs — in the module that
	talks to the server.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Device = require(BloxKart:WaitForChild("Device"))

local LOBBY = Config.Lobby

local FONT = Font.fromEnum(Enum.Font.GothamBold)

local KeyPrompt = {}
KeyPrompt.__index = KeyPrompt

-- The first bound key, named the way a player would say it. Gamepad
-- bindings are skipped: a controller shows its own glyphs elsewhere, and
-- "BUTTONY" on a desktop prompt helps nobody.
local function keyLabel(keys: { Enum.KeyCode }): string
	for _, key in keys do
		local name = key.Name
		if not name:match("^Button") and not name:match("^DPad") then
			return name
		end
	end
	return "?"
end

export type Options = {
	name: string,
	keys: { Enum.KeyCode },
	position: UDim2,
	onActivate: () -> (),
	-- Touch only. Desktop draws the key instead and ignores this.
	accent: Color3?,
}

function KeyPrompt.new(opts: Options)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartPrompt_" .. opts.name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local touch = Device.touchLayout()
	local accent = opts.accent or LOBBY.KeyPromptColor

	local button = Instance.new("TextButton")
	button.Name = opts.name
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = opts.position
	button.BorderSizePixel = 0
	button.FontFace = FONT
	button.Text = ""
	button.Parent = gui

	if touch then
		button.Size = LOBBY.ButtonSize
		button.BackgroundColor3 = accent
		button.AutoButtonColor = true
		button.TextSize = 18
		button.TextColor3 = LOBBY.ButtonTextColor

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
	else
		button.Size = UDim2.fromOffset(340, 26)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.TextSize = 17
		button.TextColor3 = LOBBY.KeyPromptTextColor
		button.TextStrokeColor3 = Color3.new(0, 0, 0)
		button.TextStrokeTransparency = 0.5
		button.RichText = true
	end

	-- Refusals and confirmations, just above the prompt. One line,
	-- fading — a hub message is not worth a panel.
	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = opts.position - UDim2.fromOffset(0, LOBBY.NoteLift)
	note.Size = UDim2.fromOffset(460, 22)
	note.BackgroundTransparency = 1
	note.FontFace = FONT
	note.TextSize = 15
	note.TextColor3 = accent
	note.TextStrokeColor3 = Color3.new(0, 0, 0)
	note.TextStrokeTransparency = 0.4
	note.Text = ""
	note.Parent = gui

	local self = setmetatable({
		gui = gui,
		button = button,
		note = note,
		touch = touch,
		accent = accent,
		keyName = keyLabel(opts.keys),
		words = "",
		noteUntil = 0,
	}, KeyPrompt)

	button.Activated:Connect(opts.onActivate)

	UserInputService.InputBegan:Connect(function(input, typing)
		if typing then
			return
		end
		for _, key in opts.keys do
			if input.KeyCode == key then
				opts.onActivate()
				return
			end
		end
	end)

	return self
end

-- The words beside the key. One place builds both forms, so the touch
-- and desktop versions cannot drift into saying different things.
function KeyPrompt:SetLabel(words: string)
	self.words = words
	if self.touch then
		self.button.Text = words
	else
		self.button.Text = ('<font color="#%s">[%s]</font>  %s'):format(self.accent:ToHex(), self.keyName, words)
	end
end

function KeyPrompt:Note(text: string)
	self.note.Text = text
	self.note.TextTransparency = 0
	self.noteUntil = os.clock() + LOBBY.NoteTime
end

function KeyPrompt:SetVisible(on: boolean)
	self.gui.Enabled = on
end

-- Fades the note out. Driven from the client's frame loop rather than
-- given its own connection, so the hub costs one update like everything
-- else on screen.
function KeyPrompt:Update(dt: number)
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

function KeyPrompt:Destroy()
	self.gui:Destroy()
end

return KeyPrompt
