--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local HpServiceUtils = require(ReplicatedStorage.Shared.Services.HpService.HpServiceUtils)

type HpServiceState = HpServiceUtils.HpServiceState
type HeartState = HpServiceUtils.HeartState

local hpStateAtom: Charm.Atom<HpServiceState> = Charm.atom(HpServiceUtils.createDefaultState())
local hpReadyAtom: Charm.Atom<boolean> = Charm.atom(false)

local heartsAtom: Charm.Selector<{ HeartState }> = Charm.computed(function(): { HeartState }
	return hpStateAtom().hearts
end)

local healthAtom: Charm.Selector<number> = Charm.computed(function(): number
	return hpStateAtom().health
end)

local maxHealthAtom: Charm.Selector<number> = Charm.computed(function(): number
	return hpStateAtom().maxHealth
end)

local heartCountAtom: Charm.Selector<number> = Charm.computed(function(): number
	return hpStateAtom().heartCount
end)

local beatHeartIndexAtom: Charm.Selector<number?> = Charm.computed(function(): number?
	local hearts = hpStateAtom().hearts
	for heartIndex = #hearts, 1, -1 do
		local heart = hearts[heartIndex]
		if heart.health > 0 then
			return heart.index
		end
	end

	return nil
end)

local healthPercentAtom: Charm.Selector<number> = Charm.computed(function(): number
	local state = hpStateAtom()
	if state.maxHealth <= 0 then
		return 0
	end
	return math.clamp(state.health / state.maxHealth, 0, 1)
end)

local function getHpState(): HpServiceState
	return hpStateAtom()
end

local function setHpState(stateRaw: any): HpServiceState
	local nextState = HpServiceUtils.sanitizeState(stateRaw, hpStateAtom())
	hpStateAtom(nextState)
	return nextState
end

local function resetHpState(): HpServiceState
	local nextState = HpServiceUtils.createDefaultState()
	hpStateAtom(nextState)
	return nextState
end

local function isHpReady(): boolean
	return hpReadyAtom()
end

local function setHpReady(isReadyRaw: any): boolean
	local nextReady = isReadyRaw == true
	hpReadyAtom(nextReady)
	return nextReady
end

return {
	hpStateAtom = hpStateAtom,
	hpReadyAtom = hpReadyAtom,
	heartsAtom = heartsAtom,
	healthAtom = healthAtom,
	maxHealthAtom = maxHealthAtom,
	heartCountAtom = heartCountAtom,
	beatHeartIndexAtom = beatHeartIndexAtom,
	healthPercentAtom = healthPercentAtom,
	isHpReady = isHpReady,
	setHpReady = setHpReady,
	getHpState = getHpState,
	setHpState = setHpState,
	resetHpState = resetHpState,
}
