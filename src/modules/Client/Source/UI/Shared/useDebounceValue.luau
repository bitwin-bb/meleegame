
local require = require(script.Parent.loader).load(script)

local useDebounce = require("useDebounce")

export type DebounceValueOptions<T> = {
	leading: boolean?,
	equalityFn: ((T, T) -> boolean)?,
}

local function useDebounceValue<T>(value: T, delaySeconds: any, options: DebounceValueOptions<T>?): T
	return useDebounce(value, delaySeconds, options).value
end

return useDebounceValue
