--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_NAME = "AquariaBackup"

local Resolver = {}

local function findPackageContainer(): Instance
	local packageContainer = ServerScriptService:FindFirstChild(PACKAGE_NAME)
	if packageContainer ~= nil then
		return packageContainer
	end

	packageContainer = ReplicatedStorage:FindFirstChild(PACKAGE_NAME)
	if packageContainer ~= nil then
		return packageContainer
	end

	packageContainer = ReplicatedStorage:WaitForChild(PACKAGE_NAME, 5)
	if packageContainer ~= nil then
		return packageContainer
	end

	error(`Could not find the {PACKAGE_NAME} package container for Cmdr command resolution.`)
end

local function findGameRoot(): Instance
	local gameRoot = findPackageContainer():FindFirstChild("game")
	if gameRoot == nil then
		error(`Could not find the "game" folder inside the {PACKAGE_NAME} package container.`)
	end

	return gameRoot
end

function Resolver.RequireFromGameRoot(...: string): any
	local current = findGameRoot()
	for index = 1, select("#", ...) do
		local segment = select(index, ...)
		local nextChild = current:FindFirstChild(segment)
		if nextChild == nil then
			error(`Could not resolve Cmdr dependency segment "{segment}".`)
		end

		current = nextChild
	end

	return require(current)
end

Resolver.requireFromGameRoot = Resolver.RequireFromGameRoot

return Resolver
