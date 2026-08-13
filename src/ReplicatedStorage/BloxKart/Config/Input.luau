--[[
	Input — key bindings.
--]]

return {
	-- Direct driving bindings. The simulation reads these itself instead of
	-- relying solely on Roblox's VehicleSeat controller to fill ThrottleFloat
	-- and SteerFloat, which can fail during a cold seat/PlayerModule handoff.
	DriveForwardKeys = { Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.ButtonR2 },
	DriveBackKeys = { Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.ButtonL2 },
	DriveLeftKeys = { Enum.KeyCode.A, Enum.KeyCode.Left },
	DriveRightKeys = { Enum.KeyCode.D, Enum.KeyCode.Right },

	-- Roblox normalises Xbox, PlayStation, Switch-style and generic pads to
	-- these KeyCodes. Controller *brands* therefore need no separate input
	-- paths; all that varies is the button printed on the hardware.
	-- Keeping the actions on separate shoulders matters: the old L1/R1 drift
	-- duplicate made a controller's most useful spare button unavailable.
	DriftKeys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonR1 }, -- RB
	LookBackKeys = { Enum.KeyCode.C, Enum.KeyCode.ButtonL1 }, -- LB (hold)
	-- RT/R2 and LT/L2 are Roblox VehicleSeat's gas and brake pedals. Never
	-- bind a ContextAction to either one or it consumes the driving input.
	-- Nitro is a tap action, so the top face button is the accessible spare.
	NitroKeys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonY }, -- FACE TOP
	FreeLookButton = Enum.UserInputType.MouseButton2, -- hold to orbit

	-- Gamepad jump, sunk separately so it can't eject the player either.
	JumpSinkKey = Enum.KeyCode.ButtonA,

	-- TEST ONLY. Space is the drift key and jumping is normally the only
	-- way out of a VehicleSeat, so without this you're stuck in the kart
	-- — which is the intent in a race. Pair with Config.Rig.TestMode.
	AllowExit = false,
	ExitKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonY },
}
