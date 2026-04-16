--!strict
--[[
	@class ServerMain
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = ServerScriptService:FindFirstChild("AquariaBackup") or ReplicatedStorage:WaitForChild("AquariaBackup")
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).bootstrapGame(packageRoot)

local serviceBag = require("ServiceBag").new()
serviceBag:GetService(require("AquariaBackupService"))
serviceBag:Init()
serviceBag:Start()
