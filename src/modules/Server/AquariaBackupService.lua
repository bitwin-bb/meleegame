--!strict
--[=[
	@class AquariaBackupService
]=]

local AquariaBackupServerBootstrap = require(script.Parent.AquariaBackupServerBootstrap)

local AquariaBackupService = {}
AquariaBackupService.ServiceName = "AquariaBackupService"

export type AquariaBackupService =
	typeof(setmetatable(
		{} :: {
			_serviceBag: any,
		},
		{} :: typeof({ __index = AquariaBackupService })
	))

function AquariaBackupService.Init(self: AquariaBackupService, serviceBag: any): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
end

function AquariaBackupService.Start(self: AquariaBackupService): ()
	assert((self :: any)._serviceBag, "Not initialized")
	AquariaBackupServerBootstrap.start()
end

return AquariaBackupService
