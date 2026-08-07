--[[
	Arc — repeat a part around a curve. The Archimedes idea, with its UI.

	YOU SEE IT BEFORE YOU BUILD IT.
	-------------------------------
	Every control here re-poses a live ghost. Drag the dial and the curve
	sweeps in the viewport; nothing exists in the place until you press
	Build. The version without this was place → look → undo → retype →
	place, which is why a numbers-only arc tool never feels good no matter
	how correct the numbers are.

	THE SWEEP IS THE DIAL, THE STEP IS DERIVED.
	-------------------------------------------
	You care whether the ring CLOSES, not what each copy's angle is. So
	the dial sets the total sweep and the per-copy step falls out of it as
	sweep / copies. 360° with any number of copies is a closed circle
	without arithmetic — which is the thing you were going to reach for a
	calculator to work out.

	ROTATION IS ABOUT AN ARBITRARY LINE, NOT AN AXIS THROUGH THE ORIGIN.
	--------------------------------------------------------------------
	    T = translate(pivot) · rotate(axis, angle) · translate(-pivot)

	That is the standard conjugation for rotating about a line through a
	point, and using it means the three axis buttons are the same code
	path rather than three special cases. X gives you a vertical loop, Y a
	curved wall, Z a barrel roll.

	EVERY COPY IS PLACED FROM THE ORIGINAL. Chaining each clone off the
	previous one compounds floating-point error, and on a 90-piece
	roundabout the last piece visibly misses the first. Pose `i` is the
	original rotated by `i · step`, so error never accumulates and the
	ring closes exactly.
--]]

local Ghost = require(script.Parent.Parent.Core.Ghost)
local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Ui = require(script.Parent.Parent.Core.Ui)

local Arc = {}

function Arc.build(page: Instance, ctx)
	local copies, sweep, radius, rise = 12, 180, 20, 0
	local axis, flip = "Y", 1
	local base: BasePart? = nil

	local ghost = Ghost.new("Arc")
	local refresh -- forward declared; every control calls it

	--=====================================================================
	--  GEOMETRY
	--=====================================================================

	-- The axis to spin about, and the direction the centre of the circle
	-- lies in. Both are the PART's own axes, so "curve left" means left
	-- relative to the thing you selected rather than to the world.
	local function frame(part: BasePart): (Vector3, Vector3)
		local cf = part.CFrame
		if axis == "X" then
			return cf.RightVector, cf.UpVector
		elseif axis == "Z" then
			return cf.LookVector, cf.UpVector
		end
		return cf.UpVector, cf.RightVector
	end

	local function poses(): { CFrame }
		local part = base
		if not part or not part.Parent or copies < 1 or math.abs(radius) < 1e-3 then
			return {}
		end

		local spin, out = frame(part)
		local pivot = part.Position + out * (radius * flip)
		-- Derived, not typed. See the note above.
		local stepDeg = sweep / copies

		local list = {}
		for i = 1, copies do
			local turn = CFrame.fromAxisAngle(spin, math.rad(stepDeg * i * -flip))
			-- Rotate about the line through `pivot` along `spin`.
			local about = CFrame.new(pivot) * turn * CFrame.new(-pivot)
			list[i] = (about * part.CFrame) + spin * (rise * i)
		end
		return list
	end

	--=====================================================================
	--  PANEL
	--=====================================================================

	local sec = Ui.section(page, "Arc", "arc1")
	local sourceLabel = Ui.label(sec, "Select a part to preview an arc from it.", true)

	Ui.label(sec, "Spin around", true)
	local _, setAxis = Ui.choice(sec, { "X", "Y", "Z" }, axis, function(name)
		axis = name
		refresh()
	end)

	local dial = Ui.dial(sec, "Total sweep", sweep, 720, function(v)
		sweep = v
		refresh()
	end)

	local copiesKnob = Ui.slider(sec, "Copies", 1, 120, copies, 1, function(v)
		copies = math.floor(v)
		refresh()
	end)
	local radiusKnob = Ui.slider(sec, "Radius", 1, 200, radius, 0.5, function(v)
		radius = v
		refresh()
	end)
	local riseKnob = Ui.slider(sec, "Rise per copy", -10, 10, rise, 0.1, function(v)
		rise = v
		refresh()
	end)


	local dirRow = Ui.row(sec, 26)
	Ui.button(dirRow, "Flip direction", function()
		flip = -flip
		refresh()
	end, 0.5)
	Ui.button(dirRow, "Close the ring", function()
		-- Not "set 360": a spiral staircase wants 720 and keeping the
		-- current number of turns is the more useful answer.
		sweep = if sweep > 360 then 720 else 360
		dial.set(sweep)
		refresh()
	end, 0.5)

	--=====================================================================
	--  PREVIEW AND COMMIT
	--=====================================================================

	refresh = function()
		-- NOTHING IS DRAWN INTO A VIEWPORT NOBODY ASKED. The ghost is a
		-- thing you can see; if the panel is not on screen there is no one
		-- to see it and no way to clear it.
		if not ctx.visible() then
			return
		end
		local parts = Sel.parts(false)
		-- A ghost is only ever built from ONE part. Two selected would be
		-- two overlapping arcs and no way to say which is which.
		base = if #parts == 1 then parts[1] else nil

		if not base then
			sourceLabel.Text = if #parts == 0 then "Select one part." else ("Select ONE part — %d selected."):format(#parts)
			ghost:clear()
			ctx.status(if #parts == 0 then "Select one part to preview an arc." else "Select ONE part.", "warn")
			return
		end

		sourceLabel.Text = ("From: %s"):format(base.Name)
		ghost:update(base, poses())
		ctx.status(("%d × %.2f° = %.0f°%s"):format(
			copies,
			sweep / math.max(copies, 1),
			sweep,
			if math.abs(sweep - 360) < 0.01 then "  ·  closed ring" else ""
		))
	end

	Ui.button(page, "Build it", function()
		if not base then
			ctx.status("Nothing to build — select one part.", "warn")
			return
		end
		local made = History.run("Arc", function()
			return ghost:commit(base.Parent)
		end)
		if made and #made > 0 then
			-- Cleared first: selecting the new parts fires the selection
			-- hook below, and a stale ghost sitting inside the real ones
			-- looks like the tool built them twice.
			ghost:clear()
			Sel.set(made)
			ctx.status(("Built %d."):format(#made), "ok")
		end
	end, nil, "primary")

	Ui.button(page, "Clear preview", function()
		ghost:clear()
		ctx.status("Preview cleared.")
	end, nil, "quiet")

	-- The ghost follows the selection, so picking a different part
	-- re-previews without touching a control.
	Sel.changed(function()
		task.defer(refresh)
	end)

	-- The panel going away takes the ghost with it — for both reasons it
	-- can go away, since the tool does not get to know which.
	ctx.onHide(function()
		ghost:clear()
	end)
	ctx.onShow(refresh)

	copiesKnob.set(copies)
	radiusKnob.set(radius)
	riseKnob.set(rise)
	setAxis(axis)
	refresh()
end

return Arc
