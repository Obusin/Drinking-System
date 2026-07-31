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

	-- The Model in ServerStorage everyone drives. This IS the kart now —
	-- it went live for all players rather than staying an override on one
	-- account.
	VisualName = "Kart",

	-- Per-player art, for trying a new model on one account without
	-- giving it to everybody. Roblox username -> Model name in
	-- ServerStorage. Anyone not listed gets VisualName as normal.
	--
	-- Purely cosmetic and it has to stay that way: the hitbox is forced
	-- to HitboxSize whatever the art is, so a bespoke kart can never be
	-- a faster kart. That is the whole reason this is safe to ship.
	--
	-- EMPTY, deliberately. The kart that used to be listed here is now
	-- VisualName above, so an entry would only override the thing it was
	-- promoted into — and a leftover name here is exactly how a player
	-- ends up in a model nobody else can see.
	VisualByPlayer = {},

	-- IN STUDIO ONLY, everyone gets this regardless of name. Set "" to
	-- turn it off.
	--
	-- Studio's "Start Server + Players" names its players Player1,
	-- Player2… rather than your Roblox username, so VisualByPlayer never
	-- matches there and you silently get the placeholder. Solo Play works
	-- because that one DOES use your real name — which makes the failure
	-- look like the custom kart randomly breaking when you switch test
	-- modes.
	--
	-- Does nothing in a real server, so it's safe to leave set while
	-- building a kart.
	StudioVisual = "Kart",

	-- What the BOTS drive. Same model as you by default — a race where
	-- the AI is visibly in different karts reads as a demo rather than a
	-- race. "" puts them in the placeholder.
	BotVisual = "Kart",
	-- Drops the art so its lowest point is on the road, whatever its
	-- pivot happens to be.
	--
	-- PivotTo puts a model's PIVOT at the hitbox origin, and a pivot is
	-- wherever the modeller left it — usually the bounding-box centre.
	-- It is not the wheel line, so the kart floated or sank by however
	-- far those two differ. That is a property of the ART, so it changes
	-- every time the model is edited, and hand-tuning VisualOffset to
	-- match is a fix that has to be redone silently forever.
	--
	-- Off if a kart genuinely should hover.
	VisualAutoSit = true,

	-- Deliberate trim on top of the automatic sit, for art that should
	-- ride proud or tucked for a reason. Zero is correct for most models.
	VisualOffset = Vector3.new(0, 0, 0),

	--== SKINS  (test) ================================================
	-- Cycles one mesh part between a list of asset ids, to prove a skin
	-- can be a mesh swap rather than a whole separate kart model.
	--
	-- If it works, cosmetics are a table of ids and nothing else: no new
	-- models in ServerStorage, no change to KartFactory, and no way for a
	-- skin to affect handling — the mesh sits inside the visual, and
	-- Simulation reads only the Hitbox and the Seat.
	--
	-- Set SkinTest false once the answer is known; the loop is a probe,
	-- not a feature. Skins.applyTo is the real entry point.
	SkinTest = true,
	SkinTestInterval = 3,
	-- A SKIN IS A SET, NOT A PART. Swapping the body alone leaves the
	-- old wheels on the new shell, so the unit that has to swap
	-- atomically is the whole set — which is also the unit a player
	-- buys. Each entry below is one skin: part name -> mesh id, parts
	-- found recursively so the artist can refile them freely.
	--
	-- FWheel and RWheel are separate keys even where they share an id,
	-- because they will not always: the rear is the wider pair on most
	-- karts, and the front is the one that steers.
	SkinTestSkins = {
		{
			Body = "rbxassetid://72597967734984",
			FWheel = "rbxassetid://136481236962745",
			RWheel = "rbxassetid://136481236962745",
		},
		{
			Body = "rbxassetid://89589911208680",
			FWheel = "rbxassetid://124866750857410",
			RWheel = "rbxassetid://124866750857410",
		},
	},

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

	--== ROAD WHEELS ===================================================
	-- Purely cosmetic: nothing here touches handling, which is decided
	-- entirely by the hitbox. Tag the wheels in your kart art, or name
	-- them from the lists below if you'd rather not tag.
	--
	-- Wheels get a Motor6D instead of a weld, because a weld can't be
	-- rotated at runtime and a Motor6D can — the same reason the steering
	-- wheel has one.
	WheelFrontTag = "KartWheelFront", -- steers AND rolls
	WheelRearTag = "KartWheelRear", -- rolls only

	-- Fallback if nothing is tagged, so the built-in placeholder works.
	FrontWheelNames = { "WheelFL", "WheelFR", "FWheel", "WheelF" },
	RearWheelNames = { "WheelRL", "WheelRR", "RWheel", "WheelR" },

	RoadWheelSteer = 26, -- degrees of lock at full steer. Real karts turn
	-- their fronts much further than a car; too little reads as broken
	RoadWheelRadius = 1.1, -- studs. Only sets how fast they LOOK like
	-- they're rolling — wrong and they visibly skid or spin up
	RoadWheelSteerRate = 12, -- how fast the fronts follow the input

	-- Which way a wheel rolls. "auto" measures it per wheel: a wheel is a
	-- disc, so its axle is its THINNEST dimension, which is true of any
	-- mesh however it was modelled.
	--
	-- Assuming an axis is what made imported wheels spin flat like a
	-- helicopter rotor — X is the axle of a Roblox Cylinder and of
	-- nothing else in particular.
	--
	-- Set a Vector3 to force it, for a mesh whose bounding box lies about
	-- its shape (a wheel with a long axle stub modelled in, say).
	RoadWheelAxis = "auto",

	-- Cap on how fast a wheel LOOKS like it's spinning, radians/sec.
	--
	-- A 1.1-stud wheel at full speed turns about 17 times a second, which
	-- at 60fps is nearly two whole revolutions per frame — it aliases into
	-- a strobing blur, and any steering angle is invisible inside it.
	-- Real footage has motion blur to sell that; we don't, so the visual
	-- spin is capped where it still reads as fast.
	RoadWheelMaxSpin = 26,

	-- Counter-steer during a drift, as a fraction of the body's slide
	-- angle. The body is yawed sideways while the kart still travels
	-- roughly forwards, so cancelling that angle points the fronts back
	-- down the ROAD — which is what a drifting car actually looks like
	-- and the single detail that sells it.
	--
	-- 1 = perfectly aligned with travel, 0 = wheels follow the body and a
	-- drift looks like the kart is just facing the wrong way. NEGATIVE
	-- flips which way they crank, if it ends up mirrored on your model.
	RoadWheelCounterSteer = 0.85,

	-- CATCH: reacts to how fast the slide is CHANGING, not how big it is.
	-- This is the term that makes the wheels move during a steady drift
	-- instead of sitting parked at an angle — cranking as the rear steps
	-- out and unwinding as it hooks up. Raise it for a twitchier, more
	-- reactive driver; 0 leaves a static counter angle.
	RoadWheelCatch = 0.14,
	RoadWheelCatchSmoothing = 10, -- a raw frame-to-frame rate is jitter,
	-- and unsmoothed it makes the wheels buzz rather than correct

	-- SAW: the small constant corrections nobody makes deliberately.
	-- Faded in with how sideways you are, so it never twitches on a
	-- straight. Radians at full slide.
	RoadWheelSaw = 0.07,
	RoadWheelSawRate = 2.6, -- oscillations per second

	--== COLLISION =====================================================
	-- Karts pass through each other. Racers bumping is a whole physics
	-- problem we don't need, and our movement is query-based anyway.
	CollisionGroup = "Karts",

	-- Seconds between checks that each seated player still OWNS their own
	-- kart on the network.
	--
	-- "I'm driving but everyone else sees me parked" is always this. The
	-- client writes the CFrame, and that only reaches anyone else if the
	-- client owns the part; ownership is granted once when they sit down,
	-- and once is not enough — the grant can fail, land mid-respawn, or be
	-- taken back by the engine when a part sleeps. Re-asserting costs a
	-- comparison per seated player.
	OwnershipCheck = 2,

	-- Seconds before auditing kart parts for anything still collidable
	-- outside the kart group. Delayed because art streams in.
	CollisionAuditDelay = 6,

	-- Seconds between checks for one kart actually sitting inside
	-- another. Names the offending part, whether it is collidable, whether
	-- it is queryable, and which group it is in.
	--
	-- On while this is being chased. Set to 0 to stop it: it is a
	-- diagnostic, not a mechanic, and it queries once per kart per tick.
	OverlapAuditRate = 0,

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

	--== SEEING OTHER PEOPLE'S KARTS ===================================
	-- Your kart is simulated on your machine at your frame rate. Everyone
	-- else's arrives over the network — a bot's is written by the server
	-- and replicates as a property update around twenty times a second.
	-- At 120 studs/s that's six studs a step, which reads as teleporting.
	--
	-- This is the rate each client eases its picture of somebody else's
	-- kart toward the last position the server sent. It changes nothing
	-- about where a kart IS, only what gets drawn between updates. Hits,
	-- items and standings all read server state.
	--
	-- Higher is tighter to the server and choppier; lower is smoother and
	-- further behind. 0 turns it off entirely.
	RemoteSmoothing = 14,

	-- Past this, jump instead of ease. A respawn or a grid placement is a
	-- real jump, and easing across one flies the kart through the scenery
	-- — which is exactly the artifact this exists to remove.
	RemoteSnapDistance = 30,

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

	Debug = false, -- trace spawning to Output
}
