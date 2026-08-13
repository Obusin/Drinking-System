--[[
	Match — narrow, server-authoritative controls for the F4 console.

	This adapter intentionally exposes only operations that preserve the match
	state machine's invariants. In particular, restart uses MatchService's grid
	entry path instead of letting a console request set an arbitrary phase.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Place = require(BloxKart.Place)
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local MatchControl = {}

local function service(): any?
	local module = script.Parent.Parent.Parent:FindFirstChild("MatchService")
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function unavailable(): (boolean, string, string)
	if not Place.isRace() then
		return false, Protocol.Code.WRONG_PLACE, "Match controls are available in the race place only."
	end
	return false, Protocol.Code.UNAVAILABLE, "MatchService is unavailable."
end

function MatchControl.restart(): (boolean, string, string, any?)
	local match = service()
	if not match or type(match.devRestartRound) ~= "function" then
		return unavailable()
	end
	local ok, message = match.devRestartRound()
	return ok, if ok then Protocol.Code.OK else Protocol.Code.UNAVAILABLE, message, match.management()
end

function MatchControl.finish(): (boolean, string, string, any?)
	local match = service()
	if not match or type(match.devFinishRound) ~= "function" then
		return unavailable()
	end
	local ok, message = match.devFinishRound()
	return ok, if ok then Protocol.Code.OK else Protocol.Code.UNAVAILABLE, message, match.management()
end

function MatchControl.setLaps(laps: number): (boolean, string, string, any?)
	local match = service()
	if not match or type(match.devSetLaps) ~= "function" then
		return unavailable()
	end
	local ok, message = match.devSetLaps(laps)
	return ok, if ok then Protocol.Code.OK else Protocol.Code.UNAVAILABLE, message, match.management()
end

return MatchControl
