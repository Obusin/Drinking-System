--[[
	Store — settings that survive closing Studio.

	plugin:SetSetting writes per-plugin, per-machine, and it is the only
	persistence a plugin gets. Saved gradients live here, as do the last
	values you typed into every numeric field — because retyping "12" into
	the brush count on every launch is exactly the friction a tool is
	supposed to remove.

	VALUES MUST BE JSON-SAFE. Roblox serialises these, and a Color3 or an
	Instance silently becomes nothing. So anything structured is converted
	to plain numbers before it gets here — see Gradients, which stores
	sequences as arrays of {t, r, g, b}.
--]]

local Store = {}

local pluginRef: Plugin? = nil

function Store.init(p: Plugin)
	pluginRef = p
end

function Store.get(key: string, default: any): any
	if not pluginRef then
		return default
	end
	local ok, value = pcall(function()
		return pluginRef:GetSetting(key)
	end)
	if not ok or value == nil then
		return default
	end
	return value
end

function Store.set(key: string, value: any)
	if not pluginRef then
		return
	end
	pcall(function()
		pluginRef:SetSetting(key, value)
	end)
end

-- Reads a number once and writes it back on every change. The pattern
-- every numeric field in the plugin uses.
function Store.number(key: string, default: number): (number, (number) -> ())
	local current = Store.get(key, default)
	if type(current) ~= "number" then
		current = default
	end
	return current, function(v: number)
		Store.set(key, v)
	end
end

return Store
