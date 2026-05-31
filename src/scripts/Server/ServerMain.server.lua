--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_TRACKER_IGNORED_MODULE_PATHS = {
	"game/Shared/Features/npc/npc/EyeOfCthulhu",
	"game/Shared/Features/npc/npc/QueenBee",
}

local REQUIRED_ARCHIVABLE_MODULE_PATHS = {
	"game/Shared/Features/npc/ui/components/EyeOfCthulhu",
	"game/Shared/Features/npc/ui/components/QueenBee",
	"game/Shared/Features/npc/ui/components/Slime",
}

local PACKAGE_TRACKER_IGNORE_TIMEOUT_SECONDS = 5

local function waitForDescendantByPath(root: Instance, path: string, timeoutSeconds: number): Instance?
	local deadline = os.clock() + timeoutSeconds
	local current = root

	for segment in string.gmatch(path, "[^/]+") do
		local child = current:FindFirstChild(segment)
		while child == nil and os.clock() < deadline do
			child = current:WaitForChild(segment, math.min(0.25, math.max(0, deadline - os.clock())))
		end
		if child == nil then
			return nil
		end

		current = child
	end

	return current
end

local function disableDuplicatePackageTrackerModules(packageRoot: Instance)
	local deadline = os.clock() + PACKAGE_TRACKER_IGNORE_TIMEOUT_SECONDS

	for _, path in REQUIRED_ARCHIVABLE_MODULE_PATHS do
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			return
		end

		local moduleScript = waitForDescendantByPath(packageRoot, path, remaining)
		if moduleScript ~= nil and moduleScript:IsA("ModuleScript") then
			moduleScript.Archivable = true
		end
	end

	for _, path in PACKAGE_TRACKER_IGNORED_MODULE_PATHS do
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			return
		end

		local moduleScript = waitForDescendantByPath(packageRoot, path, remaining)
		if moduleScript ~= nil and moduleScript:IsA("ModuleScript") then
			moduleScript.Archivable = false
		end
	end
end

local packageRoot = ServerScriptService:WaitForChild("AquariaBackup")
local loader = assert(ServerScriptService:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils").Parent
disableDuplicatePackageTrackerModules(packageRoot)
local loaderRequire = require(loader).bootstrapGame(packageRoot)

local ServiceBag = loaderRequire("ServiceBag")
local NevermoreSupport = loaderRequire("NevermoreSupport")
local CmdrBootstrapServer = loaderRequire("CmdrBootstrapServer")

local serviceBag = ServiceBag.new()

NevermoreSupport.setServiceBag(serviceBag)

serviceBag:GetService(loaderRequire("AquariaBackupService"))

serviceBag:Init()
serviceBag:Start()

CmdrBootstrapServer.start(serviceBag)
