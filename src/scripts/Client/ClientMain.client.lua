--!strict
--[[
	@class ClientMain
]]
local packageRoot = game:GetService("ReplicatedStorage"):WaitForChild("AquariaBackup")
packageRoot:WaitForChild("game"):WaitForChild("Client"):WaitForChild("AquariaBackupServiceClient")
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).bootstrapGame(packageRoot)

local serviceBag = require("ServiceBag").new()
serviceBag:GetService(require("AquariaBackupServiceClient"))
serviceBag:Init()
serviceBag:Start()
