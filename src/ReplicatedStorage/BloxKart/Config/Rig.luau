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
	-- ANSWERED: the working route is CreateMeshPartAsync + ApplyMesh,
	-- which YIELDS and fetches over the network. MeshContent is not
	-- available on this engine. Consequence for the real system: preload
	-- the equipped set at the grid and never swap mid-race — see the
	-- vault note "BloxKart Kart Customization and Skinning".
	--
	-- The probe has served its purpose. Set false once you have seen it.
	SkinTest = false,
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
	-- THE PART NAMES THE DRESSING LOOKS FOR. One source, both sides.
	--
	-- KartDress (the garage preview) already walked these lists;
	-- GarageService.lookFor did NOT — it hard-coded "FWheel"/"RWheel" as
	-- part names, which are two ALIASES in the list below and not what
	-- the actual rig uses. So the preview found WheelFL/FR/RL/RR and
	-- swapped them, and the spawned kart asked for a part called exactly
	-- "FWheel", found nothing, and silently kept its old wheels.
	--
	-- That is why customisation appeared to work in the garage and then
	-- not on the kart. Anything that dresses a kart reads these.
	-- A LIST, exactly like the wheels, and for the same reason.
	--
	-- THE GARAGE PREVIEW KART AND THE PLAYER'S REAL KART ARE DIFFERENT
	-- MODELS. The preview is the authored MenuStage kart; the ridden one
	-- is built by KartFactory. They are not required to name their parts
	-- the same way and in this project they do not — which is why the
	-- garage visibly changed and the real kart never did.
	--
	-- A single `BodyName` could only ever be right for one of them. A
	-- candidate list is right for both: a name a model does not have is
	-- simply not found, at the cost of one lookup.
	--
	-- IF THE MESH SWAP STILL DOES NOTHING, the warn from
	-- KartService/dress prints this kart's REAL MeshPart names. Add the
	-- one that is the bodywork here. DO NOT rename art to match code.
	BodyNames = { "Body", "Shell", "Hull", "Chassis" },
	-- A WHEEL MAY BE A MODEL OR A BARE PART, and the new rig is the
	-- former: FrontLeftWheel is a Model holding a Rim and a Tire, so the
	-- two can be bought and equipped separately.
	--
	-- The old names stay. A kart that was working yesterday keeps working,
	-- and the factory does not care which shape it gets.
	FrontWheelNames = { "FrontLeftWheel", "FrontRightWheel", "WheelFL", "WheelFR", "FWheel", "WheelF" },
	RearWheelNames = { "RearLeftWheel", "RearRightWheel", "WheelRL", "WheelRR", "RWheel", "WheelR" },

	--== WHAT LIVES INSIDE A WHEEL =====================================
	-- Two cosmetic slots per wheel instead of one. Named rather than
	-- positional, because "the second part in the model" is exactly the
	-- kind of rule that breaks the first time somebody reorders the
	-- Explorer.
	--
	-- TAGS BEAT NAMES and both are checked. A tag is one click in Studio
	-- and cannot silently miss; a name is free but has to be typed the
	-- same way every time, which is the failure that cost five rounds of
	-- "the garage is not saving".
	RimNames = { "Rim", "Rims", "Hub" },
	TireNames = { "Tire", "Tires", "Tyre", "Tyres" },
	RimTag = "KartRim",

	--== BODY ROLL =====================================================
	-- THE PAYOFF FOR FOUR SEPARATE WHEELS.
	--
	-- The bodywork hangs off the hitbox on its own Motor6D, so it can lean
	-- and dip while the WHEELS stay where the road put them. That order
	-- matters and is the whole illusion: real suspension moves the body
	-- against the wheels, not the wheels against the body. Wheels keep
	-- their own motors on the hitbox and never inherit the lean.
	--
	-- All of it is read from the suspension that already exists, so the
	-- body cannot disagree with what the wheels are doing — a kart leaning
	-- left while its left wheels are extended is the uncanny version of
	-- this effect, and deriving both from one source makes it impossible.
	BodyRootNames = { "Chassis", "Body", "Shell", "Hull" },
	BodyRootTag = "KartBodyRoot",

	-- Degrees of lean per stud of difference between the left and right
	-- wheels. The suspension only travels ~1 stud, so this multiplies a
	-- small number.
	BodyRollPerStud = 9,
	BodyPitchPerStud = 7,

	-- Authored lean ON TOP, from steering and drift. Suspension alone
	-- gives you bumps; this gives you cornering, which is the part players
	-- actually read as weight.
	--
	-- OUTWARD, away from the turn — that is what weight transfer looks
	-- like. Leaning into the corner reads as a motorbike.
	BodyRollPerSteer = 3.5, -- degrees at full lock
	BodyRollPerDrift = 6, -- and more again mid-drift

	-- Squash. The body drops toward the wheels as they compress, which is
	-- what makes a landing land.
	BodySquash = 0.7, -- studs of dip per stud of average compression

	-- Chased, not assigned. The suspension is already sprung; this is the
	-- bodywork's own softness on top.
	BodyRate = 9,

	-- Ceilings, because a wheel dropping into a hole should not put the
	-- kart on its side.
	BodyRollMax = 14, -- degrees
	BodyPitchMax = 10,

	--== THE GLIDER ====================================================
	-- The flap. One part, hinged, and the ONLY thing on the glider that
	-- moves — the wings are combined meshes and stay put.
	--
	-- SET ITS PIVOT TO THE HINGE LINE IN STUDIO. The motor rotates about
	-- the part's own pivot, so the hinge is aimed in the viewport rather
	-- than typed in here. Leave the pivot at the mesh centre and the flap
	-- will scissor through the wing instead of hinging off it.
	--== THRUSTERS =====================================================
	-- TWO PARTS, TWO DIFFERENT JOBS, and they are not variations of one
	-- idea:
	--
	--   CENTRE  reads SPEED. Black at a standstill, brighter the faster
	--           you go, and it takes the nitro colour while nitro burns.
	--           It is the tachometer.
	--   SIDES   read BOOST, and nothing else. Dark the entire time you
	--           are merely driving fast, then hard on. They are the
	--           afterburners.
	--
	-- That split is the whole reason a boost reads as an event: if
	-- everything glowed with speed there would be nothing left to change
	-- when you actually boosted.
	--
	-- The two *Mesh parts are housings and are deliberately not touched.
	-- THE MESHES ARE THE GLOW; Thruster/Thruster2 are the housings.
	--
	-- Named the other way round first, which lit the housing and left the
	-- part you actually see dark. Lists rather than single names so a rig
	-- that names them differently is one word here, not a code change.
	ThrusterCenterNames = { "CenterMesh" },
	ThrusterSideNames = { "SideThrustMesh" },
	ThrusterCenterTag = "KartThrusterCenter",
	ThrusterSideTag = "KartThrusterSide",

	-- Not pure black. A Neon part at 0,0,0 still catches a little bloom
	-- and reads as "off but present"; true black reads as a hole.
	ThrusterOff = Color3.fromRGB(8, 9, 14),

	-- The centre at full speed with no nitro.
	ThrusterCentre = Color3.fromRGB(96, 178, 255),
	-- And while nitro is burning.
	ThrusterNitro = Color3.fromRGB(255, 214, 92),
	-- The sides, which only ever show this or nothing.
	ThrusterBoost = Color3.fromRGB(255, 138, 48),

	-- Fraction of top speed before the centre starts to light. Without a
	-- floor it glows faintly while you roll around the lobby, which
	-- spends the effect before the race starts.
	ThrusterFloor = 0.18,

	-- How fast the colour chases, per second. Fast enough that a boost
	-- feels instant, slow enough that it is a fade rather than a switch.
	ThrusterRate = 12,

	AeroName = "Aero",
	AeroTag = "KartAero",

	-- Degrees the flap travels at full pitch input. A flap that swings far
	-- reads as a barn door; this is a control surface.
	AeroThrow = 24,
	AeroRate = 7, -- how fast it follows the input, per second

	-- The wings themselves. Fixed, but they still get motors: a welded
	-- part cannot move at all, and the flutter below needs somewhere to
	-- put a degree of movement.
	WingNames = { "Wing", "Wing_1" },
	WingTag = "KartWing",

	-- FLUTTER. Barely there on the ground, alive in the air.
	--
	-- The point is not realism, it is that a wing which never moves reads
	-- as a decal stuck to the side of the kart. One degree of wobble is
	-- enough to stop that, and more than about three looks broken.
	WingFlutter = 1.6, -- degrees of travel while gliding
	WingFlutterGround = 0.3, -- and while merely driving
	WingFlutterRate = 9, -- oscillations per second
	TireTag = "KartTire",

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

	-- HOW FAR THE FRONT WHEELS CROSS OVER, 0..1.
	--
	-- The counter-steer term used to be ADDED to the player's steering,
	-- and at full slip the two cancelled exactly: the wheels went from
	-- full lock to dead straight and never pointed the other way. Which
	-- is the one thing opposite lock is.
	--
	-- The mistake was treating the stick as "where the front wheels
	-- point" during a drift. It is not — mid-drift it means "how much
	-- drift", and the front wheels are doing something else entirely:
	-- catching the slide. So the two CROSSFADE as the slide develops
	-- rather than summing.
	--
	-- 1.0 is full crossover — at maximum slip the wheels are on full
	-- opposite lock regardless of the stick. 0.8 keeps a little of the
	-- driver's input visible in the tyres, which reads as a person
	-- holding it rather than an autopilot.
	RoadWheelCounterBlend = 0.85,

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
	-- How long before the watchdog will hand a player another character.
	-- LoadCharacter is asynchronous, and retrying it on every sweep
	-- while one is still arriving queues spawns behind each other.
	ReloadCooldown = 6,
	-- Slack on top of SeatDelay before the watchdog will call a kart
	-- missing. Building one is asynchronous, and a watchdog that races
	-- the normal path destroys what that path just made.
	SpawnGrace = 3,

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
