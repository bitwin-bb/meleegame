--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Cleanup = require(script.Parent.internal.cleanup)
local React = require(ReplicatedStorage.Packages.React)
local useLatest = require(script.Parent.internal.useLatest)

export type StoreOptions<TSelected> = {
	equalityFn: ((TSelected?, TSelected?) -> boolean)?,
}

local function defaultEquality<TSelected>(a: TSelected?, b: TSelected?): boolean
	return a == b
end

local function readStoreState(sourceRaw: any): any
	if typeof(sourceRaw) == "function" then
		return sourceRaw()
	end

	if typeof(sourceRaw) ~= "table" then
		return nil
	end

	local getState = (sourceRaw :: any).getState
	if typeof(getState) ~= "function" then
		getState = (sourceRaw :: any).GetState
	end
	if typeof(getState) ~= "function" then
		return nil
	end

	local ok, result = pcall(function()
		return getState(sourceRaw)
	end)
	if ok then
		return result
	end

	local okWithoutSelf, resultWithoutSelf = pcall(function()
		return getState()
	end)
	if okWithoutSelf then
		return resultWithoutSelf
	end

	return nil
end

local function subscribeToStore(sourceRaw: any, callback: () -> ()): any
	if typeof(sourceRaw) == "function" then
		return Charm.subscribe(sourceRaw, callback, {
			inclusive = true,
		})
	end

	if typeof(sourceRaw) ~= "table" then
		return nil
	end

	local subscribe = (sourceRaw :: any).subscribe
	if typeof(subscribe) ~= "function" then
		subscribe = (sourceRaw :: any).Subscribe
	end
	if typeof(subscribe) ~= "function" then
		return nil
	end

	local ok, result = pcall(function()
		return subscribe(sourceRaw, callback)
	end)
	if ok then
		return result
	end

	local okWithoutSelf, resultWithoutSelf = pcall(function()
		return subscribe(callback)
	end)
	if okWithoutSelf then
		return resultWithoutSelf
	end

	return nil
end

local function useStore<TSelected>(sourceRaw: any, selectorRaw: any?, options: StoreOptions<TSelected>?): TSelected?
	local selector = if typeof(selectorRaw) == "function"
		then selectorRaw
		else function(state: any): any
			return state
		end
	local equalityFn = if options ~= nil and options.equalityFn ~= nil then options.equalityFn else defaultEquality
	local selectorRef = useLatest(selector)
	local equalityRef = useLatest(equalityFn)
	local initialValue = selector(readStoreState(sourceRaw))
	local valueRef = React.useRef(initialValue)
	local value, setValue = React.useState(initialValue)

	local applySelection = React.useCallback(function()
		local nextValue = selectorRef.current(readStoreState(sourceRaw))
		if equalityRef.current(valueRef.current, nextValue) then
			return
		end

		valueRef.current = nextValue
		setValue(nextValue)
	end, { sourceRaw, selectorRef, equalityRef })

	React.useEffect(function()
		applySelection()
		local unsubscribe = subscribeToStore(sourceRaw, applySelection)

		return function()
			Cleanup.Call(unsubscribe)
		end
	end, { sourceRaw, applySelection })

	return value
end

return useStore
