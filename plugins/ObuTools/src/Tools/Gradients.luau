--[[
	Gradients — save a gradient once, reuse it everywhere.

	Roblox has no way to save a UIGradient as a preset. You either rebuild
	the keypoints by hand on every element or you copy-paste an existing
	one and then forget which of the six copies is the current one. This
	stores them by name and applies them to anything selected.

	WHY THE SEQUENCES ARE TAKEN APART BEFORE SAVING
	-----------------------------------------------
	plugin:SetSetting serialises through JSON. A ColorSequence is not a
	JSON value — saving one directly stores nothing at all, silently, and
	you find out when the preset comes back empty. So each keypoint is
	broken down to plain numbers on the way in and rebuilt on the way out.

	Roblox also requires a sequence to have at least two keypoints and to
	start at 0 and end at 1. Rebuilding enforces that, because a preset
	saved from a malformed gradient would otherwise throw when applied and
	take the whole button with it.
--]]

local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Store = require(script.Parent.Parent.Core.Store)
local Ui = require(script.Parent.Parent.Core.Ui)

local Gradients = {}

local KEY = "gradients"

--=====================================================================
--  SERIALISATION
--=====================================================================

local function packColor(seq: ColorSequence): { any }
	local out = {}
	for _, kp in seq.Keypoints do
		table.insert(out, { t = kp.Time, r = kp.Value.R, g = kp.Value.G, b = kp.Value.B })
	end
	return out
end

local function unpackColor(data: any): ColorSequence
	local points = {}
	if type(data) == "table" then
		for _, k in data do
			if type(k) == "table" and type(k.t) == "number" then
				table.insert(points, ColorSequenceKeypoint.new(math.clamp(k.t, 0, 1), Color3.new(k.r, k.g, k.b)))
			end
		end
	end
	-- A sequence needs two keypoints minimum, spanning 0 to 1. Anything
	-- that cannot satisfy that is replaced rather than thrown, so a
	-- corrupt preset degrades to plain white instead of erroring.
	if #points < 2 then
		return ColorSequence.new(Color3.new(1, 1, 1))
	end
	table.sort(points, function(a, b)
		return a.Time < b.Time
	end)
	points[1] = ColorSequenceKeypoint.new(0, points[1].Value)
	points[#points] = ColorSequenceKeypoint.new(1, points[#points].Value)
	return ColorSequence.new(points)
end

local function packNumber(seq: NumberSequence): { any }
	local out = {}
	for _, kp in seq.Keypoints do
		table.insert(out, { t = kp.Time, v = kp.Value, e = kp.Envelope })
	end
	return out
end

local function unpackNumber(data: any): NumberSequence
	local points = {}
	if type(data) == "table" then
		for _, k in data do
			if type(k) == "table" and type(k.t) == "number" then
				table.insert(points, NumberSequenceKeypoint.new(math.clamp(k.t, 0, 1), k.v or 0, k.e or 0))
			end
		end
	end
	if #points < 2 then
		return NumberSequence.new(0)
	end
	table.sort(points, function(a, b)
		return a.Time < b.Time
	end)
	points[1] = NumberSequenceKeypoint.new(0, points[1].Value, points[1].Envelope)
	points[#points] = NumberSequenceKeypoint.new(1, points[#points].Value, points[#points].Envelope)
	return NumberSequence.new(points)
end

--=====================================================================
--  STORAGE
--=====================================================================

local function all(): { [string]: any }
	local saved = Store.get(KEY, nil)
	return if type(saved) == "table" then saved else {}
end

local function save(presets: { [string]: any })
	Store.set(KEY, presets)
end

--=====================================================================
--  PANEL
--=====================================================================

function Gradients.build(page: Instance, ctx)
	local sec = Ui.section(page, "Gradients", "grad1")
	Ui.label(sec, "Select a UIGradient to save it, or any UI element to apply one.", true)

	local nameBox = Ui.text(sec, "Preset name")

	local listSection = Ui.section(page, "Saved", "grad2")
	local listHolder = Ui.list(listSection, 4)

	local refresh -- forward declared: the row buttons rebuild the list

	local function applyPreset(name: string)
		local preset = all()[name]
		if not preset then
			return
		end
		local targets = Sel.guis(false)
		if #targets == 0 then
			ctx.status("Select a UI element to apply it to.")
			return
		end
		History.run("Apply gradient " .. name, function()
			for _, obj in targets do
				-- Reuses an existing gradient rather than stacking a second
				-- one, because two UIGradients on the same element is a
				-- state Roblox allows and nothing renders sensibly from.
				local gradient = obj:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
				gradient.Color = unpackColor(preset.color)
				gradient.Transparency = unpackNumber(preset.transparency)
				gradient.Rotation = preset.rotation or 0
				gradient.Offset = Vector2.new(preset.offsetX or 0, preset.offsetY or 0)
				gradient.Parent = obj
			end
		end)
		ctx.status(("Applied %q to %d."):format(name, #targets))
	end

	local function deletePreset(name: string)
		local presets = all()
		presets[name] = nil
		save(presets)
		refresh()
		ctx.status(("Deleted %q."):format(name))
	end

	refresh = function()
		for _, child in listHolder:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local presets = all()
		local names = {}
		for name in presets do
			table.insert(names, name)
		end
		table.sort(names)

		if #names == 0 then
			Ui.label(listHolder, "Nothing saved yet.", true)
			return
		end

		for _, name in names do
			local row = Ui.row(listHolder, 24)
			Ui.button(row, name, function()
				applyPreset(name)
			end, 0.78)
			Ui.button(row, "✕", function()
				deletePreset(name)
			end, 0.2)
		end
	end

	Ui.button(sec, "Save selected gradient", function()
		local found: UIGradient? = nil
		for _, inst in Sel.get() do
			if inst:IsA("UIGradient") then
				found = inst
				break
			end
			local child = inst:FindFirstChildOfClass("UIGradient")
			if child then
				found = child
				break
			end
		end
		if not found then
			ctx.status("Select a UIGradient, or an element that has one.")
			return
		end

		local name = nameBox.Text
		if name == "" then
			name = ("Gradient %d"):format(os.time() % 10000)
		end

		local presets = all()
		presets[name] = {
			color = packColor(found.Color),
			transparency = packNumber(found.Transparency),
			rotation = found.Rotation,
			offsetX = found.Offset.X,
			offsetY = found.Offset.Y,
		}
		save(presets)
		nameBox.Text = ""
		refresh()
		ctx.status(("Saved %q."):format(name))
	end)

	refresh()
end

return Gradients
