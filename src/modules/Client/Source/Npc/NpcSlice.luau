local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm: any = require(ReplicatedStorage.Packages.Charm)
local NpcServiceUtils = require("NpcServiceUtils")
local SlimeSpriteSheet = require("SlimeSpriteSheet")
local SlimeTints = require("SlimeTints")

export type NpcSnapshot = NpcServiceUtils.NpcSnapshot

export type NpcViewState = {
	byId: { [string]: NpcSnapshot },
	orderedIds: { string },
	updatedAt: number,
}

export type SlimeGoreSprite = {
	id: string,
	position: Vector3,
	velocity: Vector3,
	createdAt: number,
	duration: number,
	scale: number,
	frameOffset: number,
	imageColor: Color3,
}

local DEFAULT_VIEW_STATE: NpcViewState = {
	byId = {},
	orderedIds = {},
	updatedAt = os.clock(),
}

local npcViewStateAtom: Charm.Atom<NpcViewState> = Charm.atom(DEFAULT_VIEW_STATE)
local slimeGoreSpritesAtom: Charm.Atom<{ [string]: SlimeGoreSprite }> = Charm.atom({})

local NpcSlice = {}

local function cloneSnapshot(snapshot: NpcSnapshot): NpcSnapshot
	return {
		id = snapshot.id,
		npcType = snapshot.npcType,
		displayName = snapshot.displayName,
		state = snapshot.state,
		biomeName = snapshot.biomeName,
		biomeReady = snapshot.biomeReady,
		hp = snapshot.hp,
		maxHp = snapshot.maxHp,
		isAlive = snapshot.isAlive,
		position = snapshot.position,
		updatedAt = snapshot.updatedAt,
		lastReason = snapshot.lastReason,
		spritePhase = snapshot.spritePhase,
		spriteFrame = snapshot.spriteFrame,
		spriteFrameRate = snapshot.spriteFrameRate,
		spritePhaseElapsed = snapshot.spritePhaseElapsed,
		spritePhaseDuration = snapshot.spritePhaseDuration,
		spriteFacingSign = snapshot.spriteFacingSign,
		spriteReceivedAt = snapshot.spriteReceivedAt,
	}
end

local function cloneState(state: NpcViewState): NpcViewState
	local byId: { [string]: NpcSnapshot } = {}
	for runtimeId, snapshot in state.byId do
		byId[runtimeId] = cloneSnapshot(snapshot)
	end

	local orderedIds: { string } = table.create(#state.orderedIds)
	for index, runtimeId in state.orderedIds do
		orderedIds[index] = runtimeId
	end

	return {
		byId = byId,
		orderedIds = orderedIds,
		updatedAt = state.updatedAt,
	}
end

local function appendUnique(orderedIds: { string }, runtimeId: string): { string }
	for _, existingId in orderedIds do
		if existingId == runtimeId then
			return orderedIds
		end
	end

	local nextIds = table.create(#orderedIds + 1)
	for index, existingId in orderedIds do
		nextIds[index] = existingId
	end
	nextIds[#nextIds + 1] = runtimeId
	return nextIds
end

local function cloneGoreSprite(sprite: SlimeGoreSprite): SlimeGoreSprite
	return {
		id = sprite.id,
		position = sprite.position,
		velocity = sprite.velocity,
		createdAt = sprite.createdAt,
		duration = sprite.duration,
		scale = sprite.scale,
		frameOffset = sprite.frameOffset,
		imageColor = sprite.imageColor,
	}
end

local function cloneGoreSprites(source: { [string]: SlimeGoreSprite }): { [string]: SlimeGoreSprite }
	local output = {}
	for id, sprite in source do
		output[id] = cloneGoreSprite(sprite)
	end
	return output
end

function NpcSlice.GetViewState(): NpcViewState
	return cloneState(npcViewStateAtom())
end

function NpcSlice.SetFromServiceState(stateRaw: any): NpcViewState
	local byId: { [string]: NpcSnapshot } = {}
	local orderedIds: { string } = {}

	if typeof(stateRaw) == "table" then
		local sourceById = (stateRaw :: any).byId
		local sourceOrderedIds = (stateRaw :: any).orderedIds
		if typeof(sourceById) == "table" and typeof(sourceOrderedIds) == "table" then
			for _, runtimeId in sourceOrderedIds do
				if typeof(runtimeId) ~= "string" then
					continue
				end
				local snapshot = NpcServiceUtils.CoerceSnapshot(sourceById[runtimeId], nil)
				if snapshot ~= nil and snapshot.npcType == "Slime" then
					snapshot.spriteReceivedAt = os.clock()
					byId[snapshot.id] = snapshot
					orderedIds = appendUnique(orderedIds, snapshot.id)
				end
			end
		end
		if typeof(sourceById) == "table" then
			for _, snapshotRaw in sourceById do
				local snapshot = NpcServiceUtils.CoerceSnapshot(snapshotRaw, nil)
				if snapshot ~= nil and snapshot.npcType == "Slime" and byId[snapshot.id] == nil then
					snapshot.spriteReceivedAt = os.clock()
					byId[snapshot.id] = snapshot
					orderedIds = appendUnique(orderedIds, snapshot.id)
				end
			end
		end
	end

	local nextState = {
		byId = byId,
		orderedIds = orderedIds,
		updatedAt = os.clock(),
	}
	npcViewStateAtom(nextState)
	return cloneState(nextState)
end

function NpcSlice.UpsertSnapshot(snapshotRaw: any): NpcSnapshot?
	local snapshot = NpcServiceUtils.CoerceSnapshot(snapshotRaw, nil)
	if snapshot == nil or snapshot.npcType ~= "Slime" then
		return nil
	end
	snapshot.spriteReceivedAt = os.clock()

	local current = npcViewStateAtom()
	local byId: { [string]: NpcSnapshot } = {}
	for runtimeId, existingSnapshot in current.byId do
		byId[runtimeId] = cloneSnapshot(existingSnapshot)
	end
	byId[snapshot.id] = snapshot

	npcViewStateAtom({
		byId = byId,
		orderedIds = appendUnique(current.orderedIds, snapshot.id),
		updatedAt = os.clock(),
	})

	return cloneSnapshot(snapshot)
end

function NpcSlice.RemoveSnapshot(runtimeIdRaw: any): boolean
	if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
		return false
	end

	local current = npcViewStateAtom()
	if current.byId[runtimeIdRaw] == nil then
		return false
	end

	local byId: { [string]: NpcSnapshot } = {}
	for runtimeId, snapshot in current.byId do
		if runtimeId ~= runtimeIdRaw then
			byId[runtimeId] = cloneSnapshot(snapshot)
		end
	end

	local orderedIds: { string } = {}
	for _, runtimeId in current.orderedIds do
		if runtimeId ~= runtimeIdRaw then
			orderedIds[#orderedIds + 1] = runtimeId
		end
	end

	npcViewStateAtom({
		byId = byId,
		orderedIds = orderedIds,
		updatedAt = os.clock(),
	})
	return true
end

function NpcSlice.SpawnSlimeDeathGore(snapshotRaw: any): { SlimeGoreSprite }
	local snapshot = NpcServiceUtils.CoerceSnapshot(snapshotRaw, nil)
	if snapshot == nil or snapshot.position == nil then
		return {}
	end

	local now = os.clock()
	local output: { SlimeGoreSprite } = {}
	local current = cloneGoreSprites(slimeGoreSpritesAtom())
	local goreAnimation = SlimeSpriteSheet.animations.Gore
	local frameCount = #goreAnimation.frames

	for index = 1, frameCount do
		local angle = (index / frameCount) * math.pi * 2
		local sprite: SlimeGoreSprite = {
			id = `{snapshot.id}:gore:{index}:{math.floor(now * 1000)}`,
			position = snapshot.position + Vector3.new(0, 0.45, 0),
			velocity = Vector3.new(math.cos(angle) * 1.7, 2.4 + index * 0.18, math.sin(angle) * 1.7),
			createdAt = now,
			duration = 0.85,
			scale = 0.55 + index * 0.08,
			frameOffset = index - 1,
			imageColor = SlimeTints.Gore,
		}
		current[sprite.id] = sprite
		output[index] = cloneGoreSprite(sprite)
	end

	slimeGoreSpritesAtom(current)
	return output
end

function NpcSlice.PruneSlimeGore(nowRaw: any): number
	local now = if typeof(nowRaw) == "number" and nowRaw == nowRaw then nowRaw else os.clock()
	local current = slimeGoreSpritesAtom()
	local nextSprites: { [string]: SlimeGoreSprite } = {}
	local removed = 0

	for id, sprite in current do
		if now - sprite.createdAt <= sprite.duration then
			nextSprites[id] = cloneGoreSprite(sprite)
		else
			removed += 1
		end
	end

	if removed > 0 then
		slimeGoreSpritesAtom(nextSprites)
	end
	return removed
end

NpcSlice.npcViewStateAtom = npcViewStateAtom
NpcSlice.slimeGoreSpritesAtom = slimeGoreSpritesAtom
return NpcSlice
