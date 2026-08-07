--[[
	Ui — the widgets every tool is built from.

	NOT A UI FRAMEWORK. There is no state, no diffing and no reconciler,
	because a plugin panel is built once and then mutated by callbacks —
	the problem a framework solves is not a problem this has. Every
	function here returns a real Instance you can keep and change.

	THE RULES THE LOOK FOLLOWS
	--------------------------
	ONE GRID. Every gap, pad and height is a multiple of 4. Nothing is
	nudged by an odd pixel to make one panel look right, because that is
	how a UI ends up feeling assembled rather than designed.

	THREE WEIGHTS OF BUTTON, AND ONLY THREE. Primary is the thing you
	came here to do and there is at most one per panel. Normal is
	everything else. Quiet is for undoing, clearing and cancelling. If
	every button is loud then none of them are, which is exactly what a
	panel with fourteen identical grey rectangles feels like.

	LABELS ARE NOT SENTENCES IN THE SAME STYLE AS VALUES. Captions are
	dimmed and small; values are full contrast. That contrast is doing
	the work an icon set would otherwise have to.

	COLOUR MEANS SOMETHING. Accent is "active" or "primary" and nothing
	else. Green and amber only ever appear in the status bar. A UI where
	colour is decoration cannot use colour to tell you anything.
--]]

local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)

local Ui = {}

local FONT = Enum.Font.Gotham
local FONT_MED = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local UNIT = 4
Ui.UNIT = UNIT

local function corner(inst: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

--=====================================================================
--  LAYOUT
--=====================================================================

function Ui.list(parent: Instance, padding: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or UNIT)
	layout.Parent = frame

	return frame
end

function Ui.row(parent: Instance, height: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height or 26)
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, UNIT)
	layout.Parent = frame

	return frame
end

--=====================================================================
--  SECTION
--
--  Collapsible, and it REMEMBERS. A panel with eight sections open is
--  a wall; the whole point of collapsing is that your layout survives
--  closing Studio, otherwise you re-collapse the same six every launch
--  and stop bothering.
--=====================================================================

function Ui.section(parent: Instance, title: string, key: string?): Frame
	local storeKey = if key then "open_" .. key else nil
	local open = if storeKey then Store.get(storeKey, true) ~= false else true

	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(1, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BorderSizePixel = 0
	holder.Parent = parent
	corner(holder, 6)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = holder

	local shell = Ui.list(holder, 0)

	-- HEADER
	local header = Instance.new("TextButton")
	header.Text = ""
	header.AutoButtonColor = false
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 30)
	header.Parent = shell

	local chevron = Instance.new("TextLabel")
	chevron.BackgroundTransparency = 1
	chevron.Font = FONT
	chevron.TextSize = 10
	chevron.Text = "▾"
	chevron.Position = UDim2.fromOffset(10, 0)
	chevron.Size = UDim2.new(0, 12, 1, 0)
	chevron.Parent = header

	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Font = FONT_BOLD
	caption.TextSize = 11
	caption.TextXAlignment = Enum.TextXAlignment.Left
	-- Uppercased rather than styled: Roblox has no letter-spacing, and
	-- caps is the one typographic move available that reads as a header
	-- without shouting at 11px.
	caption.Text = title:upper()
	caption.Position = UDim2.fromOffset(26, 0)
	caption.Size = UDim2.new(1, -34, 1, 0)
	caption.Parent = header

	-- BODY
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = shell

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = body

	local inner = Ui.list(body, UNIT + 1)

	local function apply()
		body.Visible = open
		chevron.Text = if open then "▾" else "▸"
	end

	header.Activated:Connect(function()
		open = not open
		apply()
		if storeKey then
			Store.set(storeKey, open)
		end
	end)

	Theme.bind(holder, function()
		holder.BackgroundColor3 = Theme.color("Tab")
		stroke.Color = Theme.color("Border")
		caption.TextColor3 = Theme.color("DimmedText")
		chevron.TextColor3 = Theme.color("DimmedText")
	end)

	apply()
	return inner
end

--=====================================================================
--  TEXT
--=====================================================================

function Ui.label(parent: Instance, text: string, dim: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 12
	label.LineHeight = 1.15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.Size = UDim2.new(1, 0, 0, 14)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Parent = parent

	Theme.bind(label, function()
		label.TextColor3 = Theme.color(if dim then "DimmedText" else "MainText")
	end)

	return label
end

--=====================================================================
--  BUTTONS
--
--  `weight` fills a row proportionally; leave it nil outside a row.
--  `style` is "primary" | "normal" | "quiet".
--=====================================================================

function Ui.button(parent: Instance, text: string, onClick: () -> (), weight: number?, style: string?): TextButton
	local kind = style or "normal"

	local button = Instance.new("TextButton")
	button.Font = if kind == "primary" then FONT_MED else FONT
	button.TextSize = 12
	button.Text = text
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Size = if weight then UDim2.new(weight, 0, 1, 0) else UDim2.new(1, 0, 0, 28)
	button.Parent = parent
	corner(button, 5)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = if kind == "quiet" then 0.5 else 1
	stroke.Parent = button

	local hovered, held = false, false

	local function repaint()
		if kind == "primary" then
			local base = Theme.ACCENT
			button.BackgroundTransparency = 0
			button.BackgroundColor3 = if held
				then Theme.ACCENT_DIM
				elseif hovered then base:Lerp(Color3.new(1, 1, 1), 0.12)
				else base
			button.TextColor3 = Color3.new(1, 1, 1)
		elseif kind == "quiet" then
			button.BackgroundTransparency = if hovered then 0.85 else 1
			button.BackgroundColor3 = Theme.color("MainText")
			button.TextColor3 = Theme.color("DimmedText")
			stroke.Color = Theme.color("Border")
		else
			button.BackgroundTransparency = 0
			button.BackgroundColor3 = Theme.color("Button", if held then "Pressed" elseif hovered then "Hover" else nil)
			button.TextColor3 = Theme.color("ButtonText")
		end
	end

	Theme.bind(button, repaint)

	button.MouseEnter:Connect(function()
		hovered = true
		repaint()
	end)
	button.MouseLeave:Connect(function()
		hovered, held = false, false
		repaint()
	end)
	button.MouseButton1Down:Connect(function()
		held = true
		repaint()
	end)
	button.MouseButton1Up:Connect(function()
		held = false
		repaint()
	end)
	-- Wrapped, because an error thrown out of a click handler kills the
	-- connection and the button silently stops working from then on.
	button.Activated:Connect(function()
		local ok, err = pcall(onClick)
		if not ok then
			warn(("[ObuTools] %s failed: %s"):format(text, tostring(err)))
		end
	end)

	return button
end

--=====================================================================
--  TOGGLE
--=====================================================================

-- A toggle's lit state is derived from `get()`, so after a tool changes
-- whatever `get` reads it has to ask for a repaint. Kept in a registry
-- rather than stuck on the Instance: you cannot assign a function to a
-- Roblox object, and casting to `any` to pretend otherwise is the kind
-- of trick that works until someone reads it.
local repaints: { [TextButton]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

function Ui.toggle(parent: Instance, text: string, get: () -> boolean, onClick: () -> (), weight: number?): TextButton
	local holder = if weight then parent else Ui.row(parent, 26)

	local button = Instance.new("TextButton")
	button.Font = FONT
	button.TextSize = 12
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	button.Size = if weight then UDim2.new(weight, 0, 1, 0) else UDim2.fromScale(1, 1)
	button.Parent = holder

	-- A PILL SWITCH, NOT A LIT RECTANGLE. A rectangle that changes colour
	-- is indistinguishable from a button you just pressed; a switch reads
	-- as state at a glance, from across the panel, without reading the
	-- label.
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.fromOffset(26, 14)
	track.BorderSizePixel = 0
	track.Parent = button
	corner(track, 7)

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.BorderSizePixel = 0
	dot.Parent = track
	corner(dot, 5)

	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 12
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = text
	caption.Position = UDim2.fromOffset(34, 0)
	caption.Size = UDim2.new(1, -34, 1, 0)
	caption.Parent = button

	local function repaint()
		local on = get()
		track.BackgroundColor3 = if on then Theme.ACCENT else Theme.color("Border")
		dot.BackgroundColor3 = if on then Color3.new(1, 1, 1) else Theme.color("DimmedText")
		dot.Position = UDim2.fromScale(if on then 0.72 else 0.28, 0.5)
		caption.TextColor3 = Theme.color(if on then "MainText" else "DimmedText")
	end

	Theme.bind(button, repaint)
	repaints[button] = repaint

	button.Activated:Connect(function()
		local ok, err = pcall(onClick)
		if not ok then
			warn(("[ObuTools] %s failed: %s"):format(text, tostring(err)))
		end
	end)

	return button
end

-- Safe on anything, including nil — callers flip a flag and ask for a
-- repaint without first proving the button exists yet.
function Ui.repaint(button: TextButton?)
	if button then
		local fn = repaints[button]
		if fn then
			fn()
		end
	end
end

--=====================================================================
--  TEXT INPUT
--=====================================================================

function Ui.text(parent: Instance, placeholder: string): TextBox
	local box = Instance.new("TextBox")
	box.Font = FONT
	box.TextSize = 12
	box.Text = ""
	box.PlaceholderText = placeholder
	box.ClearTextOnFocus = false
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 26)
	box.Parent = parent
	corner(box, 5)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.6
	stroke.Parent = box

	Theme.bind(box, function()
		box.BackgroundColor3 = Theme.color("InputFieldBackground")
		box.TextColor3 = Theme.color("MainText")
		box.PlaceholderColor3 = Theme.color("DimmedText")
		stroke.Color = Theme.color("Border")
	end)

	box.Focused:Connect(function()
		stroke.Color = Theme.ACCENT
		stroke.Transparency = 0
	end)
	box.FocusLost:Connect(function()
		stroke.Color = Theme.color("Border")
		stroke.Transparency = 0.6
	end)

	return box
end

--=====================================================================
--  DRAGGING
--
--  A slider has to keep tracking after the pointer leaves the little
--  6px track it started on — otherwise every drag stops the moment you
--  move slightly off it, which feels broken rather than fiddly.
--
--  So a press spawns a transparent full-window overlay and the drag is
--  read from THAT. It is the standard fix and it is self-contained: no
--  UserInputService, no global state, and it cannot outlive the release
--  because the overlay is destroyed by the same handler that ends it.
--=====================================================================

local function captureDrag(source: GuiObject, onMove: (Vector2) -> ())
	local window = source:FindFirstAncestorWhichIsA("PluginGui")
	if not window then
		return
	end

	local overlay = Instance.new("TextButton")
	overlay.Text = ""
	overlay.BackgroundTransparency = 1
	overlay.AutoButtonColor = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 999
	overlay.Active = true
	overlay.Parent = window

	local done = false
	local moved: RBXScriptConnection, ended: RBXScriptConnection, upped: RBXScriptConnection

	local function finish()
		if done then
			return
		end
		done = true
		moved:Disconnect()
		ended:Disconnect()
		upped:Disconnect()
		overlay:Destroy()
	end

	moved = overlay.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			onMove(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	-- Two ways to hear the release, because which one fires depends on
	-- where the pointer is when you let go. `done` makes the second a
	-- no-op rather than a double free.
	ended = overlay.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			finish()
		end
	end)
	upped = overlay.MouseButton1Up:Connect(finish)
end

--=====================================================================
--  SLIDER
--=====================================================================

export type Knob = { get: () -> number, set: (number) -> () }

-- Drag or type. `step` of 1 gives integers; 0 leaves it continuous.
function Ui.slider(
	parent: Instance,
	text: string,
	min: number,
	max: number,
	value: number,
	step: number,
	onChange: (number) -> ()
): Knob
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 36)
	holder.Parent = parent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Size = UDim2.new(0.55, 0, 0, 14)
	label.Parent = holder

	-- The value is a TextBox, not a label, and it is not obviously one
	-- until you click it. A slider is for feel and a typed number is for
	-- "exactly 15" — a tool needs both, and hiding the second behind a
	-- separate field would double the width of every row.
	local readout = Instance.new("TextBox")
	readout.BackgroundTransparency = 1
	readout.Font = FONT_BOLD
	readout.TextSize = 12
	readout.TextXAlignment = Enum.TextXAlignment.Right
	readout.ClearTextOnFocus = false
	readout.Position = UDim2.fromScale(0.55, 0)
	readout.Size = UDim2.new(0.45, 0, 0, 14)
	readout.Parent = holder

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 0, 0, 24)
	track.Size = UDim2.new(1, 0, 0, 4)
	track.BorderSizePixel = 0
	track.Parent = holder
	corner(track, 2)

	-- Bigger than it looks. A 4px track is right visually and miserable
	-- to hit, so an invisible 18px band takes the clicks.
	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AnchorPoint = Vector2.new(0, 0.5)
	hit.Position = UDim2.fromScale(0, 0.5)
	hit.Size = UDim2.new(1, 0, 0, 18)
	hit.Parent = track

	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	corner(fill, 2)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	corner(knob, 6)

	local knobRing = Instance.new("UIStroke")
	knobRing.Thickness = 2
	knobRing.Transparency = 1
	knobRing.Parent = knob

	Theme.bind(holder, function()
		label.TextColor3 = Theme.color("DimmedText")
		readout.TextColor3 = Theme.color("MainText")
		track.BackgroundColor3 = Theme.color("Border")
		fill.BackgroundColor3 = Theme.ACCENT
		knob.BackgroundColor3 = Theme.ACCENT
		knobRing.Color = Theme.ACCENT
	end)

	hit.MouseEnter:Connect(function()
		knobRing.Transparency = 0.65
	end)
	hit.MouseLeave:Connect(function()
		knobRing.Transparency = 1
	end)

	local current = value

	local function round(v: number): number
		if step > 0 then
			return math.floor(v / step + 0.5) * step
		end
		return v
	end

	local function redraw()
		local span = max - min
		local alpha = if span > 0 then math.clamp((current - min) / span, 0, 1) else 0
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		-- Integers read as integers. "12.00 copies" looks like a bug.
		readout.Text = if step >= 1 then tostring(math.floor(current)) else ("%.2f"):format(current)
	end

	local function apply(v: number, notify: boolean)
		current = math.clamp(round(v), math.min(min, max), math.max(min, max))
		redraw()
		if notify then
			onChange(current)
		end
	end

	local function fromX(x: number)
		local left = track.AbsolutePosition.X
		local width = math.max(track.AbsoluteSize.X, 1)
		apply(min + (max - min) * math.clamp((x - left) / width, 0, 1), true)
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		fromX(input.Position.X)
		captureDrag(track, function(pos)
			fromX(pos.X)
		end)
	end)

	readout.FocusLost:Connect(function()
		local parsed = tonumber(readout.Text)
		if parsed then
			apply(parsed, true)
		else
			redraw()
		end
	end)

	redraw()

	return {
		get = function()
			return current
		end,
		set = function(v)
			apply(v, false)
		end,
	}
end

--=====================================================================
--  DIAL
--
--  An angle is a circle. Typing 137 into a box tells you nothing about
--  whether that closes the ring; a dial with the sweep lit up tells you
--  at a glance, which is the entire reason Archimedes' one is better
--  than a text field.
--=====================================================================

local TICKS = 48 -- one every 7.5 degrees

function Ui.dial(parent: Instance, text: string, value: number, max: number, onChange: (number) -> ()): Knob
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 138)
	holder.Parent = parent

	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 11
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = text
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.Parent = holder

	local face = Instance.new("Frame")
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.new(0.5, 0, 0, 20)
	face.Size = UDim2.fromOffset(112, 112)
	face.BackgroundTransparency = 1
	face.Active = true
	face.Parent = holder

	-- Ticks around the rim. Cheap, and they read as a filled arc without
	-- needing an image or a mesh. Longer marks every 90° so the quarters
	-- are findable without counting.
	local dots = {}
	for i = 1, TICKS do
		local angle = (i - 1) / TICKS * math.pi * 2 - math.pi / 2
		local major = (i - 1) % (TICKS / 4) == 0
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.44, 0.5 + math.sin(angle) * 0.44)
		dot.Size = UDim2.fromOffset(if major then 4 else 3, if major then 9 else 5)
		dot.Rotation = math.deg(angle) + 90
		dot.BorderSizePixel = 0
		dot.Parent = face
		corner(dot, 2)
		dots[i] = dot
	end

	local needle = Instance.new("Frame")
	needle.AnchorPoint = Vector2.new(0, 0.5)
	needle.Position = UDim2.fromScale(0.5, 0.5)
	needle.Size = UDim2.fromOffset(42, 2)
	needle.BorderSizePixel = 0
	needle.ZIndex = 3
	needle.Parent = face
	corner(needle, 1)

	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(60, 60)
	hub.BorderSizePixel = 0
	hub.ZIndex = 2
	hub.Parent = face
	corner(hub, 30)

	local readout = Instance.new("TextBox")
	readout.BackgroundTransparency = 1
	readout.AnchorPoint = Vector2.new(0.5, 0.5)
	readout.Position = UDim2.fromScale(0.5, 0.5)
	readout.Size = UDim2.fromOffset(56, 20)
	readout.Font = FONT_BOLD
	readout.TextSize = 15
	readout.ClearTextOnFocus = false
	readout.ZIndex = 4
	readout.Parent = face

	local current = value

	local function redraw()
		local lit = math.clamp(current / 360, 0, 1) * TICKS
		for i, dot in dots do
			dot.BackgroundColor3 = if i <= lit then Theme.ACCENT else Theme.color("Border")
		end
		-- Rotation is clockwise from 12 o'clock; the Frame's own zero
		-- points right, hence the -90.
		needle.Rotation = current - 90
		readout.Text = ("%d°"):format(math.floor(current + 0.5))
	end

	Theme.bind(holder, function()
		caption.TextColor3 = Theme.color("DimmedText")
		readout.TextColor3 = Theme.color("MainText")
		needle.BackgroundColor3 = Theme.ACCENT
		hub.BackgroundColor3 = Theme.color("MainBackground")
		redraw()
	end)

	local function apply(v: number, notify: boolean)
		current = math.clamp(v, 0, max)
		redraw()
		if notify then
			onChange(current)
		end
	end

	local function fromPoint(pos: Vector2)
		local centre = face.AbsolutePosition + face.AbsoluteSize / 2
		local d = pos - centre
		if d.Magnitude < 8 then
			return -- dead zone at the middle, where the angle is noise
		end
		local deg = math.deg(math.atan2(d.X, -d.Y))
		if deg < 0 then
			deg += 360
		end
		apply(deg, true)
	end

	face.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		fromPoint(Vector2.new(input.Position.X, input.Position.Y))
		captureDrag(face, fromPoint)
	end)

	readout.FocusLost:Connect(function()
		local parsed = tonumber((readout.Text:gsub("°", "")))
		if parsed then
			apply(parsed, true)
		else
			redraw()
		end
	end)

	redraw()

	return {
		get = function()
			return current
		end,
		set = function(v)
			apply(v, false)
		end,
	}
end

--=====================================================================
--  SEGMENTED CHOICE
--=====================================================================

-- One lit option out of a few, in a single inset track. Used for the
-- arc's axis, where three buttons say what a dropdown would hide.
function Ui.choice(
	parent: Instance,
	options: { string },
	current: string,
	onChange: (string) -> ()
): (Frame, (string) -> ())
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 26)
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 5)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 2)
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 2)
	pad.Parent = track

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = track

	local buttons: { [string]: TextButton } = {}
	local selected = current

	local function repaint()
		track.BackgroundColor3 = Theme.color("ScrollBarBackground")
		for name, button in buttons do
			local on = name == selected
			button.BackgroundTransparency = if on then 0 else 1
			button.BackgroundColor3 = Theme.ACCENT
			button.TextColor3 = if on then Color3.new(1, 1, 1) else Theme.color("DimmedText")
		end
	end

	for _, name in options do
		local button = Instance.new("TextButton")
		button.Font = FONT_MED
		button.TextSize = 12
		button.Text = name
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Size = UDim2.new(1 / #options, -2, 1, 0)
		button.Parent = track
		corner(button, 4)

		button.Activated:Connect(function()
			selected = name
			repaint()
			onChange(name)
		end)
		buttons[name] = button
	end

	Theme.bind(track, repaint)

	return track, function(name: string)
		selected = name
		repaint()
	end
end

function Ui.divider(parent: Instance)
	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundTransparency = 0.5
	line.BorderSizePixel = 0
	line.Parent = parent
	Theme.bind(line, function()
		line.BackgroundColor3 = Theme.color("Border")
	end)
end

return Ui
