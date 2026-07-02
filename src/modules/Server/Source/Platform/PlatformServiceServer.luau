local require = require(script.Parent.loader).load(script)

local PlatformServiceServer = {}

function PlatformServiceServer.Init(self: typeof(PlatformServiceServer))
	self.isInitialized = true
end

function PlatformServiceServer.Destroy(self: typeof(PlatformServiceServer))
	self.isInitialized = false
end
return PlatformServiceServer
