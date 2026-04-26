--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local packageRoot = ServerScriptService:WaitForChild("AquariaBackup")
local loader = assert(ServerScriptService:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils").Parent
local require = require(loader).bootstrapGame(packageRoot)

local ServiceBag = require("ServiceBag")
local NevermoreSupport = require("NevermoreSupport")
local CmdrBootstrapServer = require("CmdrBootstrapServer")

local serviceBag = ServiceBag.new()

NevermoreSupport.setServiceBag(serviceBag)

serviceBag:GetService(require("AquariaBackupService"))

serviceBag:Init()
serviceBag:Start()

CmdrBootstrapServer.start(serviceBag)
