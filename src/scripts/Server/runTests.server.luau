--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = ServerScriptService:FindFirstChild("AquariaBackup") or ReplicatedStorage:WaitForChild("AquariaBackup")
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
require(loaderUtils.Parent).bootstrapGame(packageRoot)

local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
local serverTests = packageRoot:WaitForChild("game"):WaitForChild("Server"):WaitForChild("Tests")

TestEZ.TestBootstrap:run({
	serverTests:WaitForChild("Specs"),
})
