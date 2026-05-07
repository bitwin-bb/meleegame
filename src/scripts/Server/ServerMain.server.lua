--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local packageRoot = ServerScriptService:WaitForChild("AquariaBackup")
local loader = assert(ServerScriptService:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils").Parent
local loaderRequire = require(loader).bootstrapGame(packageRoot)

local ServiceBag = loaderRequire("ServiceBag")
local NevermoreSupport = loaderRequire("NevermoreSupport")
local CmdrBootstrapServer = loaderRequire("CmdrBootstrapServer")

local serviceBag = ServiceBag.new()

NevermoreSupport.setServiceBag(serviceBag)

serviceBag:GetService(loaderRequire("AquariaBackupService"))

serviceBag:Init()
serviceBag:Start()

CmdrBootstrapServer.start(serviceBag)
