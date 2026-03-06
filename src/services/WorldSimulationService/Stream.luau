--!strict

local Shared = require(script.Parent.Shared)

local Stream = {}

export type PlayerStreamState = {
	interestLookup: { [string]: number },
	sentRevisions: { [string]: number },
	queuedLookup: { [string]: number },
	queueKeys: { string },
}

export type ServerStreamState = {
	players: { [Player]: PlayerStreamState },
}

export type ClientStreamState = {
	loadedLookup: { [string]: boolean },
	pendingSnapshots: { [string]: { [string]: any } },
	pendingPriority: { [string]: number },
	pendingKeys: { string },
}

local function squaredDistance3(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local dx = ax - bx
	local dy = ay - by
	local dz = az - bz
	return dx * dx + dy * dy + dz * dz
end

function Stream.createPlayerStreamState(): PlayerStreamState
	return {
		interestLookup = {},
		sentRevisions = {},
		queuedLookup = {},
		queueKeys = {},
	}
end

function Stream.createServerStreamState(): ServerStreamState
	return {
		players = {},
	}
end

function Stream.getOrCreatePlayerStream(serverState: ServerStreamState, player: Player): PlayerStreamState
	local existing = serverState.players[player]
	if existing ~= nil then
		return existing
	end
	local created = Stream.createPlayerStreamState()
	serverState.players[player] = created
	return created
end

function Stream.removePlayerStream(serverState: ServerStreamState, player: Player)
	serverState.players[player] = nil
end

function Stream.computeChunkInterest(
	centerChunkX: number,
	centerChunkY: number,
	centerChunkZ: number,
	radius: number,
	verticalRadius: number
): { [string]: number }
	local result: { [string]: number } = {}
	local radiusSq = radius * radius

	for offsetY = -verticalRadius, verticalRadius do
		for offsetX = -radius, radius do
			for offsetZ = -radius, radius do
				local horizontalSq = offsetX * offsetX + offsetZ * offsetZ
				if horizontalSq > radiusSq then
					continue
				end
				local chunkX = centerChunkX + offsetX
				local chunkY = centerChunkY + offsetY
				local chunkZ = centerChunkZ + offsetZ
				local key = Shared.packChunkKey(chunkX, chunkY, chunkZ)
				result[key] = squaredDistance3(chunkX, chunkY, chunkZ, centerChunkX, centerChunkY, centerChunkZ)
			end
		end
	end

	return result
end

function Stream.enqueueChunk(stream: PlayerStreamState, chunkKey: string, priority: number)
	local previousPriority = stream.queuedLookup[chunkKey]
	if previousPriority ~= nil then
		if priority < previousPriority then
			stream.queuedLookup[chunkKey] = priority
		end
		return
	end
	stream.queuedLookup[chunkKey] = priority
	stream.queueKeys[#stream.queueKeys + 1] = chunkKey
end

function Stream.popNextChunk(stream: PlayerStreamState): (string?, number?)
	if #stream.queueKeys <= 0 then
		return nil, nil
	end

	local bestIndex = 1
	local bestKey = stream.queueKeys[1]
	local bestPriority = stream.queuedLookup[bestKey] or math.huge
	for index = 2, #stream.queueKeys do
		local key = stream.queueKeys[index]
		local priority = stream.queuedLookup[key] or math.huge
		if priority < bestPriority then
			bestPriority = priority
			bestKey = key
			bestIndex = index
		end
	end

	table.remove(stream.queueKeys, bestIndex)
	stream.queuedLookup[bestKey] = nil
	return bestKey, bestPriority
end

function Stream.reconcilePlayerInterest(
	stream: PlayerStreamState,
	nextInterest: { [string]: number },
	onAdded: ((chunkKey: string, priority: number) -> ())?,
	onRemoved: ((chunkKey: string) -> ())?
)
	for chunkKey, priority in nextInterest do
		local had = stream.interestLookup[chunkKey]
		stream.interestLookup[chunkKey] = priority
		if had == nil then
			if onAdded ~= nil then
				onAdded(chunkKey, priority)
			end
		elseif priority < had then
			Stream.enqueueChunk(stream, chunkKey, priority)
		end
	end

	local removedKeys = table.create(#stream.queueKeys)
	for chunkKey in stream.interestLookup do
		if nextInterest[chunkKey] == nil then
			removedKeys[#removedKeys + 1] = chunkKey
		end
	end

	for _, chunkKey in removedKeys do
		stream.interestLookup[chunkKey] = nil
		stream.sentRevisions[chunkKey] = nil
		stream.queuedLookup[chunkKey] = nil
		if onRemoved ~= nil then
			onRemoved(chunkKey)
		end
	end
end

function Stream.isRevisionOutOfDate(stream: PlayerStreamState, chunkKey: string, revision: number): boolean
	return (stream.sentRevisions[chunkKey] or -1) ~= revision
end

function Stream.markRevisionSent(stream: PlayerStreamState, chunkKey: string, revision: number)
	stream.sentRevisions[chunkKey] = revision
end

function Stream.createClientStreamState(): ClientStreamState
	return {
		loadedLookup = {},
		pendingSnapshots = {},
		pendingPriority = {},
		pendingKeys = {},
	}
end

function Stream.pushClientSnapshot(clientState: ClientStreamState, chunkSnapshot: { [string]: any }, priority: number)
	local chunkKey = chunkSnapshot.key
	if typeof(chunkKey) ~= "string" or chunkKey == "" then
		return
	end
	local had = clientState.pendingSnapshots[chunkKey] ~= nil
	clientState.pendingSnapshots[chunkKey] = chunkSnapshot
	clientState.pendingPriority[chunkKey] = priority
	if not had then
		clientState.pendingKeys[#clientState.pendingKeys + 1] = chunkKey
	end
end

function Stream.popClientSnapshot(clientState: ClientStreamState): { [string]: any }?
	if #clientState.pendingKeys <= 0 then
		return nil
	end

	local bestIndex = 1
	local bestKey = clientState.pendingKeys[1]
	local bestPriority = clientState.pendingPriority[bestKey] or math.huge
	for index = 2, #clientState.pendingKeys do
		local key = clientState.pendingKeys[index]
		local priority = clientState.pendingPriority[key] or math.huge
		if priority < bestPriority then
			bestPriority = priority
			bestKey = key
			bestIndex = index
		end
	end

	table.remove(clientState.pendingKeys, bestIndex)
	clientState.pendingPriority[bestKey] = nil
	local snapshot = clientState.pendingSnapshots[bestKey]
	clientState.pendingSnapshots[bestKey] = nil
	if snapshot == nil then
		return nil
	end

	clientState.loadedLookup[bestKey] = true
	return snapshot
end

function Stream.markClientChunkUnloaded(clientState: ClientStreamState, chunkKeyRaw: any)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end
	clientState.loadedLookup[chunkKeyRaw] = nil
	clientState.pendingPriority[chunkKeyRaw] = nil
	clientState.pendingSnapshots[chunkKeyRaw] = nil
end

return Stream