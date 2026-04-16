--!strict
--[[
	@class AquariaBackupTranslator
]]

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

return require("JSONTranslator").new("AquariaBackupTranslator", "en", {
	gameName = "AquariaBackup",
})
