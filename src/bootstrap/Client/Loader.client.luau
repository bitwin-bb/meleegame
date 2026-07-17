--!strict

local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PACKAGE_NAME = "AquariaBackup"
local BRIDGE_NAME = "AquariaLoaderBridge"
local STATE_CHANGED_NAME = "StateChanged"
local GET_SNAPSHOT_NAME = "GetSnapshot"
local CLIENT_SCRIPT_FOLDER_NAME = "AquariaBackupScripts"
local CLIENT_BOOT_SCRIPT_NAME = "ClientMain"
local BYTE_NET_RELIABLE_REMOTE_NAME = "ByteNetReliable"
local BYTE_NET_UNRELIABLE_REMOTE_NAME = "ByteNetUnreliable"
local BYTE_NET_STORAGE_NAME = "BytenetStorage"
local PART_CACHE_FOLDER_NAME = "Part Cache"
local WORKSPACE_GAME_FOLDER_NAME = "Game"
local WORLD_GENERATION_FOLDER_NAME = "WorldGeneration"
local COLLISION_CHUNKS_FOLDER_NAME = "CollisionChunks"

local REPLICATION_TIMEOUT_SECONDS = 60
local NETWORK_TIMEOUT_SECONDS = 30
local CLIENT_SCRIPT_TIMEOUT_SECONDS = 15
local ITEM_REGISTRY_WARMUP_TIMEOUT_SECONDS = 5
local WORLD_CHUNK_PRELOAD_TIMEOUT_SECONDS = 8
local WORLD_CHUNK_PRELOAD_MIN_READY_CHUNKS = 5
local ITEM_REGISTRY_STABLE_PASSES_REQUIRED = 2
local MODULE_REQUIRE_BATCH_SIZE = 12
local ASSET_PRELOAD_BATCH_SIZE = 40
local ASSET_PROGRESS_INTERVAL = 5
local BLOOD_ENGINE_PACKAGE_NAME = "BloodEngine"
local SOURCE_FOLDER_NAME = "Source"
local VENDOR_FOLDER_NAME = "Vendor"

local STAGE_WEIGHT_REPLICATION = 10
local STAGE_WEIGHT_FRAMEWORK = 12
local STAGE_WEIGHT_NETWORK = 10
local STAGE_WEIGHT_PACKAGES = 10
local STAGE_WEIGHT_MODULES = 20
local STAGE_WEIGHT_DATA = 12
local STAGE_WEIGHT_ASSETS = 14
local STAGE_WEIGHT_CHUNKS = 8
local STAGE_WEIGHT_SCRIPTS = 4
local TOTAL_STAGE_WEIGHT = 100
local CRITICAL_MODULE_PROGRESS_SHARE = 0.25

local BYTE_NET_NAMESPACE_NAMES = {
	"AnimationService",
	"AudioService",
	"BossService",
	"BreathService",
	"BuildService",
	"CameraService",
	"CraftingService",
	"GoreService",
	"HpService",
	"InventoryService",
	"LiquidService",
	"LootService",
	"MagicService",
	"ManaService",
	"MeleeService",
	"NpcService",
	"PlayerDataService",
	"PlayerService",
	"RagdollService",
	"VFXService",
	"WeatherService",
	"WorldGenerationService",
	"WorldSimulationService",
}

local RUNTIME_WALLY_PACKAGES = {
	"ByteNet",
	"React",
	"ReactRoblox",
	"ReactCharm",
	"ReactRodux",
	"Charm",
	"Signal",
	"Sift",
	"Ripple",
	"Janitor",
	"Matter",
	"Plasma",
}

local RUNTIME_VENDOR_PACKAGES = {
	"FastCast",
	"PartCache",
	"RaycastHitbox",
	"BloodEngine",
	"EZCameraShake",
}

local CONTENT_PROPERTIES_BY_CLASS: { [string]: { string } } = {
	Animation = { "AnimationId" },
	Beam = { "Texture" },
	Decal = { "Texture" },
	ImageButton = { "Image", "HoverImage", "PressedImage" },
	ImageLabel = { "Image" },
	MeshPart = { "MeshId", "TextureID" },
	ParticleEmitter = { "Texture" },
	Sky = {
		"SkyboxBk",
		"SkyboxDn",
		"SkyboxFt",
		"SkyboxLf",
		"SkyboxRt",
		"SkyboxUp",
		"MoonTextureId",
		"SunTextureId",
	},
	Sound = { "SoundId" },
	SpecialMesh = { "MeshId", "TextureId" },
	Trail = { "Texture" },
	VideoFrame = { "Video" },
}

local SKIPPED_MODULE_NAMES = {}

local SERVER_ONLY_MODULE_NAME_SUFFIXES = {
	"ServiceServer",
	"Server",
}

local SKIPPED_MODULE_PATHS = {
	["Client/App/RootUI"] = true,
	["App/RootUI"] = true,
	["Npc/BossServiceServer"] = true,
	["Npc/Components/QueenBeeRoot"] = true,
	["Npc/Modules/QueenBeeSpriteSheet"] = true,
	["Npc/UI/NpcRoot"] = true,
	["Npc/NpcServiceServer"] = true,
	["Npc/Npc/QueenBee"] = true,
	["Npc/UI/Components/QueenBee"] = true,
	["Npc/UI/Screens/QueenBeeScreen"] = true,
}

type LoaderSnapshot = {
	status: string,
	stage: string,
	message: string,
	progress: number,
	completed: number,
	total: number,
	startedAt: number,
	finishedAt: number?,
	moduleCount: number,
	assetCount: number,
	assetLoadedCount: number,
	assetFailedCount: number,
	failureCount: number,
	lastError: string?,
	failures: { string },
}

type LoaderBridge = {
	folder: Folder,
	changed: BindableEvent,
	getSnapshot: BindableFunction,
}

type ReplicatedContext = {
	packageRoot: Instance,
	gameRoot: Instance,
	clientRoot: Instance,
	sharedRoot: Instance,
	packagesRoot: Instance,
	vendorRoot: Instance,
}

local failures: { string } = {}
local snapshot: LoaderSnapshot = {
	status = "idle",
	stage = "boot",
	message = "starting loader",
	progress = 0,
	completed = 0,
	total = TOTAL_STAGE_WEIGHT,
	startedAt = os.clock(),
	finishedAt = nil,
	moduleCount = 0,
	assetCount = 0,
	assetLoadedCount = 0,
	assetFailedCount = 0,
	failureCount = 0,
	lastError = nil,
	failures = failures,
}

local completedWeight = 0

local function cloneStringArray(source: { string }): { string }
	local output = table.create(#source)
	for index, value in source do
		output[index] = value
	end
	return output
end

local function cloneSnapshot(): LoaderSnapshot
	local output = table.clone(snapshot) :: any
	output.failures = cloneStringArray(failures)
	return output :: LoaderSnapshot
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return existing
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureBindableEvent(parent: Instance, name: string): BindableEvent
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("BindableEvent") then
			return existing
		end
		existing:Destroy()
	end

	local bindable = Instance.new("BindableEvent")
	bindable.Name = name
	bindable.Parent = parent
	return bindable
end

local function ensureBindableFunction(parent: Instance, name: string): BindableFunction
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("BindableFunction") then
			return existing
		end
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = name
	bindable.Parent = parent
	return bindable
end

local function ensureBridge(): LoaderBridge
	local folder = ensureFolder(ReplicatedFirst, BRIDGE_NAME)
	local changed = ensureBindableEvent(folder, STATE_CHANGED_NAME)
	local getSnapshot = ensureBindableFunction(folder, GET_SNAPSHOT_NAME)

	return {
		folder = folder,
		changed = changed,
		getSnapshot = getSnapshot,
	}
end

local bridge = ensureBridge()

local function encodeSnapshotForAttribute(): string
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(cloneSnapshot())
	end)

	if ok and typeof(encoded) == "string" then
		return encoded
	end

	return "{}"
end

local function writeAttributes()
	local encodedSnapshot = encodeSnapshotForAttribute()
	local targets = {
		ReplicatedFirst,
		script,
		bridge.folder,
	}

	for _, target in targets do
		target:SetAttribute("AquariaLoaderStatus", snapshot.status)
		target:SetAttribute("AquariaLoaderStage", snapshot.stage)
		target:SetAttribute("AquariaLoaderMessage", snapshot.message)
		target:SetAttribute("AquariaLoaderProgress", snapshot.progress)
		target:SetAttribute("AquariaLoaderCompleted", snapshot.completed)
		target:SetAttribute("AquariaLoaderTotal", snapshot.total)
		target:SetAttribute("AquariaLoaderStartedAt", snapshot.startedAt)
		target:SetAttribute("AquariaLoaderFinishedAt", snapshot.finishedAt)
		target:SetAttribute("AquariaLoaderModuleCount", snapshot.moduleCount)
		target:SetAttribute("AquariaLoaderAssetCount", snapshot.assetCount)
		target:SetAttribute("AquariaLoaderAssetLoadedCount", snapshot.assetLoadedCount)
		target:SetAttribute("AquariaLoaderAssetFailedCount", snapshot.assetFailedCount)
		target:SetAttribute("AquariaLoaderFailureCount", snapshot.failureCount)
		target:SetAttribute("AquariaLoaderLastError", snapshot.lastError)
		target:SetAttribute("AquariaLoaderSnapshot", encodedSnapshot)
	end
end

local function publish(status: string, stage: string, message: string, progressRaw: number?)
	local progress = if typeof(progressRaw) == "number" then progressRaw else snapshot.progress

	snapshot.status = status
	snapshot.stage = stage
	snapshot.message = message
	snapshot.progress = math.clamp(progress, 0, 1)
	snapshot.completed = math.floor(snapshot.progress * TOTAL_STAGE_WEIGHT + 0.5)
	snapshot.failureCount = #failures
	snapshot.lastError = failures[#failures]

	if status == "complete" or status == "failed" then
		snapshot.finishedAt = snapshot.finishedAt or os.clock()
	end

	writeAttributes()
	bridge.changed:Fire(cloneSnapshot())
end

local function setStageProgress(stage: string, message: string, localProgressRaw: number, stageWeight: number)
	local localProgress = math.clamp(localProgressRaw, 0, 1)
	publish("running", stage, message, (completedWeight + stageWeight * localProgress) / TOTAL_STAGE_WEIGHT)
end

local function completeStage(stage: string, message: string, stageWeight: number)
	completedWeight += stageWeight
	publish("running", stage, message, completedWeight / TOTAL_STAGE_WEIGHT)
end

local function recordFailure(scope: string, err: any)
	local message = `{scope}: {tostring(err)}`
	failures[#failures + 1] = message
	snapshot.failureCount = #failures
	snapshot.lastError = message
	warn("[AquariaLoader] " .. message)
end

local function recordWarning(scope: string, err: any)
	warn("[AquariaLoader] " .. `{scope}: {tostring(err)}`)
end

bridge.getSnapshot.OnInvoke = function()
	return cloneSnapshot()
end

local function waitForRequiredChild(parent: Instance, name: string, timeoutSeconds: number): Instance
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		return existing
	end

	local found = parent:WaitForChild(name, timeoutSeconds)
	if found == nil then
		error(`timed out waiting for {parent:GetFullName()}.{name}`)
	end

	return found
end

local function waitForByteNetNamespace(storage: Instance, namespaceName: string, timeoutSeconds: number)
	local namespaceValue = waitForRequiredChild(storage, namespaceName, timeoutSeconds)
	if not namespaceValue:IsA("StringValue") then
		error(`expected ByteNet namespace {namespaceName} to be a StringValue`)
	end

	local deadline = os.clock() + timeoutSeconds
	while namespaceValue.Value == "" and os.clock() < deadline do
		task.wait(0.05)
	end

	if namespaceValue.Value == "" then
		error(`timed out waiting for ByteNet namespace {namespaceName} to be ready`)
	end
end

local function waitForInstancePath(root: Instance, path: { string }, timeoutSeconds: number): Instance
	local deadline = os.clock() + timeoutSeconds
	local current = root

	for _, childName in path do
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			error(`timed out waiting for {current:GetFullName()}.{childName}`)
		end

		local child = current:FindFirstChild(childName)
		if child == nil then
			child = current:WaitForChild(childName, remaining)
		end
		if child == nil then
			error(`timed out waiting for {current:GetFullName()}.{childName}`)
		end

		current = child
	end

	return current
end

local function waitForRequiredModule(root: Instance, path: { string }, timeoutSeconds: number): ModuleScript
	local current = root
	for _, childName in path do
		current = waitForRequiredChild(current, childName, timeoutSeconds)
	end

	if not current:IsA("ModuleScript") then
		error(`{current:GetFullName()} is not a ModuleScript`)
	end

	return current
end

local function getLocalPlayer(): Player
	local player = Players.LocalPlayer
	while player == nil do
		Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
		player = Players.LocalPlayer
	end
	return player
end

local function isContentId(value: string): boolean
	return string.find(value, "rbxassetid://", 1, true) == 1
		or string.find(value, "rbxasset://", 1, true) == 1
		or string.find(value, "rbxthumb://", 1, true) == 1
end

local function addAssetId(assetIds: { string }, assetSet: { [string]: boolean }, valueRaw: any)
	if typeof(valueRaw) ~= "string" then
		return
	end
	if not isContentId(valueRaw) then
		return
	end
	if assetSet[valueRaw] then
		return
	end

	assetSet[valueRaw] = true
	assetIds[#assetIds + 1] = valueRaw
	snapshot.assetCount = #assetIds
end

local function collectAssetIdsFromValue(
	valueRaw: any,
	assetIds: { string },
	assetSet: { [string]: boolean },
	seenTables: { [any]: boolean }?,
	depthRaw: number?
)
	addAssetId(assetIds, assetSet, valueRaw)

	if typeof(valueRaw) ~= "table" then
		return
	end

	local depth = if typeof(depthRaw) == "number" then depthRaw else 0
	if depth > 12 then
		return
	end

	local seen = seenTables or ({} :: any)
	local valueTable = valueRaw :: any
	if seen[valueTable] then
		return
	end
	seen[valueTable] = true

	for key, value in valueRaw do
		collectAssetIdsFromValue(key, assetIds, assetSet, seen, depth + 1)
		collectAssetIdsFromValue(value, assetIds, assetSet, seen, depth + 1)
	end
end

local function collectAssetIdsFromInstance(instance: Instance, assetIds: { string }, assetSet: { [string]: boolean })
	for className, propertyNames in CONTENT_PROPERTIES_BY_CLASS do
		if not instance:IsA(className) then
			continue
		end

		for _, propertyName in propertyNames do
			local ok, value = pcall(function()
				return (instance :: any)[propertyName]
			end)

			if ok then
				addAssetId(assetIds, assetSet, value)
			end
		end
	end
end

local function collectAssetIdsFromTree(root: Instance, assetIds: { string }, assetSet: { [string]: boolean })
	collectAssetIdsFromInstance(root, assetIds, assetSet)
	for _, descendant in root:GetDescendants() do
		collectAssetIdsFromInstance(descendant, assetIds, assetSet)
	end
end

local function getRelativeModulePath(root: Instance, moduleScript: ModuleScript): string?
	local names = {}
	local current: Instance? = moduleScript
	while current ~= nil and current ~= root do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end

	if current ~= root then
		return nil
	end

	return table.concat(names, "/")
end

local function endsWith(text: string, suffix: string): boolean
	return string.sub(text, -#suffix) == suffix
end

local function isServerOnlyModuleName(moduleName: string): boolean
	for _, suffix in SERVER_ONLY_MODULE_NAME_SUFFIXES do
		if endsWith(moduleName, suffix) then
			return true
		end
	end

	return false
end

local function shouldPrewarmModule(root: Instance, moduleScript: ModuleScript): boolean
	if SKIPPED_MODULE_NAMES[moduleScript.Name] == true then
		return false
	end
	if isServerOnlyModuleName(moduleScript.Name) then
		return false
	end
	if string.find(moduleScript.Name, ".spec", 1, true) ~= nil then
		return false
	end
	if string.find(moduleScript.Name, ".story", 1, true) ~= nil then
		return false
	end
	local relativePath = getRelativeModulePath(root, moduleScript)
	if relativePath ~= nil and SKIPPED_MODULE_PATHS[relativePath] == true then
		return false
	end

	return true
end

local function collectModuleScripts(root: Instance): { ModuleScript }
	local modules = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ModuleScript") and shouldPrewarmModule(root, descendant) then
			modules[#modules + 1] = descendant
		end
	end

	table.sort(modules, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	return modules
end

local function requireModule(
	moduleScript: ModuleScript,
	label: string,
	warmedModules: { [Instance]: boolean },
	assetIds: { string },
	assetSet: { [string]: boolean },
	isCritical: boolean
): any
	if warmedModules[moduleScript] == true then
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		if isCritical then
			error(`failed to load {label}: {tostring(result)}`)
		end

		recordFailure(label, result)
		return nil
	end

	warmedModules[moduleScript] = true
	snapshot.moduleCount += 1
	collectAssetIdsFromValue(result, assetIds, assetSet)
	return result
end

local function getWorkspaceFoldersModule(context: ReplicatedContext): ModuleScript?
	local coreFolder = context.sharedRoot:FindFirstChild("Core")
	if coreFolder ~= nil then
		local workspaceFoldersModule = coreFolder:FindFirstChild("WorkspaceFolders")
		if workspaceFoldersModule ~= nil and workspaceFoldersModule:IsA("ModuleScript") then
			return workspaceFoldersModule
		end
	end

	local modulesFolder = context.sharedRoot:FindFirstChild("Modules")
	if modulesFolder == nil then
		return nil
	end
	local modulesCoreFolder = modulesFolder:FindFirstChild("Core")
	if modulesCoreFolder == nil then
		return nil
	end
	local workspaceFoldersModule = modulesCoreFolder:FindFirstChild("WorkspaceFolders")
	if workspaceFoldersModule ~= nil and workspaceFoldersModule:IsA("ModuleScript") then
		return workspaceFoldersModule
	end
	return nil
end

local function adoptPartCacheFolder(context: ReplicatedContext)
	local loosePartCacheFolder = Workspace:FindFirstChild(PART_CACHE_FOLDER_NAME)
	if loosePartCacheFolder == nil then
		return
	end
	if not loosePartCacheFolder:IsA("Folder") then
		return
	end

	local workspaceFoldersModule = getWorkspaceFoldersModule(context)
	if workspaceFoldersModule == nil then
		recordWarning("part cache folder", "WorkspaceFolders module was not available")
		return
	end

	local ok, workspaceFolders = pcall(require, workspaceFoldersModule)
	if not ok or typeof(workspaceFolders) ~= "table" then
		recordWarning("part cache folder", workspaceFolders)
		return
	end

	local gameFolder = (workspaceFolders :: any).GetOrCreateGameFolder()
	if typeof(gameFolder) ~= "Instance" or not gameFolder:IsA("Folder") then
		recordWarning("part cache folder", "Game folder was not available")
		return
	end

	local existing = gameFolder:FindFirstChild(PART_CACHE_FOLDER_NAME)
	if existing ~= nil and existing ~= loosePartCacheFolder then
		if existing:IsA("Folder") then
			for _, child in loosePartCacheFolder:GetChildren() do
				child.Parent = existing
			end
			loosePartCacheFolder:Destroy()
			if typeof((workspaceFolders :: any).ManageFolder) == "function" then
				(workspaceFolders :: any).ManageFolder(existing, gameFolder)
			end
			return
		end
		existing:Destroy()
	end

	if typeof((workspaceFolders :: any).ManageFolder) == "function" then
		(workspaceFolders :: any).ManageFolder(loosePartCacheFolder, gameFolder)
	end
	if #loosePartCacheFolder:GetChildren() > 0 then
		loosePartCacheFolder.Parent = gameFolder
	end
end

local function countDictionaryEntries(dictionaryRaw: any): number
	if typeof(dictionaryRaw) ~= "table" then
		return 0
	end

	local count = 0
	for _ in dictionaryRaw do
		count += 1
	end
	return count
end

local function waitForReplicatedContext(): ReplicatedContext
	setStageProgress("replication", "waiting for replicated game package", 0, STAGE_WEIGHT_REPLICATION)

	local packageRoot = waitForRequiredChild(ReplicatedStorage, PACKAGE_NAME, REPLICATION_TIMEOUT_SECONDS)
	local gameRoot = waitForRequiredChild(packageRoot, "game", REPLICATION_TIMEOUT_SECONDS)
	local clientRealmRoot = waitForRequiredChild(gameRoot, "Client", REPLICATION_TIMEOUT_SECONDS)
	local sharedRealmRoot = waitForRequiredChild(gameRoot, "Shared", REPLICATION_TIMEOUT_SECONDS)
	local clientRoot = waitForRequiredChild(clientRealmRoot, SOURCE_FOLDER_NAME, REPLICATION_TIMEOUT_SECONDS)
	local sharedRoot = waitForRequiredChild(sharedRealmRoot, SOURCE_FOLDER_NAME, REPLICATION_TIMEOUT_SECONDS)
	local packagesRoot = waitForRequiredChild(ReplicatedStorage, "Packages", REPLICATION_TIMEOUT_SECONDS)
	local vendorRoot = waitForRequiredChild(sharedRealmRoot, VENDOR_FOLDER_NAME, REPLICATION_TIMEOUT_SECONDS)

	completeStage("replication", "replicated game package is ready", STAGE_WEIGHT_REPLICATION)
	return {
		packageRoot = packageRoot,
		gameRoot = gameRoot,
		clientRoot = clientRoot,
		sharedRoot = sharedRoot,
		packagesRoot = packagesRoot,
		vendorRoot = vendorRoot,
	}
end

local function waitForNevermoreLoader(context: ReplicatedContext)
	setStageProgress("framework", "waiting for nevermore loader", 0, STAGE_WEIGHT_FRAMEWORK)

	local loader = waitForRequiredChild(context.packageRoot, "loader", REPLICATION_TIMEOUT_SECONDS)
	if not loader:IsA("ModuleScript") then
		error("replicated loader is not a ModuleScript")
	end

	local loaderLink = waitForRequiredChild(loader, "LoaderLink", REPLICATION_TIMEOUT_SECONDS)
	if not loaderLink:IsA("ObjectValue") then
		error("replicated loader link is not an ObjectValue")
	end

	local deadline = os.clock() + REPLICATION_TIMEOUT_SECONDS
	while loaderLink.Value == nil and os.clock() < deadline do
		task.wait(0.05)
	end
	if loaderLink.Value == nil then
		error("replicated loader link did not resolve")
	end

	completeStage("framework", "nevermore framework is ready", STAGE_WEIGHT_FRAMEWORK)
end

local function waitForNetwork(
	context: ReplicatedContext,
	warmedModules: { [Instance]: boolean },
	assetIds: { string },
	assetSet: { [string]: boolean }
)
	setStageProgress("network", "waiting for network remotes", 0, STAGE_WEIGHT_NETWORK)

	waitForRequiredChild(ReplicatedStorage, BYTE_NET_RELIABLE_REMOTE_NAME, NETWORK_TIMEOUT_SECONDS)
	waitForRequiredChild(ReplicatedStorage, BYTE_NET_UNRELIABLE_REMOTE_NAME, NETWORK_TIMEOUT_SECONDS)

	local byteNetStorage = waitForRequiredChild(ReplicatedStorage, BYTE_NET_STORAGE_NAME, NETWORK_TIMEOUT_SECONDS)
	for _, namespaceName in BYTE_NET_NAMESPACE_NAMES do
		waitForByteNetNamespace(byteNetStorage, namespaceName, NETWORK_TIMEOUT_SECONDS)
	end

	setStageProgress("network", "registering network packet readers", 0.9, STAGE_WEIGHT_NETWORK)
	local clientPacketsModule = waitForRequiredModule(
		context.gameRoot,
		{ "Client", SOURCE_FOLDER_NAME, "NetClient", "NetPacketsClient" },
		REPLICATION_TIMEOUT_SECONDS
	)
	requireModule(clientPacketsModule, "client network packets", warmedModules, assetIds, assetSet, true)

	completeStage("network", "network remotes are ready", STAGE_WEIGHT_NETWORK)
end

local function waitForBloodEnginePackageAssets(vendorRoot: Instance)
	local bloodEngineRoot = waitForRequiredChild(vendorRoot, BLOOD_ENGINE_PACKAGE_NAME, REPLICATION_TIMEOUT_SECONDS)

	for _, path in
		{
			{ "Assets", "Meshes", "Droplet" },
			{ "Assets", "Meshes", "Decal" },
			{ "Assets", "Images" },
			{ "Assets", "Sounds" },
		}
	do
		waitForInstancePath(bloodEngineRoot, path, REPLICATION_TIMEOUT_SECONDS)
	end
end

local function prewarmRuntimePackages(
	context: ReplicatedContext,
	warmedModules: { [Instance]: boolean },
	assetIds: { string },
	assetSet: { [string]: boolean }
)
	setStageProgress("packages", "loading runtime packages", 0, STAGE_WEIGHT_PACKAGES)
	waitForBloodEnginePackageAssets(context.vendorRoot)
	local runtimePackageCount = #RUNTIME_WALLY_PACKAGES + #RUNTIME_VENDOR_PACKAGES

	for index, packageName in RUNTIME_WALLY_PACKAGES do
		local packageModule = context.packagesRoot:FindFirstChild(packageName)
		if packageModule == nil or not packageModule:IsA("ModuleScript") then
			recordFailure("package " .. packageName, "missing package module")
		else
			requireModule(packageModule, "package " .. packageName, warmedModules, assetIds, assetSet, false)
		end

		setStageProgress(
			"packages",
			`loading runtime packages {index}/{runtimePackageCount}`,
			index / runtimePackageCount,
			STAGE_WEIGHT_PACKAGES
		)
	end

	for index, packageName in RUNTIME_VENDOR_PACKAGES do
		local completedPackageCount = #RUNTIME_WALLY_PACKAGES + index
		local packageModule = context.vendorRoot:FindFirstChild(packageName)
		if packageModule == nil or not packageModule:IsA("ModuleScript") then
			recordFailure("vendor package " .. packageName, "missing package module")
		else
			requireModule(packageModule, "vendor package " .. packageName, warmedModules, assetIds, assetSet, false)
		end

		setStageProgress(
			"packages",
			`loading runtime packages {completedPackageCount}/{runtimePackageCount}`,
			completedPackageCount / runtimePackageCount,
			STAGE_WEIGHT_PACKAGES
		)
	end

	completeStage("packages", "runtime packages are ready", STAGE_WEIGHT_PACKAGES)
end

local function prewarmCriticalModules(
	context: ReplicatedContext,
	warmedModules: { [Instance]: boolean },
	assetIds: { string },
	assetSet: { [string]: boolean }
): { [string]: any }
	local critical = {
		{
			key = "CoreConfigs",
			label = "core configs",
			path = { "Shared", SOURCE_FOLDER_NAME, "Core", "CoreConfigs" },
		},
		{
			key = "Runtime",
			label = "core runtime",
			path = { "Shared", SOURCE_FOLDER_NAME, "Core", "CoreRuntime" },
		},
		{
			key = "ItemRegistry",
			label = "item registry",
			path = { "Shared", SOURCE_FOLDER_NAME, "Item", "Modules", "ItemRegistry" },
		},
		{
			key = "ImageIds",
			label = "ui image ids",
			path = { "Shared", SOURCE_FOLDER_NAME, "Core", "UI", "ImageIds" },
		},
		{
			key = "RootUI",
			label = "react root ui",
			path = { "Client", SOURCE_FOLDER_NAME, "App", "RootUI" },
		},
		{
			key = "AquariaBackupServiceClient",
			label = "client service bootstrap",
			path = { "Client", SOURCE_FOLDER_NAME, "AquariaBackupServiceClient" },
		},
	}

	local results = {}
	for index, entry in critical do
		setStageProgress(
			"modules",
			`loading critical module {entry.label}`,
			((index - 1) / #critical) * CRITICAL_MODULE_PROGRESS_SHARE,
			STAGE_WEIGHT_MODULES
		)

		local moduleScript = waitForRequiredModule(context.gameRoot, entry.path, REPLICATION_TIMEOUT_SECONDS)
		results[entry.key] = requireModule(moduleScript, entry.label, warmedModules, assetIds, assetSet, true)
	end

	return results
end

local function prewarmGameModules(
	context: ReplicatedContext,
	warmedModules: { [Instance]: boolean },
	assetIds: { string },
	assetSet: { [string]: boolean }
)
	local modules = {}
	for _, moduleScript in collectModuleScripts(context.sharedRoot) do
		modules[#modules + 1] = moduleScript
	end
	for _, moduleScript in collectModuleScripts(context.clientRoot) do
		modules[#modules + 1] = moduleScript
	end

	table.sort(modules, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	if #modules <= 0 then
		completeStage("modules", "game modules are ready", STAGE_WEIGHT_MODULES)
		return
	end

	for index, moduleScript in modules do
		requireModule(moduleScript, moduleScript:GetFullName(), warmedModules, assetIds, assetSet, false)

		if index % MODULE_REQUIRE_BATCH_SIZE == 0 or index == #modules then
			setStageProgress(
				"modules",
				`loading game modules {index}/{#modules}`,
				CRITICAL_MODULE_PROGRESS_SHARE + (1 - CRITICAL_MODULE_PROGRESS_SHARE) * (index / #modules),
				STAGE_WEIGHT_MODULES
			)
			task.wait()
		end
	end

	completeStage("modules", "game modules are ready", STAGE_WEIGHT_MODULES)
end

local function warmItemRegistry(itemRegistryRaw: any, assetIds: { string }, assetSet: { [string]: boolean })
	setStageProgress("data", "warming item registry", 0, STAGE_WEIGHT_DATA)

	local deadline = os.clock() + ITEM_REGISTRY_WARMUP_TIMEOUT_SECONDS
	local lastDefinitionCount = -1
	local stablePasses = 0
	local definitionsById = {}

	while os.clock() < deadline do
		if typeof(itemRegistryRaw.ClearCache) == "function" then
			itemRegistryRaw.ClearCache()
		end

		definitionsById = if typeof(itemRegistryRaw.GetDefinitionsById) == "function"
			then itemRegistryRaw.GetDefinitionsById()
			else {} :: any

		local definitionCount = countDictionaryEntries(definitionsById)
		if definitionCount > 0 then
			if definitionCount == lastDefinitionCount then
				stablePasses += 1
			else
				lastDefinitionCount = definitionCount
				stablePasses = 1
			end

			if stablePasses >= ITEM_REGISTRY_STABLE_PASSES_REQUIRED then
				collectAssetIdsFromValue(definitionsById, assetIds, assetSet)
				completeStage("data", `item registry warmed with {definitionCount} definitions`, STAGE_WEIGHT_DATA)
				return
			end
		else
			lastDefinitionCount = definitionCount
			stablePasses = 0
		end

		setStageProgress("data", "warming item registry", 0.5, STAGE_WEIGHT_DATA)
		task.wait()
	end

	collectAssetIdsFromValue(definitionsById, assetIds, assetSet)
	recordFailure("item registry", "timed out before registry stabilized")
	completeStage("data", "item registry warmup timed out", STAGE_WEIGHT_DATA)
end

local function preloadAssets(assetIds: { string })
	setStageProgress("assets", "preloading content", 0, STAGE_WEIGHT_ASSETS)

	if #assetIds <= 0 then
		completeStage("assets", "no content ids found", STAGE_WEIGHT_ASSETS)
		return
	end

	snapshot.assetCount = #assetIds
	snapshot.assetLoadedCount = 0
	snapshot.assetFailedCount = 0

	for startIndex = 1, #assetIds, ASSET_PRELOAD_BATCH_SIZE do
		local batch = {}
		local endIndex = math.min(startIndex + ASSET_PRELOAD_BATCH_SIZE - 1, #assetIds)
		for index = startIndex, endIndex do
			batch[#batch + 1] = assetIds[index]
		end

		local loadedBeforeBatch = snapshot.assetLoadedCount
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(batch, function(_contentId: string, fetchStatus: Enum.AssetFetchStatus)
				snapshot.assetLoadedCount += 1

				if string.find(tostring(fetchStatus), "Success", 1, true) == nil then
					snapshot.assetFailedCount += 1
				end

				if
					snapshot.assetLoadedCount % ASSET_PROGRESS_INTERVAL == 0
					or snapshot.assetLoadedCount >= #assetIds
				then
					setStageProgress(
						"assets",
						`preloading content {snapshot.assetLoadedCount}/{#assetIds}`,
						snapshot.assetLoadedCount / #assetIds,
						STAGE_WEIGHT_ASSETS
					)
				end
			end)
		end)

		if not ok then
			snapshot.assetFailedCount += #batch
			recordWarning("content preload", err)
		elseif snapshot.assetLoadedCount < loadedBeforeBatch + #batch then
			snapshot.assetLoadedCount = loadedBeforeBatch + #batch
		end

		setStageProgress(
			"assets",
			`preloading content {math.min(snapshot.assetLoadedCount, #assetIds)}/{#assetIds}`,
			math.min(snapshot.assetLoadedCount, #assetIds) / #assetIds,
			STAGE_WEIGHT_ASSETS
		)
		task.wait()
	end

	completeStage("assets", "content preload finished", STAGE_WEIGHT_ASSETS)
end

local function findWorldGenerationFolder(): Folder?
	local gameFolder = Workspace:FindFirstChild(WORKSPACE_GAME_FOLDER_NAME)
	if gameFolder ~= nil and gameFolder:IsA("Folder") then
		local worldFolder = gameFolder:FindFirstChild(WORLD_GENERATION_FOLDER_NAME)
		if worldFolder ~= nil and worldFolder:IsA("Folder") then
			return worldFolder
		end
	end

	local worldFolder = Workspace:FindFirstChild(WORLD_GENERATION_FOLDER_NAME)
	if worldFolder ~= nil and worldFolder:IsA("Folder") then
		return worldFolder
	end

	return nil
end

local function countReadyCollisionChunks(): number
	local worldFolder = findWorldGenerationFolder()
	if worldFolder == nil then
		return 0
	end

	local collisionChunksFolder = worldFolder:FindFirstChild(COLLISION_CHUNKS_FOLDER_NAME)
	if collisionChunksFolder == nil or not collisionChunksFolder:IsA("Folder") then
		return 0
	end

	local readyCount = 0
	for _, child in collisionChunksFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("ChunkCollisionReady") == true then
			readyCount += 1
		end
	end
	return readyCount
end

local function preloadWorldChunks()
	setStageProgress("chunks", "preloading spawn chunks", 0, STAGE_WEIGHT_CHUNKS)

	local deadline = os.clock() + WORLD_CHUNK_PRELOAD_TIMEOUT_SECONDS
	while os.clock() < deadline do
		local readyCount = countReadyCollisionChunks()
		if readyCount >= WORLD_CHUNK_PRELOAD_MIN_READY_CHUNKS then
			completeStage("chunks", `spawn chunks ready ({readyCount})`, STAGE_WEIGHT_CHUNKS)
			return
		end

		setStageProgress(
			"chunks",
			`preloading spawn chunks {readyCount}/{WORLD_CHUNK_PRELOAD_MIN_READY_CHUNKS}`,
			readyCount / WORLD_CHUNK_PRELOAD_MIN_READY_CHUNKS,
			STAGE_WEIGHT_CHUNKS
		)
		task.wait(0.05)
	end

	recordWarning("world chunk preload", "timed out waiting for spawn collision chunks")
	completeStage("chunks", "spawn chunk preload timed out", STAGE_WEIGHT_CHUNKS)
end

local function waitForClientBootScript()
	setStageProgress("scripts", "waiting for client boot scripts", 0, STAGE_WEIGHT_SCRIPTS)

	local player = getLocalPlayer()
	local playerScripts = player:WaitForChild("PlayerScripts", CLIENT_SCRIPT_TIMEOUT_SECONDS)
	if playerScripts == nil then
		recordFailure("client scripts", "player scripts did not replicate before timeout")
		completeStage("scripts", "client boot script wait timed out", STAGE_WEIGHT_SCRIPTS)
		return
	end

	local scriptFolder = playerScripts:FindFirstChild(CLIENT_SCRIPT_FOLDER_NAME)
		or playerScripts:WaitForChild(CLIENT_SCRIPT_FOLDER_NAME, CLIENT_SCRIPT_TIMEOUT_SECONDS)
	if scriptFolder == nil then
		recordFailure("client scripts", "aquaria client script folder did not replicate before timeout")
		completeStage("scripts", "client boot script wait timed out", STAGE_WEIGHT_SCRIPTS)
		return
	end

	local bootScript = scriptFolder:FindFirstChild(CLIENT_BOOT_SCRIPT_NAME)
		or scriptFolder:WaitForChild(CLIENT_BOOT_SCRIPT_NAME, CLIENT_SCRIPT_TIMEOUT_SECONDS)
	if bootScript == nil then
		recordFailure("client scripts", "ClientMain did not replicate before timeout")
		completeStage("scripts", "client boot script wait timed out", STAGE_WEIGHT_SCRIPTS)
		return
	end

	completeStage("scripts", "client boot scripts are present", STAGE_WEIGHT_SCRIPTS)
end

local function runLoader()
	if not RunService:IsClient() then
		return
	end

	publish("running", "boot", "starting loader", 0)

	local assetIds = {}
	local assetSet = {}
	local warmedModules = {}

	local context = waitForReplicatedContext()
	waitForNevermoreLoader(context)

	waitForNetwork(context, warmedModules, assetIds, assetSet)
	prewarmRuntimePackages(context, warmedModules, assetIds, assetSet)
	adoptPartCacheFolder(context)

	local criticalResults = prewarmCriticalModules(context, warmedModules, assetIds, assetSet)
	prewarmGameModules(context, warmedModules, assetIds, assetSet)
	warmItemRegistry(criticalResults.ItemRegistry, assetIds, assetSet)

	collectAssetIdsFromTree(ReplicatedFirst, assetIds, assetSet)
	collectAssetIdsFromTree(ReplicatedStorage, assetIds, assetSet)
	preloadAssets(assetIds)
	preloadWorldChunks()
	waitForClientBootScript()

	if #failures > 0 then
		publish("failed", "failed", `loader completed with {#failures} issue(s)`, completedWeight / TOTAL_STAGE_WEIGHT)
		return
	end

	publish("complete", "complete", "loader complete", 1)
end

local ok, err = (xpcall :: any)(runLoader, debug.traceback)
if not ok then
	recordFailure("loader", err)
	publish("failed", "failed", "loader failed", math.max(snapshot.progress, completedWeight / TOTAL_STAGE_WEIGHT))
end
