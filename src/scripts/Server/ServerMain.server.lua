--!strict
--[[
	@class ServerMain
]]
local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_NAME = "AquariaBackup"
local PACKAGE_LOAD_TIMEOUT_SECONDS = 10

local packageRoot = ServerScriptService:FindFirstChild(PACKAGE_NAME)
	or ServerScriptService:WaitForChild(PACKAGE_NAME, PACKAGE_LOAD_TIMEOUT_SECONDS)
assert(packageRoot ~= nil, `[ServerMain] Missing ServerScriptService.{PACKAGE_NAME}.`)

local gameRoot = packageRoot:FindFirstChild("game") or packageRoot:WaitForChild("game", PACKAGE_LOAD_TIMEOUT_SECONDS)
assert(gameRoot ~= nil, `[ServerMain] Missing game folder in {packageRoot:GetFullName()}.`)
local serverRoot = gameRoot:FindFirstChild("Server") or gameRoot:WaitForChild("Server", PACKAGE_LOAD_TIMEOUT_SECONDS)
assert(
	serverRoot ~= nil,
	`[ServerMain] Missing game.Server folder in {packageRoot:GetFullName()}.`
)
serverRoot:WaitForChild("AquariaBackupServerBootstrap", PACKAGE_LOAD_TIMEOUT_SECONDS)

local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).bootstrapGame(packageRoot)
local NevermoreSupport = require(gameRoot.Shared.Modules.Core.NevermoreSupport)
local ServerBinderSupport = require(gameRoot.Server.Binders.ServerBinderSupport)
local AquariaBackupTranslator = require(gameRoot.Shared.AquariaBackupTranslator)
local AquariaBackupService = require(gameRoot.Server.AquariaBackupService)
local CmdrBootstrapServer = require(gameRoot.Server.Cmdr.CmdrBootstrapServer)

local serviceBag = NevermoreSupport.start({
	ServerBinderSupport,
	require("CmdrService"),
	AquariaBackupTranslator,
	AquariaBackupService,
})

CmdrBootstrapServer.start(serviceBag)
