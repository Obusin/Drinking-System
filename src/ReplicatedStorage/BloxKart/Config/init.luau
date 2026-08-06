--[[
	BloxKart Config
	--------------------------------------------------------------------
	Every tunable value in the game, in one replicated place.

		local Config = require(ReplicatedStorage.BloxKart.Config)
		Config.Handling.MaxSpeed

	Split by concern rather than by which script uses it, so a value
	lives where you'd go looking for it.
--]]

return {
DevConsole = require(script.DevConsole),
	Loading = require(script.Loading),
	Handling = require(script.Handling), -- how it moves
	Rig = require(script.Rig), -- how it's built and spawned
	Bots = require(script.Bots), -- AI racers
	Camera = require(script.Camera), -- chase cam, FOV, looking around
	Audio = require(script.Audio), -- sound ids and pitches
	Effects = require(script.Effects), -- trails and body motion
	Nitro = require(script.Nitro), -- banked boost and burn stages
	Boosters = require(script.Boosters), -- speed pads in the world
	Race = require(script.Race), -- lap timing
	Match = require(script.Match), -- the round loop: grid, countdown, results
	Respawn = require(script.Respawn), -- void zones and getting back on track
	Items = require(script.Items), -- power-ups and their boxes
	Rider = require(script.Rider), -- steering wheel and hand IK
	Input = require(script.Input), -- key bindings
	Touch = require(script.Touch), -- mobile on-screen controls
	Haptics = require(script.Haptics), -- controller rumble
	Music = require(script.Music), -- background playlists
	Spectate = require(script.Spectate), -- watching after you finish
	Rewards = require(script.Rewards), -- end-of-race results and payout
	Level = require(script.Level), -- XP, the curve, and what earns it
	Quests = require(script.Quests), -- the daily/weekly/monthly pools
	Data = require(script.Data), -- persistence, off by default
	Minimap = require(script.Minimap), -- the track, drawn from Route
	Skins = require(script.Skins), -- what a kart can look like
	Garage = require(script.Garage), -- the customisation catalogue (keys -> meshes/paint)
	Hud = require(script.Hud), -- shared on-screen styling
	Places = require(script.Places), -- lobby vs race place, and the track list
	Lobby = require(script.Lobby), -- the hub: calling and putting away your kart
	Build = require(script.Build), -- which version this server is running
}
