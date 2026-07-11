local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

local ChunkVisibilityServiceClient = {}
ChunkVisibilityServiceClient.ServiceName = "ChunkVisibilityServiceClient"

function ChunkVisibilityServiceClient.Init(self: any)
	if self._maid ~= nil then
		return
	end

	self._maid = Maid.new()
	self._hiddenChunks = {}
end

function ChunkVisibilityServiceClient.SetChunkVisible(self: any, chunkKey: string, visible: boolean)
	if self._maid == nil then
		self:Init()
	end

	if visible then
		self._hiddenChunks[chunkKey] = nil
	else
		self._hiddenChunks[chunkKey] = true
	end
end

function ChunkVisibilityServiceClient.IsChunkVisible(self: any, chunkKey: string): boolean
	if self._hiddenChunks == nil then
		return true
	end
	return self._hiddenChunks[chunkKey] ~= true
end

function ChunkVisibilityServiceClient.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	if self._hiddenChunks ~= nil then
		table.clear(self._hiddenChunks)
	end
end

return ChunkVisibilityServiceClient
