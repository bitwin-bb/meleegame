--!strict
local Workspace = game:GetService("Workspace")

local WorkspaceFolders = {}

local GAME_FOLDER_NAME = "Game"

WorkspaceFolders.GAME_FOLDER_NAME = GAME_FOLDER_NAME

local function asFolder(instance: Instance?): Folder?
	if instance ~= nil and instance:IsA("Folder") then
		return instance
	end
	return nil
end

function WorkspaceFolders.getOrCreateGameFolder(): Folder
	local existing = asFolder(Workspace:FindFirstChild(GAME_FOLDER_NAME))
	if existing ~= nil then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = GAME_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

function WorkspaceFolders.findFolderInGame(folderName: string): Folder?
	local gameFolder = asFolder(Workspace:FindFirstChild(GAME_FOLDER_NAME))
	if gameFolder == nil then
		return nil
	end
	return asFolder(gameFolder:FindFirstChild(folderName))
end

function WorkspaceFolders.findFolderInGameOrWorkspace(folderName: string): Folder?
	local inGame = WorkspaceFolders.findFolderInGame(folderName)
	if inGame ~= nil then
		return inGame
	end
	return asFolder(Workspace:FindFirstChild(folderName))
end

function WorkspaceFolders.getOrCreateFolderInGame(folderName: string): Folder
	local gameFolder = WorkspaceFolders.getOrCreateGameFolder()

	local inGame = gameFolder:FindFirstChild(folderName)
	if inGame ~= nil then
		if inGame:IsA("Folder") then
			return inGame
		end
		inGame:Destroy()
	end

	local legacy = Workspace:FindFirstChild(folderName)
	if legacy ~= nil then
		if legacy:IsA("Folder") then
			legacy.Parent = gameFolder
			return legacy
		end
		legacy:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = gameFolder
	return folder
end

return WorkspaceFolders
