--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local EffectHandler = {}
EffectHandler.__index = EffectHandler

export type EffectHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		Emitted: any,
	},
	EffectHandler
))

function EffectHandler.new(): EffectHandler
	local self = setmetatable({
		maid = Maid.new(),
		Emitted = Signal.new(),
	}, EffectHandler)

	self.maid:GiveTask(self.Emitted)
	return self
end

function EffectHandler.Emit(self: EffectHandler, effectNameRaw: any, payload: any?)
	if typeof(effectNameRaw) ~= "string" or effectNameRaw == "" then
		return
	end
	self.Emitted:Fire(effectNameRaw, payload)
end

function EffectHandler.Destroy(self: EffectHandler)
	self.maid:DoCleaning()
end

EffectHandler.emit = EffectHandler.Emit
EffectHandler.destroy = EffectHandler.Destroy

return EffectHandler
