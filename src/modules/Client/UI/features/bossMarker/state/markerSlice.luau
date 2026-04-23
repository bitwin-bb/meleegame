--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local Charm = require(ReplicatedStorage.Packages.Charm)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)

export type MarkerState = BossServiceUtils.BossServiceState
type BossSnapshot = BossServiceUtils.BossSnapshot

local markerStateAtom: Charm.Atom<MarkerState> = Charm.atom(BossServiceUtils.createDefaultState())
local markerReadyAtom: Charm.Atom<boolean> = Charm.atom(false)

local aliveBossesAtom: Charm.Selector<{ BossSnapshot }> = Charm.computed(function(): { BossSnapshot }
	local state = markerStateAtom()
	local aliveBosses = Sift.Array.create(#state.orderedIds)

	for _, runtimeId in state.orderedIds do
		local snapshot = state.byId[runtimeId]
		if snapshot ~= nil and snapshot.isAlive == true then
			aliveBosses = Sift.Array.append(aliveBosses, snapshot)
		end
	end

	return aliveBosses
end)

local activeBossCountAtom: Charm.Selector<number> = Charm.computed(function(): number
	return #aliveBossesAtom()
end)

local function getMarkerState(): MarkerState
	return markerStateAtom()
end

local function setMarkerState(stateRaw: any): MarkerState
	local nextState = BossServiceUtils.sanitizeState(stateRaw, markerStateAtom())
	markerStateAtom(nextState)
	return nextState
end

local function resetMarkerState(): MarkerState
	local nextState = BossServiceUtils.createDefaultState()
	markerStateAtom(nextState)
	return nextState
end

local function isMarkerReady(): boolean
	return markerReadyAtom()
end

local function setMarkerReady(isReadyRaw: any): boolean
	local nextReady = isReadyRaw == true
	markerReadyAtom(nextReady)
	return nextReady
end

return {
	markerStateAtom = markerStateAtom,
	markerReadyAtom = markerReadyAtom,
	aliveBossesAtom = aliveBossesAtom,
	activeBossCountAtom = activeBossCountAtom,
	getMarkerState = getMarkerState,
	setMarkerState = setMarkerState,
	resetMarkerState = resetMarkerState,
	isMarkerReady = isMarkerReady,
	setMarkerReady = setMarkerReady,
}
