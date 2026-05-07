--!strict

local EyeOfCthulhuController = require(script:FindFirstAncestor("game").Shared.Classes.Boss.EyeOfCthulhu)

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
