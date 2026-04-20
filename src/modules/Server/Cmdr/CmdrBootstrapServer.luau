--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local nevermoreRequire = require(loaderUtils.Parent).load(script)

local CmdrService = nevermoreRequire("CmdrService")
local CmdrUtils = require(script:FindFirstAncestor("game").Shared.Cmdr.CmdrUtils)

local CmdrBootstrapServer = {}

local started = false
local CMDR_COMMAND_LOAD_TIMEOUT_SECONDS = 10
local CMDR_COMMAND_LOAD_POLL_INTERVAL_SECONDS = 0.1
local EXTRA_ALLOWED_USER_IDS = {}
local INFRASTRUCTURE_MODULE_KEYS = {
	loader = true,
	cmdrpackageresolver = true,
}
local MIN_CREATOR_GROUP_RANK = 254

local function isExtraAllowedUserId(userId: number): boolean
	return EXTRA_ALLOWED_USER_IDS[userId] == true
end

local function isCreatorAuthorized(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function(): number
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank >= MIN_CREATOR_GROUP_RANK
	end

	return false
end

local function isCmdrAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end

	if isExtraAllowedUserId(player.UserId) then
		return true
	end

	return isCreatorAuthorized(player)
end

local function applyCmdrPlayerAttributes(player: Player)
	player:SetAttribute(CmdrUtils.CMDR_ENABLED_ATTRIBUTE, isCmdrAuthorized(player))

	if player:GetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE, false)
	end
	if player:GetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, CmdrUtils.DEFAULT_FLY_SPEED)
	end
	if player:GetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE, false)
	end
	if player:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE, false)
	end
end

local function clearCmdrPlayerAttributes(player: Player)
	player:SetAttribute(CmdrUtils.CMDR_ENABLED_ATTRIBUTE, nil)
	player:SetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE, nil)
	player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, nil)
	player:SetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE, nil)
	player:SetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE, nil)
end

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeCommandKey(valueRaw: any): string
	local value = trim(valueRaw)
	if value == "" then
		return ""
	end

	value = string.lower(value)
	value = string.gsub(value, "[%s_%-]+", "")

	return value
end

local function normalizeServerModuleKey(valueRaw: any): string
	local value = trim(valueRaw)
	if value == "" then
		return ""
	end

	local lowercaseValue = string.lower(value)
	if string.sub(value, -6) == "Server" or (value == lowercaseValue and string.sub(value, -6) == "server") then
		value = string.sub(value, 1, -7)
	end

	return normalizeCommandKey(value)
end

local function isCmdrInfrastructureModule(moduleScript: ModuleScript): boolean
	return INFRASTRUCTURE_MODULE_KEYS[normalizeCommandKey(moduleScript.Name)] == true
end

local function resolveCmdrRoots(): (Folder, Folder, Folder)
	local gameRoot = script:FindFirstAncestor("game")
	assert(gameRoot ~= nil, "Missing Nevermore game root for CmdrBootstrapServer.")

	local sharedRoot = gameRoot:FindFirstChild("Shared")
	assert(sharedRoot ~= nil and sharedRoot:IsA("Folder"), "Shared folder was not found in the Nevermore game root.")

	local sharedCmdrRoot = sharedRoot:FindFirstChild("Cmdr")
	assert(sharedCmdrRoot ~= nil and sharedCmdrRoot:IsA("Folder"), "Cmdr folder was not found in the Nevermore shared root.")

	local serverRoot = gameRoot:FindFirstChild("Server")
	assert(serverRoot ~= nil and serverRoot:IsA("Folder"), "Server folder was not found in the Nevermore game root.")

	local serverCmdrRoot = serverRoot:FindFirstChild("Cmdr")
	assert(serverCmdrRoot ~= nil and serverCmdrRoot:IsA("Folder"), "Cmdr folder was not found in the Nevermore server root.")

	local cmdrTypes = sharedCmdrRoot:FindFirstChild("Types")
	local sharedCommands = sharedCmdrRoot:FindFirstChild("Commands")
	local serverCommands = serverCmdrRoot:FindFirstChild("ServerCommands")
	assert(cmdrTypes ~= nil and cmdrTypes:IsA("Folder"), "Cmdr Types folder was not found.")
	assert(sharedCommands ~= nil and sharedCommands:IsA("Folder"), "Cmdr shared Commands folder was not found.")
	assert(serverCommands ~= nil and serverCommands:IsA("Folder"), "Cmdr ServerCommands folder was not found.")

	return cmdrTypes, sharedCommands, serverCommands
end

local function collectModuleScriptsByKey(folder: Instance, useServerModuleKeys: boolean?): { [string]: { ModuleScript } }
	local modulesByKey = {}

	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") and not isCmdrInfrastructureModule(child) then
			local moduleKey = if useServerModuleKeys == true
				then normalizeServerModuleKey(child.Name)
				else normalizeCommandKey(child.Name)
			if moduleKey == "" then
				continue
			end

			local bucket = modulesByKey[moduleKey]
			if bucket == nil then
				bucket = {}
				modulesByKey[moduleKey] = bucket
			end
			bucket[#bucket + 1] = child
		end
	end

	for _, bucket in modulesByKey do
		table.sort(bucket, function(left: ModuleScript, right: ModuleScript)
			return left:GetFullName() < right:GetFullName()
		end)
	end

	return modulesByKey
end

local function getSortedModuleNames(modulesByKey: { [string]: { ModuleScript } }): { string }
	local names = {}

	for name in modulesByKey do
		names[#names + 1] = name
	end

	table.sort(names, function(left: string, right: string)
		return string.lower(left) < string.lower(right)
	end)

	return names
end

local function tryRequireCommandDefinition(moduleScript: ModuleScript): (boolean, any, string?)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		return false, nil, `[CmdrBootstrapServer] Failed to require shared Cmdr module {moduleScript:GetFullName()}: {result}`
	end

	if typeof(result) ~= "table" then
		return false, nil, `[CmdrBootstrapServer] Shared Cmdr module {moduleScript:GetFullName()} returned {typeof(result)} instead of a table.`
	end

	local commandName = trim((result :: any).Name)
	if commandName == "" then
		return false,
			nil,
			`[CmdrBootstrapServer] Shared Cmdr module {moduleScript:GetFullName()} returned a table without a valid Name.`
	end

	return true, result, nil
end

local function tryRequireCommandExecutor(moduleScript: ModuleScript): (boolean, any, string?)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		return false, nil, `[CmdrBootstrapServer] Failed to require server Cmdr module {moduleScript:GetFullName()}: {result}`
	end

	if typeof(result) ~= "function" then
		return false,
			nil,
			`[CmdrBootstrapServer] Server Cmdr module {moduleScript:GetFullName()} returned {typeof(result)} instead of a function.`
	end

	return true, result, nil
end

local function resolveFirstValidModule(
	moduleScripts: { ModuleScript },
	validator: (ModuleScript) -> (boolean, any, string?)
): (ModuleScript?, any, { string })
	local issues = {}

	for _, moduleScript in moduleScripts do
		local ok, result, issue = validator(moduleScript)
		if ok then
			return moduleScript, result, issues
		end

		if issue ~= nil then
			issues[#issues + 1] = issue
		end
	end

	return nil, nil, issues
end

local function resolveServerCommandCandidates(
	serverModulesByKey: { [string]: { ModuleScript } },
	candidateKeys: { string }
): { ModuleScript }
	local candidates = {}
	local seen = {}

	for _, candidateKey in candidateKeys do
		local normalizedKey = normalizeCommandKey(candidateKey)
		local matchingServerModules = serverModulesByKey[normalizedKey]
		if matchingServerModules ~= nil then
			for _, moduleScript in matchingServerModules do
				if seen[moduleScript] ~= true then
					seen[moduleScript] = true
					candidates[#candidates + 1] = moduleScript
				end
			end
		end
	end

	return candidates
end

local function getMissingServerCommandKeys(
	sharedModulesByKey: { [string]: { ModuleScript } },
	serverModulesByKey: { [string]: { ModuleScript } }
): { string }
	local missingKeys = {}

	for sharedModuleKey in sharedModulesByKey do
		if serverModulesByKey[sharedModuleKey] == nil then
			missingKeys[#missingKeys + 1] = sharedModuleKey
		end
	end

	table.sort(missingKeys, function(left: string, right: string)
		return left < right
	end)

	return missingKeys
end

local function waitForCmdrCommandModuleMaps(
	sharedFolder: Instance,
	serverFolder: Instance
): ({ [string]: { ModuleScript } }, { [string]: { ModuleScript } }, { string })
	local deadline = os.clock() + CMDR_COMMAND_LOAD_TIMEOUT_SECONDS

	while true do
		local sharedModulesByKey = collectModuleScriptsByKey(sharedFolder)
		local serverModulesByKey = collectModuleScriptsByKey(serverFolder, true)

		if next(sharedModulesByKey) == nil then
			return sharedModulesByKey, serverModulesByKey, {}
		end

		local missingServerKeys = getMissingServerCommandKeys(sharedModulesByKey, serverModulesByKey)
		if #missingServerKeys <= 0 then
			return sharedModulesByKey, serverModulesByKey, missingServerKeys
		end

		if os.clock() >= deadline then
			return sharedModulesByKey, serverModulesByKey, missingServerKeys
		end

		task.wait(CMDR_COMMAND_LOAD_POLL_INTERVAL_SECONDS)
	end
end

local function warnDuplicateModules(kind: string, moduleName: string, modules: { ModuleScript })
	if #modules <= 1 then
		return
	end

	local fullNames = {}
	for index, moduleScript in modules do
		fullNames[index] = moduleScript:GetFullName()
	end

	warn(
		`[CmdrBootstrapServer] Found duplicate {kind} Cmdr modules named "{moduleName}". Using the first valid candidate from: {table.concat(fullNames, "; ")}`
	)
end

local function warnModuleIssues(issues: { string })
	for _, issue in issues do
		warn(issue)
	end
end

local function registerCmdrCommands(cmdrService: any, sharedFolder: Instance, serverFolder: Instance): number
	local registeredCount = 0
	local sharedModulesByKey, serverModulesByKey, missingServerKeys = waitForCmdrCommandModuleMaps(sharedFolder, serverFolder)

	if #missingServerKeys > 0 then
		warn(
			`[CmdrBootstrapServer] Timed out waiting for server Cmdr executor modules in {serverFolder:GetFullName()}. Missing keys: {table.concat(missingServerKeys, ", ")}`
		)
	end

	for _, sharedModuleKey in getSortedModuleNames(sharedModulesByKey) do
		local sharedModules = sharedModulesByKey[sharedModuleKey]
		warnDuplicateModules("shared", sharedModuleKey, sharedModules)

		local sharedModule, commandData, sharedIssues =
			resolveFirstValidModule(sharedModules, tryRequireCommandDefinition)
		warnModuleIssues(sharedIssues)

		local commandLabel = sharedModules[1].Name
		if commandData ~= nil then
			local commandName = trim((commandData :: any).Name)
			if commandName ~= "" then
				commandLabel = commandName
			end
		end

		if sharedModule == nil then
			warn(
				`[CmdrBootstrapServer] Skipping Cmdr command "{commandLabel}" because no valid shared command definition module was found in {sharedFolder:GetFullName()}.`
			)
			continue
		end

		local candidateServerKeys = { sharedModuleKey }
		local commandNameKey = normalizeCommandKey((commandData :: any).Name)
		if commandNameKey ~= "" and commandNameKey ~= sharedModuleKey then
			candidateServerKeys[#candidateServerKeys + 1] = commandNameKey
		end

		local serverModules = resolveServerCommandCandidates(serverModulesByKey, candidateServerKeys)
		warnDuplicateModules("server", commandLabel, serverModules)

		local serverModule, execute, serverIssues = resolveFirstValidModule(serverModules, tryRequireCommandExecutor)
		warnModuleIssues(serverIssues)

		if serverModule == nil then
			warn(
				`[CmdrBootstrapServer] Skipping Cmdr command "{commandLabel}" because no valid server executor module was found in {serverFolder:GetFullName()}.`
			)
			continue
		end

		cmdrService:RegisterCommand(commandData, execute)
		registeredCount += 1
	end

	for _, child in sharedFolder:GetChildren() do
		if child:IsA("Folder") then
			local matchingServerFolder = serverFolder:FindFirstChild(child.Name)
			if matchingServerFolder == nil or not matchingServerFolder:IsA("Folder") then
				warn(
					`[CmdrBootstrapServer] Skipping Cmdr folder "{child:GetFullName()}" because the matching server folder is missing.`
				)
				continue
			end

			registeredCount += registerCmdrCommands(cmdrService, child, matchingServerFolder)
		end
	end

	return registeredCount
end

function CmdrBootstrapServer.Start(serviceBag: any)
	if started then
		return
	end
	started = true

	for _, player in Players:GetPlayers() do
		applyCmdrPlayerAttributes(player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		applyCmdrPlayerAttributes(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		clearCmdrPlayerAttributes(player)
	end)

	local cmdrTypes, sharedCommands, serverCommands = resolveCmdrRoots()
	local cmdrService = serviceBag:GetService(CmdrService)

	cmdrService:PromiseCmdr():Then(function(cmdr)
		cmdr:RegisterTypesIn(cmdrTypes:Clone())

		local registeredCount = registerCmdrCommands(cmdrService, sharedCommands, serverCommands)
		assert(registeredCount > 0, "[CmdrBootstrapServer] No valid Cmdr commands were registered.")
	end)
end

CmdrBootstrapServer.start = CmdrBootstrapServer.Start

return CmdrBootstrapServer
