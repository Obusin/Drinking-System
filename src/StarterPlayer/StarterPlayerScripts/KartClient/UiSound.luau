--[[
	UiSound — 2D interface SFX (click, hover, open, close, equip, ...).

	These are NON-positional: they live on SoundService, not on a part, so a
	menu click never attenuates with distance the way the kart engine does.
	Ids are config-driven (Config.Audio.UI), so a screen asks for a cue by
	NAME ("Click", "Hover", …) and never touches an asset id.

	One pooled Sound per cue. Play() rewinds rather than layering, which is the
	right behaviour for taps: a rapid click reads as clicks, not a smear. Cues
	that genuinely need to overlap (they don't yet) would want a small voice
	pool like Audio.notes — deliberately not built until something needs it.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local UI = Config.Audio.UI or {}

local UiSound = {}

local pool: { [string]: Sound } = {}

local function sound(name: string): Sound?
	local id = UI[name]
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local existing = pool[name]
	if existing then
		return existing
	end
	local s = Instance.new("Sound")
	s.Name = "_UI_" .. name
	s.SoundId = id
	s.Volume = UI.Volume or 0.5
	s.Parent = SoundService
	pool[name] = s
	return s
end

-- Play a named cue from the start. Unknown/blank cues no-op so callers can
-- stay declarative without guarding every id.
function UiSound.play(name: string)
	local s = sound(name)
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

-- Convenience: wire the standard hover + click cues onto a GuiButton. Pass a
-- different clickCue (e.g. "Error") when the action isn't a plain confirm.
function UiSound.bind(btn: GuiButton, clickCue: string?)
	btn.MouseEnter:Connect(function()
		UiSound.play("Hover")
	end)
	btn.Activated:Connect(function()
		UiSound.play(clickCue or "Click")
	end)
end

return UiSound
