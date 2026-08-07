--[[
	Garage — the catalogue the customisation UI reads.

	WHY THIS EXISTS SEPARATELY FROM Config.Skins
	--------------------------------------------
	Config.Skins holds POOLS of mesh ids for the interim random dresser.
	A garage needs something a profile can name: `equipped = { Body =
	"stock" }` stores a KEY, not a mesh id, so there has to be a table
	that turns one into the other. That is this.

	OWNERSHIP IS PER PART, NEVER PER SET (matching DataService.Template's
	`parts`/`equipped` split). A set is a convenient thing to sell later;
	it is not the unit anything is stored as, which is what lets somebody
	mix a body from one set with wheels from another.

	NOTHING HERE CAN TOUCH HANDLING. Simulation reads the Hitbox and the
	Seat and nothing else — see Skins.luau — so every field below is
	decoration by construction rather than by discipline. Do not add a
	stat to an item here expecting it to do something.
--]]

return {
	-- TEST MODE. Everything selectable regardless of profile.parts, and
	-- nothing costs Bolt. Flip to false once the shop/purchase path is
	-- wired and items should actually be earned.
	UnlockedForTesting = true,

	-- TRACE THE WHOLE SAVE PATH, both ends.
	--
	-- Every failure mode in this chain is SILENT — a refused equip, a
	-- profile that has not loaded, a remote that is not there yet, and a
	-- write that lands in a mock store all look identical from the
	-- garage: you pick a part and it does not stick. This prints one line
	-- per step so the break is visible instead of inferred.
	--
	-- The line that matters most is the mock-store one. Studio ALWAYS
	-- mocks unless Config.Data.LiveInStudio is set, so the usual answer
	-- is "it saved perfectly, into a store that evaporates". That is
	-- warned about once at boot, which is a message nobody is reading an
	-- hour later; this repeats it at the moment of the save.
	Debug = true,

	-- CYCLE TEST — seconds between forced re-dresses. 0 = off.
	--
	-- Turns the whole profile/garage chain off and re-dresses every
	-- human's kart straight from the catalogue on this interval. It
	-- answers the ONE question the garage cannot: can the kart the player
	-- rides wear a different mesh at all?
	--
	--   meshes visibly change -> the swap pipeline works, and the bug is
	--                            upstream in what the profile resolves to
	--   nothing changes       -> the log names every part on that kart and
	--                            whether any of them is even a MeshPart,
	--                            which is what Config.Rig needs to match
	--
	-- 4 is a good value: slow enough to see, fast enough to be obvious.
	-- TURN IT OFF before anyone else plays — it overrides what they chose.
	CycleTest = 0,

	-- HIDE THE PREVIEW KART UNTIL IT IS WEARING THE RIGHT THING.
	--
	-- The profile arrives from a DataStore round trip, so there is always
	-- a gap between the menu appearing and the look being known. Nothing
	-- can close that gap — the only choice is what the player sees during
	-- it, and showing a stock kart that then pops into their real one
	-- reads as the customisation not having saved. Which is precisely how
	-- it was reported.
	--
	-- So the stage kart starts invisible and fades in once dressed. It
	-- uses LocalTransparencyModifier, which is render-only and does not
	-- touch the authored Transparency, so art with deliberately
	-- see-through parts survives untouched.
	--
	-- 0 disables the fade and shows the kart immediately.
	PreviewFadeTime = 0.3,

	-- Reveal anyway after this long, even if nothing ever arrived. A
	-- profile that fails to load must not leave an invisible kart on the
	-- menu — a missing kart is a worse failure than a stock one.
	PreviewMaxWait = 8,

	-- THE SAME TRICK FOR THE KART YOU ACTUALLY RIDE.
	--
	-- A spawned kart is built, then dressed asynchronously — the mesh
	-- swap fetches over the network — so there is always a moment where
	-- it exists wearing the default. Seating is instant, so the player
	-- watches their own kart change shape underneath them, which reads as
	-- a glitch rather than as loading.
	--
	-- So it spawns invisible and fades in once dressed. SERVER side, so
	-- it cannot use LocalTransparencyModifier like the menu preview does:
	-- each part's original Transparency is recorded and restored exactly,
	-- which is what stops a canopy or a glass panel being flattened
	-- opaque the first time it spawns.
	--
	-- Seating is NOT delayed. Control is available immediately and this
	-- is purely what you see — a kart you cannot drive for half a second
	-- is a worse trade than one that fades in.
	--
	-- 0 disables it and the kart appears immediately, undressed.
	SpawnFadeTime = 0.35,

	-- Give up and show it anyway. A mesh that never loads must not leave
	-- an invisible kart under the player.
	SpawnMaxWait = 6,

	-- How often Loadout re-checks that the kart on the menu stage is
	-- still the one it dressed. Cheap — one function call and two
	-- comparisons — and it runs for the whole session rather than in a
	-- window that has to be guessed right.
	TrackInterval = 0.4,

	-- Slot order is UI order.
	--
	-- FRONT AND REAR ARE STILL A PAIR. A kart with mismatched axles reads
	-- as a bug rather than as a build, so one rim choice and one tyre
	-- choice go on all four corners.
	--
	-- RIM AND TYRE ARE NOT A PAIR, and that is the point of the new rig.
	-- A wheel is a Model holding both, so they are two independent
	-- purchases that combine — gold rims on rally tyres is a build
	-- somebody chose, not an inconsistency.
	Slots = { "Body", "Rim", "Tire", "Paint" },

	SlotLabels = {
		Body = "BODY",
		Rim = "RIMS",
		Tire = "TYRES",
		Paint = "PAINT",
	},

	--== BODIES ========================================================
	-- `mesh` is swapped onto the MeshPart named "Body" on the kart.
	Bodies = {
		{ id = "stock", name = "STOCK", mesh = "", price = 0 },
		{ id = "aero", name = "AERO", mesh = "rbxassetid://72597967734984", price = 250 },
		{ id = "brute", name = "BRUTE", mesh = "rbxassetid://89589911208680", price = 250 },
		{ id = "gt", name = "GT", mesh = "rbxassetid://132060041489941", price = 300 },
	},

	--== RIMS ==========================================================
	-- Swapped onto every MeshPart named "Rim" inside the four wheel
	-- Models. Cheaper than tyres on purpose: a rim is the smaller part of
	-- the silhouette, and the first thing somebody buys should be cheap.
	Rims = {
		{ id = "stock", name = "STOCK", mesh = "", price = 0 },
		{ id = "split", name = "SPLIT SIX", mesh = "", price = 150 },
		{ id = "mesh", name = "MESH", mesh = "", price = 150 },
		{ id = "dish", name = "DEEP DISH", mesh = "", price = 220 },
	},

	--== TYRES =========================================================
	-- Swapped onto every MeshPart named "Tire". These carry the old
	-- wheel meshes, because the whole-wheel mesh was mostly tyre — so a
	-- player who owned SLICKS still owns something that looks like what
	-- they bought. See the migration note in GarageService.
	Tires = {
		{ id = "stock", name = "STOCK", mesh = "", price = 0 },
		{ id = "slick", name = "SLICKS", mesh = "rbxassetid://136481236962745", price = 200 },
		{ id = "rally", name = "RALLY", mesh = "rbxassetid://124866750857410", price = 200 },
	},

	--== WHEELS (LEGACY) ===============================================
	-- The pre-split catalogue: one mesh for the whole wheel. Kept ONLY so
	-- an existing profile's saved id still resolves to a name and a price
	-- while it is being migrated. Nothing should add to this list.
	Wheels = {
		{ id = "stock", name = "STOCK", mesh = "", price = 0 },
		{ id = "slick", name = "SLICKS", mesh = "rbxassetid://136481236962745", price = 200 },
		{ id = "rally", name = "RALLY", mesh = "rbxassetid://124866750857410", price = 200 },
	},

	--== PAINT =========================================================
	-- Applied to the SAME part the body mesh goes on ("Body"), so paint
	-- and shape are always talking about the same object. Costs no new
	-- asset, which is why it is the cheapest variety in the game.
	--
	-- `colour = nil` means "leave whatever colour the kart was built
	-- with" — the honest default, and distinct from painting it white.
	Paints = {
		{ id = "stock", name = "FACTORY", colour = nil, price = 0 },
		{ id = "red", name = "RACE RED", colour = Color3.fromRGB(196, 40, 40), price = 120 },
		{ id = "gold", name = "GOLD", colour = Color3.fromRGB(226, 178, 48), price = 180 },
		{ id = "blue", name = "ELECTRIC", colour = Color3.fromRGB(35, 130, 226), price = 120 },
		{ id = "green", name = "TOXIC", colour = Color3.fromRGB(88, 190, 62), price = 120 },
		{ id = "purple", name = "VIOLET", colour = Color3.fromRGB(126, 78, 214), price = 150 },
		{ id = "black", name = "MIDNIGHT", colour = Color3.fromRGB(28, 30, 36), price = 150 },
		{ id = "white", name = "CHALK", colour = Color3.fromRGB(232, 234, 238), price = 120 },
	},
}
