--[[
	ObuTools — one panel instead of nine plugin buttons.

	WHAT THIS IS
	------------
	The tools I actually reach for, in one dockable window, all sharing
	one undo policy, one theme and one status line. It is not a clone of
	F3X — F3X is a better F3X than anything written in an afternoon — it
	is the gap between the good plugins: the UI scaling AutoScale does,
	the curve Archimedes does, the wedges GapFill does, the scatter
	Brushtool does, and a tag panel that answers the question Studio's own
	one does not.

	THE RULES EVERY TOOL FOLLOWS
	----------------------------
	1. ONE ACTION IS ONE UNDO. Everything goes through Core.History, and
	   a stroke that placed sixty rocks undoes as one step. A tool you
	   cannot undo is a tool you use nervously, which means you do not
	   use it.

	2. NOTHING RUNS BEHIND A CLOSED PANEL. Every tab gets a context with
	   visible(), onShow and onHide, and anything that draws into the
	   viewport clears itself on the way out. This was a real bug, not a
	   precaution: the arc preview used to survive closing the window and
	   then follow your selection around the map.

	3. NO HARDCODED COLOURS. Every colour is asked for by name from the
	   Studio theme, so light mode is not a second code path. Painters are
	   bound to the instance they paint with a weak key, so rebuilding
	   panels does not leak them.

	4. IT SAYS WHAT IT DID, IN ONE PLACE. The status bar at the bottom is
	   per-tab, so a background panel cannot overwrite what the one you
	   are looking at just told you. "12 converted to scale, 3 skipped"
	   is a diagnostic; silence is not.

	5. REFUSE RATHER THAN GUESS. Degenerate input — three points in a
	   line, a zero-size parent, a missing template — stops with a
	   message. See GapFill for why: a NaN CFrame produces a part you
	   cannot see, select or delete.

	BUILD IT WITH ./build.sh — argon drops it straight into Studio's
	plugins folder. ./build.sh watch rebuilds on save.
--]]

local Ghost = require(script.Core.Ghost)
local Store = require(script.Core.Store)
local Theme = require(script.Core.Theme)
local Ui = require(script.Core.Ui)
local Widget = require(script.Core.Widget)

local Align = require(script.Tools.Align)
local Anchor = require(script.Tools.Anchor)
local Arc = require(script.Tools.Arc)
local Brush = require(script.Tools.Brush)
local GapFill = require(script.Tools.GapFill)
local Gradients = require(script.Tools.Gradients)
local Scaler = require(script.Tools.Scaler)
local Tags = require(script.Tools.Tags)

Store.init(plugin)
Theme.start()

-- BEFORE ANY TOOL MAKES ITS OWN. A rebuild reloads the plugin without
-- running anything's cleanup, so every ./build.sh with a preview on
-- screen used to strand a ghost holder under the Camera.
Ghost.sweep()

local toolbar = plugin:CreateToolbar("OBU")
local button = toolbar:CreateButton("ObuTools", "Build, UI and tag tools", "rbxasset://textures/StudioToolbox/Recent.png")
button.ClickableWhenViewportHidden = true

local widget = Widget.new(plugin, "ObuTools", "OBU Tools")

--=====================================================================
--  TABS
--
--  Built once at startup, not on demand. Tools hold live state — the
--  brush's template, the arc's radius — and rebuilding a panel on every
--  tab switch would silently reset it.
--=====================================================================

local build, buildCtx = widget:addTab("Build")
Arc.build(build, buildCtx)
Ui.divider(build)
Brush.build(build, buildCtx, plugin)
Ui.divider(build)
GapFill.build(build, buildCtx)
Ui.divider(build)
Align.build(build, buildCtx)

local ui, uiCtx = widget:addTab("UI")
Scaler.build(ui, uiCtx)
Ui.divider(ui)
Anchor.build(ui, uiCtx)
Ui.divider(ui)
Gradients.build(ui, uiCtx)

local tags, tagsCtx = widget:addTab("Tags")
Tags.build(tags, tagsCtx)

widget:show("Build")

--=====================================================================
--  TOOLBAR
--=====================================================================

button.Click:Connect(function()
	widget:toggle()
end)

-- Kept in step with the window's own close button, which does not go
-- through the click handler above — otherwise the toolbar button stays
-- lit over a closed panel and the next click appears to do nothing.
widget.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.gui.Enabled)
end)
button:SetActive(widget.gui.Enabled)

-- The other half of Ghost.sweep: on a clean unload there is no reason to
-- leave anything behind at all.
plugin.Unloading:Connect(function()
	Ghost.sweep()
end)

print("[ObuTools] ready — Build / UI / Tags.")
