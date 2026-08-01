--[[
	Lobby — the hub, and calling your kart in it.

	A lobby is a place you WALK around. You arrive on foot, and your kart
	is something you call for rather than something you are born in. That
	is the whole difference from a race place, where the kart is handed to
	you because a race is about to start.

	Everything here is read by PlayerVehicleService (server, the policy
	and the remote) and VehicleHud (client, the button and the key).
	KartService is untouched by it: KartService still owns HOW a kart is
	built and seated, and this decides WHEN somebody is allowed to ask.
--]]

return {
	--== CALLING YOUR KART ===============================================
	-- A toggle, not two controls. Press once for a kart, press again to
	-- put it away.
	--
	-- A BUTTON AND A KEY, NOT A PROMPT ON A PIT LANE. A ProximityPrompt
	-- would answer "where does the kart go" for free and cost nothing on
	-- mobile — but it also means you can only call your kart from one
	-- spot, and a hub is meant to be somewhere you wander. The clearance
	-- check below is the price of that freedom.
	ToggleKeys = { Enum.KeyCode.G, Enum.KeyCode.ButtonY },

	-- Two states, because a prompt that does not say what it will do
	-- next is a prompt you press to find out.
	SpawnText = "CALL KART",
	DespawnText = "PUT AWAY",

	-- A KEY PROMPT ON DESKTOP, A REAL BUTTON ON TOUCH.
	--
	-- A big clickable slab in the middle of a hub is a menu, and the
	-- lobby is explicitly not a menu — it is a place. Showing the key
	-- instead teaches the binding, which is what the player actually
	-- needs after the first ten seconds.
	--
	-- Touch has no keyboard, so there it stays a button. Same module,
	-- same state, decided by Device.touchLayout — the same answer the
	-- rest of the client already uses for this question.
	KeyPromptColor = Color3.fromRGB(255, 196, 62),
	KeyPromptTextColor = Color3.fromRGB(236, 238, 245),

	-- Bottom centre, above the mobile controls if any.
	ButtonPosition = UDim2.fromScale(0.5, 0.9),
	ButtonSize = UDim2.fromOffset(190, 46),
	ButtonColor = Color3.fromRGB(255, 196, 62),
	ButtonTextColor = Color3.fromRGB(20, 20, 22),

	--== WHERE IT APPEARS ================================================
	-- Studs in front of where the player is standing. Far enough that the
	-- kart does not materialise inside them, close enough that it is
	-- obviously theirs.
	SpawnAhead = 8,

	-- Lifted before the drop, so it settles onto the road rather than
	-- spawning half-sunk into it.
	SpawnLift = 3,

	-- CLEARANCE. The box that has to be empty before a kart may appear.
	--
	-- This is the cost of a button instead of a pit lane: the player can
	-- be standing anywhere, including a doorway, and a 7-stud kart has to
	-- fit. Slightly larger than the hitbox so it does not spawn wedged
	-- against a wall it can never drive out of.
	--
	-- If it does not fit, REFUSE AND SAY SO. Spawning it anyway means a
	-- kart clipped into geometry, which reads as a broken game rather
	-- than as a bad spot to stand.
	ClearanceSize = Vector3.new(6, 4, 10),
	BlockedMessage = "NOT ENOUGH ROOM — TRY OPEN GROUND",

	--== RATE LIMIT ======================================================
	-- Seconds between accepted requests, per player. A toggle bound to a
	-- key is a toggle somebody will hold down, and building a kart is not
	-- free.
	--
	-- Also the honest reason: this is a remote, and every remote gets a
	-- cooldown. See Kart/SECURITY.md.
	ToggleCooldown = 1.0,

	--== WALKING AGAIN ===================================================
	-- Seating a player zeroes their jump and disables the Jumping state,
	-- so nobody can hop out of a moving kart. Putting the kart away has
	-- to undo exactly that, or the hub is a place you can walk but never
	-- jump — which looks like a physics bug and is very hard to guess at.
	--
	-- The values come from StarterPlayer at runtime rather than living
	-- here, so they follow whatever the place is actually configured for.
	-- This flag only decides whether we bother.
	RestoreJumpOnDespawn = true,

	-- Where the player is put when their kart vanishes underneath them.
	-- Beside where the kart was, not inside it.
	DismountSide = 4,

	--== ANNOUNCE ========================================================
	-- One line when the hub starts, saying what it is. Cheap, and it is
	-- how you notice a place is running the wrong role.
	Announce = true,
}
