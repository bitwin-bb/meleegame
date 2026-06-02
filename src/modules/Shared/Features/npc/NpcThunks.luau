--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local NpcServiceClient = require(gameRoot.Shared.Features.npc.NpcServiceClient)
local NpcSlice = require(gameRoot.Shared.Features.npc.NpcSlice)

type NpcViewState = NpcSlice.NpcViewState
type SlimeGoreSprite = NpcSlice.SlimeGoreSprite

local NpcThunks = {}

local runtime = {
	started = false,
	connection = nil :: any?,
}

local function syncFromService()
	NpcSlice.setFromServiceState(NpcServiceClient:getState())
end

function NpcThunks.StartClientSync(): () -> ()
	if runtime.started then
		syncFromService()
		return function() end
	end

	runtime.started = true
	syncFromService()
	runtime.connection = NpcServiceClient.stateChanged:Connect(function(nextState)
		NpcSlice.setFromServiceState(nextState)
	end)

	return function()
		if runtime.connection ~= nil then
			runtime.connection:Disconnect()
			runtime.connection = nil
		end
		runtime.started = false
	end
end

function NpcThunks.GetViewState(): NpcViewState
	return NpcSlice.getViewState()
end

function NpcThunks.SpawnSlimeDeathGore(snapshotRaw: any): { SlimeGoreSprite }
	return NpcSlice.spawnSlimeDeathGore(snapshotRaw)
end

function NpcThunks.PruneSlimeGore(nowRaw: any): number
	return NpcSlice.pruneSlimeGore(nowRaw)
end

NpcThunks.startClientSync = NpcThunks.StartClientSync
NpcThunks.getViewState = NpcThunks.GetViewState
NpcThunks.spawnSlimeDeathGore = NpcThunks.SpawnSlimeDeathGore
NpcThunks.pruneSlimeGore = NpcThunks.PruneSlimeGore

return NpcThunks
