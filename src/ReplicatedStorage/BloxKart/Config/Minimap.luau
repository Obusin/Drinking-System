--[[
	Minimap — the track, drawn from the same nodes the bots drive.

	Built from Route.nodes() rather than from anything authored
	separately, so the map and the racing line CANNOT disagree. A map
	maintained by hand is a second answer to "where does the track go",
	and this project has paid for those repeatedly.

	Not a ViewportFrame. That renders real geometry — a camera, the whole
	track in frame, a render pass every frame — to produce a picture,
	when what a minimap wants is a schematic.
--]]

return {
	Enabled = true,

	--== MODE ==========================================================
	-- "north"   the map is fixed; your arrow rotates on it
	-- "heading" the map rotates; your arrow always points up
	--
	-- North-up for now. Heading-up is BUILT and works — it is one string
	-- away — and belongs in a settings menu rather than in a config file
	-- nobody but us can reach. It is easier to learn a track from a map
	-- that holds still and easier to drive one from a map that turns,
	-- which is exactly the kind of thing a player should choose.
	Mode = "north",

	--== PLACEMENT =====================================================
	-- Bottom left. The bottom right is the lap and time readout, the top
	-- corners are the balances and the match status.
	Position = UDim2.new(0, 24, 1, -24),
	Anchor = Vector2.new(0, 1),
	Size = Vector2.new(210, 210),
	-- Fraction of the map's half-size left empty at the edges, so a
	-- track that touches the bounding box does not touch the frame.
	Padding = 0.12,

	BackgroundColor = Color3.fromRGB(14, 14, 16),
	BackgroundTransparency = 0.35,

	--== THE TRACK =====================================================
	-- Drawn once as a chain of thin rotated frames, one per pair of
	-- nodes. Segments are drawn slightly long so the joins do not show
	-- as gaps on a corner.
	TrackColor = Color3.fromRGB(88, 92, 104),
	TrackThickness = 5,
	SegmentOverlap = 2, -- pixels added to each segment's length

	-- The start/finish node, so a lap has a landmark.
	StartColor = Color3.fromRGB(255, 255, 255),
	StartSize = 7,

	--== RACERS ========================================================
	SelfColor = Color3.fromRGB(255, 196, 62),
	SelfSize = 11,
	RacerColor = Color3.fromRGB(210, 214, 224),
	RacerSize = 8,
	-- Anyone who has finished is still on the track for a few seconds
	-- while the AI drives them off. Dimmed rather than hidden — they are
	-- still in the way.
	FinishedTransparency = 0.6,
}
