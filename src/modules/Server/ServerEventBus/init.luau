--!strict

local require = require(script.Parent.loader).load(assert(script:FindFirstAncestor("AquariaBackup"), "Missing AquariaBackup package root"))

return {
	Server = require("Server"),
	Utils = require("Utils"),
	Core = require("Core"),
}
