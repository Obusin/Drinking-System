--[[
	Rig — how the kart is BUILT and spawned. Server-side concerns.
--]]

return {
	-- TestMode: one shared kart on the pad, walk up and sit in it.
	-- FALSE (production): one kart per player, spawned already seated,
	-- no way out. Pair with Config.Input.AllowExit.
	TestMode = false,

	MaxRacers = 8, -- grid size. More players than this still spawn, they
	-- just reuse colours and grid slots.

	-- The physical footprint. FIXED, regardless of what the art looks
	-- like. Changing this changes handling; changing the art does not.
	HitboxSize = Vector3.new(4, 2.4, 7),

	VisualName = "KartVisual", -- optional Model in ServerStorage

	-- Per-player art, for trying a new model on one account without
	-- giving it to everybody. Roblox username -> Model name in
	-- ServerStorage. Anyone not listed gets VisualName as normal.
	--
	-- Purely cosmetic and it has to stay that way: the hitbox is forced
	-- to HitboxSize whatever the art is, so a bespoke kart can never be
	-- a faster kart. That is the whole reason this is safe to ship.
	--
	-- Empty this table when the new model goes live for everyone.
	VisualByPlayer = {
		Obus1n = "Kart",
	},
	VisualOffset = Vector3.new(0, 0, 0),

	--== PAINT =========================================================
	-- One colour per grid slot, so every racer is tellable apart.
	-- Chosen to stay distinct for the common colour-blindness types:
	-- no red/green pair, no blue/purple pair adjacent in the order.
	Colors = {
		Color3.fromRGB(214, 48, 49), -- 1  red
		Color3.fromRGB(9, 132, 227), -- 2  blue
		Color3.fromRGB(253, 203, 110), -- 3  sand
		Color3.fromRGB(0, 184, 148), -- 4  teal
		Color3.fromRGB(232, 67, 147), -- 5  pink
		Color3.fromRGB(253, 121, 33), -- 6  orange
		Color3.fromRGB(162, 155, 254), -- 7  lilac
		Color3.fromRGB(45, 52, 54), -- 8  graphite
	},
	-- Which parts get painted. Tag a part `KartPaint` in custom art to
	-- opt it in; otherwise these names are matched on the placeholder.
	-- Anything not listed keeps its authored colour, so trim and tyres
	-- don't turn pink.
	PaintTag = "KartPaint",
	PaintParts = { "Chassis", "Nose" },

	--== COLLISION =====================================================
	-- Karts pass through each other. Racers bumping is a whole physics
	-- problem we don't need, and our movement is query-based anyway.
	CollisionGroup = "Karts",

	-- Steering wheel. Built so the hands have something to grab; the
	-- Rider module spins it and solves the arms onto it. If your
	-- KartVisual already contains a part named "SteeringWheel", that
	-- gets used instead and none of this is built.
	WheelOffset = CFrame.new(0, 1.45, -0.85), -- relative to the hitbox
	WheelTilt = -22, -- degrees of lean. NEGATIVE tips the top away from
	-- the driver (rally/kart style). Flip the sign if it looks wrong.
	WheelRadius = 0.85,
	WheelThick = 0.16,
	WheelSegments = 14, -- rim is a ring of blocks; no torus primitive
	WheelColor = Color3.fromRGB(33, 33, 38),

	--== SPAWNING ======================================================
	DropHeight = 3, -- studs above the pad's top face at spawn
	GridColumns = 2, -- karts per row on the start grid
	GridSpacing = 9, -- sideways gap between columns
	GridRowSpacing = 11, -- gap between rows, measured backwards
	GridStagger = 4, -- how far back each column sits from the one to its
	-- left, so the grid zigzags like a real one
	SpawnName = "", -- name a specific SpawnLocation, or "" for any
	FallbackCF = CFrame.new(0, 10, 0),
	RespawnBelow = -100,
	SeatDelay = 0.2, -- let the character assemble before Sit()
	ReseatDelay = 0.1, -- grace before shoving an escapee back in

	Debug = true, -- trace spawning to Output
}
