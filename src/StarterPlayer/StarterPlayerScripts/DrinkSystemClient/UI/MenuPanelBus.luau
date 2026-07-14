local MenuPanelBus = {}

local stateChanged = Instance.new("BindableEvent")
stateChanged.Name = "MenuPanelStateChanged"

local open = false

function MenuPanelBus.IsOpen(): boolean
	return open
end

function MenuPanelBus.SetOpen(nextOpen: boolean)
	local normalized = nextOpen == true
	if open == normalized then
		return
	end

	open = normalized
	stateChanged:Fire(open)
end

function MenuPanelBus.Toggle()
	MenuPanelBus.SetOpen(not open)
end

function MenuPanelBus.Observe(callback: (boolean) -> ()): RBXScriptConnection
	callback(open)
	return stateChanged.Event:Connect(callback)
end

return MenuPanelBus
