--!strict
local Workspace = game:GetService("Workspace")

local WorkspaceFolders = {}

local GAME_FOLDER_NAME = "Game"

WorkspaceFolders.GAME_FOLDER_NAME = GAME_FOLDER_NAME

local managedFolders = setmetatable({}, { __mode = "k" }) :: { [Folder]: true }
local managedParents = setmetatable({}, { __mode = "k" }) :: { [Folder]: () -> Instance? }
local managedConnections = setmetatable({}, { __mode = "k" }) :: { [Folder]: { RBXScriptConnection } }
local pruneScheduled = setmetatable({}, { __mode = "k" }) :: { [Folder]: boolean }
local workspaceGameConnection: RBXScriptConnection? = nil

local function asFolder(instance: Instance?): Folder?
	if instance ~= nil and instance:IsA("Folder") then
		return instance
	end
	return nil
end

local function isFolderEmpty(folder: Folder): boolean
	return #folder:GetChildren() <= 0
end

local function findDirectFolder(parent: Instance, folderName: string): Folder?
	for _, child in parent:GetChildren() do
		if child.Name == folderName and child:IsA("Folder") then
			return child
		end
	end
	return nil
end

local function hasChildPath(folder: Folder, firstName: string, secondName: string?): boolean
	local firstChild = findDirectFolder(folder, firstName)
	if firstChild == nil then
		return false
	end
	if secondName == nil then
		return true
	end
	return findDirectFolder(firstChild, secondName) ~= nil
end

local function forgetManagedFolder(folder: Folder)
	local connections = managedConnections[folder]
	if connections ~= nil then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	managedFolders[folder] = nil
	managedParents[folder] = nil
	managedConnections[folder] = nil
	pruneScheduled[folder] = nil
end

local function isParentLocked(instance: Instance): boolean
	local currentParent = instance.Parent
	local ok = pcall(function()
		instance.Parent = currentParent
	end)
	return not ok
end

local function mergeFolderContents(target: Folder, source: Folder)
	for _, child in source:GetChildren() do
		local existing = target:FindFirstChild(child.Name)
		if existing ~= nil and existing ~= child and existing:IsA("Folder") and child:IsA("Folder") then
			mergeFolderContents(existing, child)
		else
			child.Parent = target
		end
	end
	forgetManagedFolder(source)
	source:Destroy()
end

local function resolveCanonicalGameFolder(): Folder?
	local gameFolders = {}
	for _, child in Workspace:GetChildren() do
		if child.Name == GAME_FOLDER_NAME and child:IsA("Folder") then
			table.insert(gameFolders, child)
		end
	end

	if #gameFolders <= 0 then
		return nil
	end

	local canonical = gameFolders[1]
	for _, folder in gameFolders do
		if hasChildPath(folder, "WorldGeneration", "CollisionChunks") then
			canonical = folder
			break
		end

		local canonicalHasWorldGeneration = hasChildPath(canonical, "WorldGeneration", nil)
		local folderHasWorldGeneration = hasChildPath(folder, "WorldGeneration", nil)
		local shouldUseFolder = (not canonicalHasWorldGeneration and folderHasWorldGeneration)
			or (isFolderEmpty(canonical) and not isFolderEmpty(folder))
		if shouldUseFolder then
			canonical = folder
		end
	end

	for _, folder in gameFolders do
		if folder ~= canonical and folder.Parent == Workspace then
			mergeFolderContents(canonical, folder)
		end
	end

	return canonical
end

local function resolveManagedParent(folder: Folder): Instance?
	local resolver = managedParents[folder]
	if resolver == nil then
		return nil
	end
	return resolver()
end

local function attachManagedFolder(folder: Folder)
	if isParentLocked(folder) then
		forgetManagedFolder(folder)
		return
	end

	local parent = resolveManagedParent(folder)
	if parent == nil or folder.Parent == parent then
		return
	end

	local existing = parent:FindFirstChild(folder.Name)
	if existing ~= nil and existing ~= folder then
		if existing:IsA("Folder") and isFolderEmpty(existing) then
			existing.Parent = nil
		else
			existing:Destroy()
		end
	end

	local ok = pcall(function()
		folder.Parent = parent
	end)
	if not ok then
		forgetManagedFolder(folder)
	end
end

local function pruneGameFolderIfEmpty()
	local gameFolder = resolveCanonicalGameFolder()
	if gameFolder ~= nil and isFolderEmpty(gameFolder) then
		gameFolder.Parent = nil
	end
end

local function schedulePrune(folder: Folder)
	if pruneScheduled[folder] then
		return
	end

	pruneScheduled[folder] = true
	task.defer(function()
		pruneScheduled[folder] = nil
		if managedFolders[folder] ~= true then
			return
		end
		if folder.Parent ~= nil and isFolderEmpty(folder) then
			local ok = pcall(function()
				folder.Parent = nil
			end)
			if not ok then
				forgetManagedFolder(folder)
				return
			end
			pruneGameFolderIfEmpty()
		end
	end)
end

local function manageFolder(folder: Folder, resolveParent: () -> Instance?): Folder
	if managedFolders[folder] then
		managedParents[folder] = resolveParent
		schedulePrune(folder)
		return folder
	end

	managedFolders[folder] = true
	managedParents[folder] = resolveParent
	managedConnections[folder] = {
		folder.ChildAdded:Connect(function()
			attachManagedFolder(folder)
		end),
		folder.ChildRemoved:Connect(function()
			schedulePrune(folder)
		end),
	}
	schedulePrune(folder)
	return folder
end

local function manageDescendantFolders(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("Folder") then
			manageFolder(child, function()
				return parent
			end)
			manageDescendantFolders(child)
		end
	end
end

local function ensureWorkspaceGameConnection()
	if workspaceGameConnection ~= nil then
		return
	end

	workspaceGameConnection = Workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name ~= GAME_FOLDER_NAME or not child:IsA("Folder") then
			return
		end
		task.defer(function()
			local gameFolder = resolveCanonicalGameFolder()
			if gameFolder == nil then
				return
			end
			manageFolder(gameFolder, function()
				return Workspace
			end)
			manageDescendantFolders(gameFolder)
		end)
	end)
end

local function getExistingOrCreateGameFolder(): Folder
	local existing = resolveCanonicalGameFolder()
	if existing ~= nil then
		return existing
	end

	for folder in managedFolders do
		if folder.Name == GAME_FOLDER_NAME then
			return folder
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = GAME_FOLDER_NAME
	return folder
end

function WorkspaceFolders.GetOrCreateGameFolder(): Folder
	ensureWorkspaceGameConnection()
	local folder = getExistingOrCreateGameFolder()
	manageFolder(folder, function()
		return Workspace
	end)
	manageDescendantFolders(folder)
	if folder.Parent == nil and not isFolderEmpty(folder) then
		folder.Parent = Workspace
	end
	return folder
end

function WorkspaceFolders.FindFolderInGame(folderName: string): Folder?
	ensureWorkspaceGameConnection()
	local gameFolder = resolveCanonicalGameFolder()
	if gameFolder == nil then
		return nil
	end
	manageFolder(gameFolder, function()
		return Workspace
	end)
	manageDescendantFolders(gameFolder)
	return asFolder(gameFolder:FindFirstChild(folderName))
end

function WorkspaceFolders.FindFolderInGameOrWorkspace(folderName: string): Folder?
	local inGame = WorkspaceFolders.FindFolderInGame(folderName)
	if inGame ~= nil then
		return inGame
	end
	return asFolder(Workspace:FindFirstChild(folderName))
end

function WorkspaceFolders.GetOrCreateFolderInGame(folderName: string): Folder
	local gameFolder = WorkspaceFolders.GetOrCreateGameFolder()

	local inGame = gameFolder:FindFirstChild(folderName)
	if inGame ~= nil then
		if inGame:IsA("Folder") then
			return manageFolder(inGame, function()
				return WorkspaceFolders.GetOrCreateGameFolder()
			end)
		end
		inGame:Destroy()
	end

	for folder in managedFolders do
		if folder.Name ~= folderName or folder.Parent ~= nil then
			continue
		end
		if isParentLocked(folder) then
			forgetManagedFolder(folder)
			continue
		end
		return manageFolder(folder, function()
			return WorkspaceFolders.GetOrCreateGameFolder()
		end)
	end

	local legacy = Workspace:FindFirstChild(folderName)
	if legacy ~= nil then
		if legacy:IsA("Folder") then
			local folder = manageFolder(legacy, function()
				return WorkspaceFolders.GetOrCreateGameFolder()
			end)
			if not isFolderEmpty(folder) then
				folder.Parent = gameFolder
			else
				folder.Parent = nil
			end
			return folder
		end
		legacy:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	return manageFolder(folder, function()
		return WorkspaceFolders.GetOrCreateGameFolder()
	end)
end

function WorkspaceFolders.PruneEmptyFolder(folderRaw: Instance?)
	local folder = asFolder(folderRaw)
	if folder == nil then
		return
	end
	schedulePrune(folder)
end

function WorkspaceFolders.ManageFolder(folderRaw: Instance?, parentRaw: Instance?): Folder?
	local folder = asFolder(folderRaw)
	if folder == nil then
		return nil
	end

	local fallbackParent = parentRaw
	return manageFolder(folder, function()
		if fallbackParent ~= nil then
			return fallbackParent
		end
		return folder.Parent
	end)
end

function WorkspaceFolders.PruneEmptyGameFolder()
	task.defer(pruneGameFolderIfEmpty)
end

WorkspaceFolders.getOrCreateGameFolder = WorkspaceFolders.GetOrCreateGameFolder
WorkspaceFolders.findFolderInGame = WorkspaceFolders.FindFolderInGame
WorkspaceFolders.findFolderInGameOrWorkspace = WorkspaceFolders.FindFolderInGameOrWorkspace
WorkspaceFolders.getOrCreateFolderInGame = WorkspaceFolders.GetOrCreateFolderInGame
WorkspaceFolders.pruneEmptyFolder = WorkspaceFolders.PruneEmptyFolder
WorkspaceFolders.manageFolder = WorkspaceFolders.ManageFolder
WorkspaceFolders.pruneEmptyGameFolder = WorkspaceFolders.PruneEmptyGameFolder

return WorkspaceFolders
