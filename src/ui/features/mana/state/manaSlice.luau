--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local ManaServiceUtils = require(ReplicatedStorage.Shared.Services.ManaService.ManaServiceUtils)

type ManaServiceState = ManaServiceUtils.ManaServiceState

local manaStateAtom: Charm.Atom<ManaServiceState> = Charm.atom(ManaServiceUtils.createDefaultState())
local manaReadyAtom: Charm.Atom<boolean> = Charm.atom(false)

local manaAtom: Charm.Selector<number> = Charm.computed(function(): number
	return manaStateAtom().mana
end)

local maxManaAtom: Charm.Selector<number> = Charm.computed(function(): number
	return manaStateAtom().maxMana
end)

local manaPercentAtom: Charm.Selector<number> = Charm.computed(function(): number
	local state = manaStateAtom()
	if state.maxMana <= 0 then
		return 0
	end
	return math.clamp(state.mana / state.maxMana, 0, 1)
end)

local function getManaState(): ManaServiceState
	return manaStateAtom()
end

local function setManaState(stateRaw: any): ManaServiceState
	local nextState = ManaServiceUtils.sanitizeState(stateRaw, manaStateAtom())
	manaStateAtom(nextState)
	return nextState
end

local function resetManaState(): ManaServiceState
	local nextState = ManaServiceUtils.createDefaultState()
	manaStateAtom(nextState)
	return nextState
end

local function isManaReady(): boolean
	return manaReadyAtom()
end

local function setManaReady(isReadyRaw: any): boolean
	local nextReady = isReadyRaw == true
	manaReadyAtom(nextReady)
	return nextReady
end

return {
	manaStateAtom = manaStateAtom,
	manaReadyAtom = manaReadyAtom,
	manaAtom = manaAtom,
	maxManaAtom = maxManaAtom,
	manaPercentAtom = manaPercentAtom,
	isManaReady = isManaReady,
	setManaReady = setManaReady,
	getManaState = getManaState,
	setManaState = setManaState,
	resetManaState = resetManaState,
}
