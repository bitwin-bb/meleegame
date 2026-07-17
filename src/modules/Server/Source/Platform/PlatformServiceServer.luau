local require = require(script.Parent.loader).load(script)

local PlatformServiceServer = {}
PlatformServiceServer.ServiceName = "PlatformServiceServer"

function PlatformServiceServer.Init(self: typeof(PlatformServiceServer), _serviceBag: any?)
	self.isInitialized = true
end

function PlatformServiceServer.Destroy(self: typeof(PlatformServiceServer))
	self.isInitialized = false
end
return PlatformServiceServer
