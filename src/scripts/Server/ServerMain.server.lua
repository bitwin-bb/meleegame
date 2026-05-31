--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_TRACKER_IGNORED_MODULE_PATHS = {
	"game/Client/UI/core/hooks/useManaTransparency",
	"game/Client/UI/hud/state/slice/hpSlice",
	"game/Client/UI/hud/state/slice/manaSlice",
	"game/Client/UI/hud/state/thunk/hpThunks",
	"game/Client/UI/hud/state/thunk/manaThunks",
	"game/Client/UI/hud/TopBar/components/HeartMeter",
	"game/Client/UI/hud/TopBar/components/ManaMeter",
	"game/Client/UI/hud/TopBar/HpTopRightBar",
	"game/Client/UI/hud/TopBar/ManaTopRightBar",
	"game/Client/Binders/DisturberBinder",
	"game/Client/Binders/FoliageBinder",
	"game/Client/Binders/LayerBinder",
	"game/Client/Binders/LightBinder",
	"game/Client/Binders/LiquidBinder",
	"game/Client/Binders/PreviewBinder",
	"game/Server/Binders/BreakableBinder",
	"game/Server/Binders/DropBinder",
	"game/Server/Binders/GoreBinder",
	"game/Server/Binders/HazardBinder",
	"game/Server/Binders/HitboxBinder",
	"game/Server/Binders/LootBinder",
	"game/Server/Binders/MagicBinder",
	"game/Server/Binders/MeleeBinder",
	"game/Server/Binders/NpcBinder",
	"game/Server/Binders/PickupBinder",
	"game/Server/Binders/PlaceableBinder",
	"game/Server/Binders/RagdollBinder",
	"game/Server/Binders/StationBinder",
	"game/Shared/Classes/EnemyHitbox",
	"game/Shared/Classes/EnemyHitbox/Utils/SpatialHash",
	"game/Shared/Classes/Gore",
	"game/Shared/Classes/Gore/Gib",
	"game/Shared/Classes/Gore/LimbDestruction",
	"game/Shared/Classes/Magic",
	"game/Shared/Classes/Melee",
	"game/Shared/Classes/Npc",
	"game/Shared/Classes/WindFoliage",
	"game/Shared/Classes/WindFoliage/BufferPool",
	"game/Shared/Classes/WindFoliage/DisturbanceSource",
	"game/Shared/Classes/WindFoliage/FoliageInstance",
	"game/Shared/Classes/WindFoliage/FoliageUpdateManager",
	"game/Shared/Classes/WindFoliage/LODController",
	"game/Shared/Classes/WindFoliage/RippleMotion",
	"game/Shared/Classes/WindFoliage/TreeFoliageGraph",
	"game/Shared/Classes/WindFoliage/TreeRuntimeRegistry",
	"game/Shared/Classes/WindFoliage/WindField",
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
