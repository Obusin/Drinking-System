--[[
	Widget — the dockable panel, its tabs, and the lifecycle tools hang off.

	One window with three tabs rather than three toolbar buttons, because
	the alternative is what the plugin bar looks like once you have F3X,
	Archimedes, GapFill, Brushtool and AutoScale installed: a row of icons
	where you have stopped reading the tooltips.

	TABS ARE BUILT ONCE AND HIDDEN, not rebuilt on switch. A tool holds
	live state — the brush's template, the arc's radius — and rebuilding
	its panel would throw that away every time you looked at something
	else.

	WHICH IS EXACTLY WHY TOOLS NEED TO BE TOLD WHEN THEY GO AWAY.
	-------------------------------------------------------------
	A hidden panel is still running. Arc rebuilt its ghost on every
	selection change whether you could see the panel or not, so closing
	the window left a translucent arc floating in the viewport that
	nothing would ever clear — and it followed your selection around,
	which made it look like a bug in the place rather than in the plugin.

	So a tab hands its tool a context: `visible()` to check before doing
	anything the user can see, and `onHide` for the work of putting things
	back. Both fire for BOTH reasons a panel can go away — switching tab
	and closing the window — because a tool should not have to know the
	difference, and the one it forgets is the one that leaks.

	THE STATUS BAR IS PER-TAB. Each tab remembers its own last message
	and the bar shows the active one. A background tab reacting to a
	selection change cannot overwrite what the tab you are looking at
	just told you.
--]]

local Selection = game:GetService("Selection")

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local Widget = {}
Widget.__index = Widget

local HEADER = 34
local TABS = 30
local STATUS = 26

export type Ctx = {
	visible: () -> boolean,
	onShow: (() -> ()) -> (),
	onHide: (() -> ()) -> (),
	status: (string, string?) -> (),
}

function Widget.new(plugin: Plugin, id: string, title: string)
	local self = setmetatable({ tabs = {}, order = {}, active = nil }, Widget)

	local info = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Left,
		false, -- starts closed; the toolbar button opens it
		false, -- and does not override a previously saved state
		320,
		600,
		280,
		420
	)

	local gui = plugin:CreateDockWidgetPluginGui(id, info)
	gui.Title = title
	gui.Name = id
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.gui = gui

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BorderSizePixel = 0
	root.Parent = gui

	--== HEADER ========================================================
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, HEADER)
	header.BackgroundTransparency = 1
	header.Parent = root

	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0, 0.5)
	mark.Position = UDim2.new(0, 12, 0.5, 0)
	mark.Size = UDim2.fromOffset(3, 14)
	mark.BorderSizePixel = 0
	mark.Parent = header

	local wordmark = Instance.new("TextLabel")
	wordmark.BackgroundTransparency = 1
	wordmark.Font = Enum.Font.GothamBold
	wordmark.TextSize = 12
	wordmark.TextXAlignment = Enum.TextXAlignment.Left
	wordmark.Text = "OBU TOOLS"
	wordmark.Position = UDim2.fromOffset(22, 0)
	wordmark.Size = UDim2.new(1, -30, 1, 0)
	wordmark.Parent = header

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Text = ""
	hint.Position = UDim2.new(0, 0, 0, 0)
	hint.Size = UDim2.new(1, -12, 1, 0)
	hint.Parent = header
	self.hint = hint

	-- WHAT IS SELECTED, ALWAYS ON SCREEN. Every tool in here reads the
	-- selection, and "nothing happened" is nearly always "nothing was
	-- selected". Better answered before you press the button than after.
	local function countSelection()
		local n = #Selection:Get()
		hint.Text = if n == 0 then "nothing selected" elseif n == 1 then "1 selected" else ("%d selected"):format(n)
	end
	Selection.SelectionChanged:Connect(countSelection)
	countSelection()

	--== TAB BAR =======================================================
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(0, HEADER)
	bar.Size = UDim2.new(1, 0, 0, TABS)
	bar.BackgroundTransparency = 1
	bar.Parent = root

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = bar
	self.bar = bar

	local rule = Instance.new("Frame")
	rule.Position = UDim2.fromOffset(0, HEADER + TABS - 1)
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.BorderSizePixel = 0
	rule.BackgroundTransparency = 0.6
	rule.Parent = root

	--== BODY ==========================================================
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, HEADER + TABS)
	body.Size = UDim2.new(1, 0, 1, -(HEADER + TABS + STATUS))
	body.Parent = root
	self.body = body

	--== STATUS BAR ====================================================
	local status = Instance.new("Frame")
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.fromScale(0, 1)
	status.Size = UDim2.new(1, 0, 0, STATUS)
	status.BorderSizePixel = 0
	status.Parent = root

	local statusRule = Instance.new("Frame")
	statusRule.Size = UDim2.new(1, 0, 0, 1)
	statusRule.BorderSizePixel = 0
	statusRule.BackgroundTransparency = 0.6
	statusRule.Parent = status

	local pip = Instance.new("Frame")
	pip.AnchorPoint = Vector2.new(0, 0.5)
	pip.Position = UDim2.new(0, 12, 0.5, 0)
	pip.Size = UDim2.fromOffset(6, 6)
	pip.BorderSizePixel = 0
	pip.Parent = status
	local pipCorner = Instance.new("UICorner")
	pipCorner.CornerRadius = UDim.new(1, 0)
	pipCorner.Parent = pip

	local statusText = Instance.new("TextLabel")
	statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.Gotham
	statusText.TextSize = 11
	statusText.TextXAlignment = Enum.TextXAlignment.Left
	statusText.TextTruncate = Enum.TextTruncate.AtEnd
	statusText.Text = "Ready."
	statusText.Position = UDim2.fromOffset(26, 0)
	statusText.Size = UDim2.new(1, -34, 1, 0)
	statusText.Parent = status
	self.statusText = statusText
	self.statusPip = pip

	Theme.bind(root, function()
		root.BackgroundColor3 = Theme.color("MainBackground")
		wordmark.TextColor3 = Theme.color("MainText")
		hint.TextColor3 = Theme.color("DimmedText")
		mark.BackgroundColor3 = Theme.ACCENT
		rule.BackgroundColor3 = Theme.color("Border")
		statusRule.BackgroundColor3 = Theme.color("Border")
		status.BackgroundColor3 = Theme.color("Titlebar")
		statusText.TextColor3 = Theme.color("DimmedText")
	end)

	-- CLOSING THE WINDOW IS ONE OF THE TWO WAYS A PANEL GOES AWAY, and
	-- the one that used to be missed entirely.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not gui.Enabled then
			for _, name in self.order do
				self:_hide(name)
			end
		elseif self.active then
			self:_show(self.active)
			self:_paintTabs()
		end
	end)

	return self
end

function Widget:_paintTabs()
	for name, tab in self.tabs do
		local on = self.active == name and self.gui.Enabled
		tab.label.TextColor3 = if on then Theme.color("MainText") else Theme.color("DimmedText")
		tab.label.Font = if on then Enum.Font.GothamBold else Enum.Font.Gotham
		tab.underline.BackgroundColor3 = Theme.ACCENT
		tab.underline.Visible = on
	end
end

function Widget:_hide(name: string)
	local tab = self.tabs[name]
	if not tab or not tab.shown then
		return
	end
	tab.shown = false
	for _, fn in tab.hideHooks do
		task.spawn(fn)
	end
end

-- The mirror of _hide, and it exists for the same reason: a tool that
-- ignores changes while hidden — which it should — is stale the moment
-- it comes back, and something has to say so.
function Widget:_show(name: string)
	local tab = self.tabs[name]
	if not tab or tab.shown or not self.gui.Enabled then
		return
	end
	tab.shown = true
	for _, fn in tab.showHooks do
		task.spawn(fn)
	end
end

function Widget:_setStatus(text: string, kind: string?)
	self.statusText.Text = text
	local colour = if kind == "ok"
		then Theme.OK
		elseif kind == "warn" then Theme.WARN
		else Theme.color("DimmedText")
	self.statusPip.BackgroundColor3 = colour
	self.statusText.TextColor3 = if kind then Theme.color("MainText") else Theme.color("DimmedText")
end

-- Returns the container a tool builds into, and its lifecycle context.
function Widget:addTab(name: string): (Frame, Ctx)
	local page = Instance.new("ScrollingFrame")
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Size = UDim2.fromScale(1, 1)
	page.Visible = false
	page.ScrollBarThickness = 4
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.Parent = self.body

	Theme.bind(page, function()
		page.ScrollBarImageColor3 = Theme.color("DimmedText")
	end)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = page

	local content = Ui.list(page, 8)

	--== TAB BUTTON ====================================================
	local button = Instance.new("TextButton")
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Size = UDim2.fromScale(0, 1)
	button.Parent = self.bar

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.Text = name
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = button

	-- An underline rather than a filled block. A filled tab competes with
	-- the primary button for "the loud thing on screen", and there should
	-- only ever be one of those.
	local underline = Instance.new("Frame")
	underline.AnchorPoint = Vector2.new(0.5, 1)
	underline.Position = UDim2.fromScale(0.5, 1)
	underline.Size = UDim2.new(1, -16, 0, 2)
	underline.BorderSizePixel = 0
	underline.Visible = false
	underline.Parent = button

	local record = {
		page = page,
		button = button,
		label = label,
		underline = underline,
		hideHooks = {} :: { () -> () },
		showHooks = {} :: { () -> () },
		shown = false,
		message = "Ready.",
		kind = nil :: string?,
	}
	self.tabs[name] = record
	table.insert(self.order, name)

	for _, tabName in self.order do
		self.tabs[tabName].button.Size = UDim2.fromScale(1 / #self.order, 1)
	end

	Theme.bind(button, function()
		self:_paintTabs()
	end)

	button.Activated:Connect(function()
		self:show(name)
	end)

	if not self.active then
		self:show(name)
	end

	local ctx: Ctx = {
		visible = function(): boolean
			return self.gui.Enabled and page.Visible
		end,
		onShow = function(fn: () -> ())
			table.insert(record.showHooks, fn)
		end,
		onHide = function(fn: () -> ())
			table.insert(record.hideHooks, fn)
		end,
		status = function(text: string, kind: string?)
			record.message = text
			record.kind = kind
			if self.active == name then
				self:_setStatus(text, kind)
			end
		end,
	}

	return content, ctx
end

function Widget:show(name: string)
	local previous = self.active
	if previous == name and self.tabs[name] and self.tabs[name].shown then
		return
	end

	self.active = name
	for tabName, tab in self.tabs do
		tab.page.Visible = tabName == name
	end
	self:_show(name)
	-- SWITCHING AWAY IS THE OTHER WAY A PANEL GOES AWAY. Fired after the
	-- new tab is up, so a tool clearing its ghost cannot wipe one the
	-- incoming tool just drew.
	if previous and previous ~= name then
		self:_hide(previous)
	end

	self:_paintTabs()

	local record = self.tabs[name]
	if record then
		self:_setStatus(record.message, record.kind)
	end
end

function Widget:toggle()
	-- The Enabled listener does the rest; toggling is just the flag.
	self.gui.Enabled = not self.gui.Enabled
end

return Widget
