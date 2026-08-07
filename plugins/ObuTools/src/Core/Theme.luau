--[[
	Theme — Studio's own colours, not ours.

	Every colour in this plugin is asked for by NAME from the Studio theme
	rather than written as a hex value. That is the whole reason it stops
	looking wrong when you switch to light mode: a plugin with hardcoded
	greys is a dark rectangle sitting in a white window, and there is no
	amount of picking nicer greys that fixes it.

	PAINTERS ARE BOUND TO THE THING THEY PAINT, WEAKLY.
	---------------------------------------------------
	The first version kept one flat list of repaint closures. Panels that
	rebuild — the gradient list, the tag list, both of which redraw on
	every selection change — added a closure per row per rebuild and never
	removed one. After an hour of clicking around, a theme switch would
	repaint several thousand rows that had been destroyed long ago.

	Binding to the Instance with a WEAK KEY fixes it at the root: when the
	row is destroyed and forgotten, the entry goes with it, and nothing
	has to remember to unregister. Lifetime follows the object rather than
	being managed by hand, which is the only version of this that stays
	correct as tools get added.
--]]

local Theme = {}

-- Instance -> the closures that paint it. Weak keys, so a destroyed and
-- dereferenced row takes its painters with it at the next collection.
local bound: { [Instance]: { () -> () } } = setmetatable({}, { __mode = "k" }) :: any
-- For the handful of painters with no single owner.
local loose: { () -> () } = {}

-- Studio's palette, by role. `modifier` handles hover/pressed/disabled
-- states without needing a second colour per widget.
function Theme.color(name: string, modifier: string?): Color3
	local guide = (Enum.StudioStyleGuideColor :: any)[name]
	if not guide then
		return Color3.fromRGB(255, 0, 255) -- loud on purpose: a typo should be visible
	end
	local mod = if modifier then (Enum.StudioStyleGuideModifier :: any)[modifier] else nil
	return settings().Studio.Theme:GetColor(guide, mod)
end

--=====================================================================
--  OUR OWN COLOURS
--
--  Deliberately few. Everything structural comes from Studio; these are
--  only for meaning Studio has no name for — "this is active", "that
--  worked", "that did not".
--=====================================================================

Theme.ACCENT = Color3.fromRGB(226, 88, 62)
Theme.ACCENT_DIM = Color3.fromRGB(150, 58, 41)
Theme.OK = Color3.fromRGB(96, 176, 112)
Theme.WARN = Color3.fromRGB(214, 154, 64)

function Theme.isDark(): boolean
	-- Judged from the background rather than the theme's name, so a
	-- custom theme still gets the right answer.
	local bg = Theme.color("MainBackground")
	return (bg.R + bg.G + bg.B) / 3 < 0.5
end

--=====================================================================
--  PAINTING
--=====================================================================

-- Runs once now, and again on every theme change for as long as `inst`
-- is alive. The normal way to register.
function Theme.bind(inst: Instance, fn: () -> ())
	local list = bound[inst]
	if not list then
		list = {}
		bound[inst] = list
	end
	table.insert(list, fn)
	fn()
end

-- For painters that outlive any single instance. Held strongly, so use
-- it only for things that genuinely live as long as the plugin.
function Theme.paint(fn: () -> ())
	table.insert(loose, fn)
	fn()
end

function Theme.start()
	settings().Studio.ThemeChanged:Connect(function()
		for _, fn in loose do
			task.spawn(fn)
		end
		for inst, list in bound do
			-- A destroyed instance can still be written to; it is simply
			-- pointless. Skipping keeps a theme switch proportional to what
			-- is on screen rather than to everything ever created.
			if inst.Parent then
				for _, fn in list do
					task.spawn(fn)
				end
			end
		end
	end)
end

return Theme
