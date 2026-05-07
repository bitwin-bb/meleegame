--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type ToggleSetter = boolean | ((boolean) -> boolean)

export type ToggleResult = {
	value: boolean,
	set: (nextValue: ToggleSetter) -> boolean,
	toggle: (nextValue: boolean?) -> boolean,
	enable: () -> boolean,
	disable: () -> boolean,
	reset: () -> boolean,
}

local function resolveToggleValue(current: boolean, nextValueRaw: ToggleSetter): boolean
	if typeof(nextValueRaw) == "function" then
		return ((nextValueRaw :: any)(current) == true)
	end
	return nextValueRaw == true
end

local function useToggle(initialValueRaw: any): ToggleResult
	local initialValue = initialValueRaw == true
	local valueRef = React.useRef(initialValue)
	local value, setValue = React.useState(initialValue)

	local set = React.useCallback(function(nextValueRaw: ToggleSetter): boolean
		local nextValue = resolveToggleValue(valueRef.current, nextValueRaw)
		valueRef.current = nextValue
		setValue(nextValue)
		return nextValue
	end, {})

	local toggle = React.useCallback(function(nextValueRaw: boolean?): boolean
		if nextValueRaw ~= nil then
			return set(nextValueRaw == true)
		end
		return set(function(current: boolean): boolean
			return not current
		end)
	end, { set })

	local enable = React.useCallback(function(): boolean
		return set(true)
	end, { set })

	local disable = React.useCallback(function(): boolean
		return set(false)
	end, { set })

	local reset = React.useCallback(function(): boolean
		return set(initialValue)
	end, { set, initialValue })

	return {
		value = value,
		set = set,
		toggle = toggle,
		enable = enable,
		disable = disable,
		reset = reset,
	}
end

return useToggle
