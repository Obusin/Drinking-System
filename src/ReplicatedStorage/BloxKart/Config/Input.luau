--[[
	Input — key bindings.
--]]

return {
	DriftKeys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL1 },
	LookBackKeys = { Enum.KeyCode.C, Enum.KeyCode.ButtonR3 },
	-- Tap to escalate the burn: 1 -> 2 -> 3 -> off. Not a hold.
	NitroKeys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL2 },
	FreeLookButton = Enum.UserInputType.MouseButton2, -- hold to orbit

	-- Gamepad jump, sunk separately so it can't eject the player either.
	JumpSinkKey = Enum.KeyCode.ButtonA,

	-- TEST ONLY. Space is the drift key and jumping is normally the only
	-- way out of a VehicleSeat, so without this you're stuck in the kart
	-- — which is the intent in a race. Pair with Config.Rig.TestMode.
	AllowExit = false,
	ExitKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonY },
}
