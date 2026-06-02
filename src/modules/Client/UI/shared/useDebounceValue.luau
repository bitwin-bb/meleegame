--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local useDebounce = require(gameRoot.Client.UI.core.hooks.useDebounce)

export type DebounceValueOptions<T> = {
	leading: boolean?,
	equalityFn: ((T, T) -> boolean)?,
}

local function useDebounceValue<T>(value: T, delaySeconds: any, options: DebounceValueOptions<T>?): T
	return useDebounce(value, delaySeconds, options).value
end

return useDebounceValue
