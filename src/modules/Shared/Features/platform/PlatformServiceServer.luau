--!strict

local PlatformServiceServer = {}

function PlatformServiceServer.Init(self: typeof(PlatformServiceServer))
	self.isInitialized = true
end

function PlatformServiceServer.Destroy(self: typeof(PlatformServiceServer))
	self.isInitialized = false
end

PlatformServiceServer.init = PlatformServiceServer.Init
PlatformServiceServer.destroy = PlatformServiceServer.Destroy

return PlatformServiceServer
