--!strict
--[=[
	@class AquariaBackupServiceClient
]=]

local AquariaBackupClientBootstrap = require(script.Parent.AquariaBackupClientBootstrap)

local AquariaBackupServiceClient = {}
AquariaBackupServiceClient.ServiceName = "AquariaBackupServiceClient"

export type AquariaBackupServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: any,
	},
	{} :: typeof({ __index = AquariaBackupServiceClient })
))

function AquariaBackupServiceClient.Init(self: AquariaBackupServiceClient, serviceBag: any): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
end

function AquariaBackupServiceClient.Start(self: AquariaBackupServiceClient): ()
	assert((self :: any)._serviceBag, "Not initialized")
	task.spawn(AquariaBackupClientBootstrap.start)
end

return AquariaBackupServiceClient
