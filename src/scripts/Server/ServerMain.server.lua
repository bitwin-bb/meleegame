--!strict
--[[
	@class ServerMain
]]
local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_NAME = "AquariaBackup"

local packageRoot = ServerScriptService:FindFirstChild(PACKAGE_NAME)
assert(packageRoot ~= nil, `[ServerMain] Missing ServerScriptService.{PACKAGE_NAME}.`)

local gameRoot = packageRoot:FindFirstChild("game")
assert(gameRoot ~= nil, `[ServerMain] Missing game folder in {packageRoot:GetFullName()}.`)
assert(
	gameRoot:FindFirstChild("Server") ~= nil,
	`[ServerMain] Missing game.Server folder in {packageRoot:GetFullName()}.`
)
local serverBootstrapModule = gameRoot.Server:WaitForChild("AquariaBackupServerBootstrap")

local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).bootstrapGame(packageRoot)

local serviceBag = require("ServiceBag").new()
serviceBag:Init()
serviceBag:Start()

require(serverBootstrapModule).start()
