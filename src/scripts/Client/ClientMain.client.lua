--!strict
--[[
	@class ClientMain
]]
local packageRoot = game:GetService("ReplicatedStorage"):WaitForChild("AquariaBackup")
local clientBootstrapModule = packageRoot:WaitForChild("game"):WaitForChild("Client"):WaitForChild("AquariaBackupClientBootstrap")
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).bootstrapGame(packageRoot)

local serviceBag = require("ServiceBag").new()
serviceBag:Init()
serviceBag:Start()

task.spawn(require(clientBootstrapModule).start)
