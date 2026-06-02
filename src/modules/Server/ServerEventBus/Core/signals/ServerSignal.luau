--!strict

local require = require(script.Parent.loader).load(assert(script:FindFirstAncestor("AquariaBackup"), "Missing AquariaBackup package root"))

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing game root")

return require("Signal")
