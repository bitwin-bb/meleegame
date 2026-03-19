--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local BreathServiceUtils = require(ReplicatedStorage.Shared.Services.BreathService.BreathServiceUtils)

type BreathServiceState = BreathServiceUtils.BreathServiceState

local breathStateAtom: Charm.Atom<BreathServiceState> = Charm.atom(BreathServiceUtils.createDefaultState())
local breathReadyAtom: Charm.Atom<boolean> = Charm.atom(false)

local breathAtom: Charm.Selector<number> = Charm.computed(function(): number
	return breathStateAtom().breath
end)

local maxBreathAtom: Charm.Selector<number> = Charm.computed(function(): number
	return breathStateAtom().maxBreath
end)

local underwaterAtom: Charm.Selector<boolean> = Charm.computed(function(): boolean
	local state = breathStateAtom()
	return state.isUnderwater or state.isBreathingBlocked or state.isDrowning
end)

local breathPercentAtom: Charm.Selector<number> = Charm.computed(function(): number
	local state = breathStateAtom()
	if state.maxBreath <= 0 then
		return 0
	end
	return math.clamp(state.breath / state.maxBreath, 0, 1)
end)

local function getBreathState(): BreathServiceState
	return breathStateAtom()
end

local function setBreathState(stateRaw: any): BreathServiceState
	local nextState = BreathServiceUtils.createState(stateRaw, breathStateAtom())
	breathStateAtom(nextState)
	return nextState
end

local function resetBreathState(): BreathServiceState
	local nextState = BreathServiceUtils.createDefaultState()
	breathStateAtom(nextState)
	return nextState
end

local function isBreathReady(): boolean
	return breathReadyAtom()
end

local function setBreathReady(isReadyRaw: any): boolean
	local nextReady = isReadyRaw == true
	breathReadyAtom(nextReady)
	return nextReady
end

return {
	breathStateAtom = breathStateAtom,
	breathReadyAtom = breathReadyAtom,
	breathAtom = breathAtom,
	maxBreathAtom = maxBreathAtom,
	underwaterAtom = underwaterAtom,
	breathPercentAtom = breathPercentAtom,
	getBreathState = getBreathState,
	setBreathState = setBreathState,
	resetBreathState = resetBreathState,
	isBreathReady = isBreathReady,
	setBreathReady = setBreathReady,
}
