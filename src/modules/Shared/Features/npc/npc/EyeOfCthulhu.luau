--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local EyeOfCthulhuController = require(gameRoot.Shared.Features.npc.npc.EyeOfCthulhu)

local EyeOfCthulhu = {}

EyeOfCthulhu.id = "EyeOfCthulhu"
EyeOfCthulhu.controller = EyeOfCthulhuController

function EyeOfCthulhu.Init(_self: typeof(EyeOfCthulhu), _service: any)
	return
end

function EyeOfCthulhu.New(...: any): any
	return EyeOfCthulhuController.new(...)
end

EyeOfCthulhu.init = EyeOfCthulhu.Init
EyeOfCthulhu.new = EyeOfCthulhu.New

return EyeOfCthulhu
