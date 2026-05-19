--!strict

--// Modules
local Class = require(script.Class)

--// Types
export type Class = Class.Class

--// Variables
local MainFolder: Folder

--// Module Setup
local System = { new = Class.new, Class = Class }

function System.CreateMainFolder()
	MainFolder = Instance.new("Folder")
	MainFolder.Name = "Part Cache"
	MainFolder.Parent = workspace
end

function System.CreateSubFolder(name: string)
	local Folder = Instance.new("Folder")
	Folder.Name = name
	Folder.Parent = MainFolder
	return Folder
end

System.CreateMainFolder() -- Run

return System
