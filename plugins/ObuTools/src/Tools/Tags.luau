--[[
	Tags — every CollectionService tag in the place, with counts.

	NOT A NICETY. In a tag-driven game the tag IS the wiring: a cone is
	scenery because it is tagged Props, a part is a checkpoint because it
	is tagged Checkpoint. Which means a MISSING tag is a feature that
	silently does nothing — no error, no warning, just a lap counter that
	never counts and a cone that behaves like a wall.

	Studio's own tag panel shows you the tags on the thing you have
	selected. The question you actually have is the other way round: how
	many Checkpoints are in this place, and where are they? That question
	is the one that catches a half-set-up map before you playtest it.

	COUNTS ARE THE POINT. "Checkpoint 0" on a race track tells you
	instantly what twenty minutes of driving in circles would.
--]]

local CollectionService = game:GetService("CollectionService")

local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Ui = require(script.Parent.Parent.Core.Ui)

local Tags = {}

function Tags.build(page: Instance, ctx)
	local sec = Ui.section(page, "Apply", "tags1")
	local nameBox = Ui.text(sec, "Tag name")

	local refresh

	local function applyTag(name: string, add: boolean)
		if name == "" then
			ctx.status("Type a tag name first.")
			return
		end
		local targets = Sel.get()
		if #targets == 0 then
			ctx.status("Nothing selected.")
			return
		end
		History.run((if add then "Add tag " else "Remove tag ") .. name, function()
			for _, inst in targets do
				if add then
					CollectionService:AddTag(inst, name)
				else
					CollectionService:RemoveTag(inst, name)
				end
			end
		end)
		ctx.status(("%s %q on %d."):format(if add then "Added" else "Removed", name, #targets))
		refresh()
	end

	local applyRow = Ui.row(sec)
	Ui.button(applyRow, "Add to selection", function()
		applyTag(nameBox.Text, true)
	end, 0.5)
	Ui.button(applyRow, "Remove", function()
		applyTag(nameBox.Text, false)
	end, 0.5)

	--== SELECTED ======================================================
	local onSel = Ui.section(page, "On selection", "tags2")
	local selHolder = Ui.list(onSel, 3)

	--== ALL TAGS ======================================================
	local allSec = Ui.section(page, "In this place", "tags3")
	local allHolder = Ui.list(allSec, 3)

	local function clear(holder: Instance)
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	refresh = function()
		clear(selHolder)
		clear(allHolder)

		-- WHAT THE SELECTION CARRIES
		local onSelected: { [string]: number } = {}
		local selection = Sel.get()
		for _, inst in selection do
			for _, tag in CollectionService:GetTags(inst) do
				onSelected[tag] = (onSelected[tag] or 0) + 1
			end
		end
		local selNames = {}
		for tag in onSelected do
			table.insert(selNames, tag)
		end
		table.sort(selNames)

		if #selection == 0 then
			Ui.label(selHolder, "Nothing selected.", true)
		elseif #selNames == 0 then
			Ui.label(selHolder, ("%d selected, no tags."):format(#selection), true)
		else
			for _, tag in selNames do
				local row = Ui.row(selHolder, 22)
				Ui.label(row, ("%s  (%d/%d)"):format(tag, onSelected[tag], #selection)).Size =
					UDim2.fromScale(0.72, 1)
				Ui.button(row, "Remove", function()
					applyTag(tag, false)
				end, 0.26)
			end
		end

		-- EVERY TAG IN THE PLACE, WITH ITS POPULATION
		local all = CollectionService:GetAllTags()
		table.sort(all)
		if #all == 0 then
			Ui.label(allHolder, "No tags in this place.", true)
			return
		end
		for _, tag in all do
			local n = #CollectionService:GetTagged(tag)
			local row = Ui.row(allHolder, 22)
			local label = Ui.label(row, ("%s  ×%d"):format(tag, n), n == 0)
			label.Size = UDim2.fromScale(0.72, 1)
			label.AutomaticSize = Enum.AutomaticSize.None
			-- Selecting everything with a tag is how you SEE the answer.
			-- A count says "0 checkpoints"; a selection shows you the four
			-- that are tagged and the gap where the fifth should be.
			Ui.button(row, "Select", function()
				local tagged = CollectionService:GetTagged(tag)
				Sel.set(tagged)
				ctx.status(("Selected %d tagged %q."):format(#tagged, tag))
			end, 0.26)
		end
	end

	Ui.button(page, "Refresh", refresh)

	-- Live, so the panel matches what you have clicked without a button
	-- press. Throttled through a flag rather than debounced by time: the
	-- rebuild is cheap and the delay would be more noticeable than the work.
	local queued = false
	Sel.changed(function()
		-- Not while hidden. This is the panel that rebuilds most, and a
		-- rebuild nobody can see is work plus a fresh set of theme
		-- bindings for rows that will be thrown away unread.
		if queued or not ctx.visible() then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			refresh()
		end)
	end)

	-- Caught up on the way back in, since changes made while hidden were
	-- deliberately ignored above.
	ctx.onShow(refresh)

	refresh()
end

return Tags
