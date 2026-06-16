
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local Sensor = {}
Sensor.__index = Sensor

export type Sensor = typeof(setmetatable(
	{} :: {
		Name: string,
		maid: any,
		update: ((any, any, number) -> ())?,
		destroyed: boolean,
	},
	Sensor
))

function Sensor.new(configRaw: any?): Sensor
	local config = if typeof(configRaw) == "table" then Table.copy(configRaw) else {}
	return setmetatable({
		Name = if typeof(config.Name) == "string" and config.Name ~= "" then config.Name else "Sensor",
		maid = Maid.new(),
		update = if typeof(config.Update) == "function" then config.Update else nil,
		destroyed = false,
	}, Sensor)
end

function Sensor.Update(self: Sensor, agent: any, dtRaw: any)
	if self.destroyed or self.update == nil then
		return
	end
	local dt = if typeof(dtRaw) == "number" and dtRaw == dtRaw then math.max(0, dtRaw) else 0
	self.update(self, agent, dt)
end

function Sensor.Destroy(self: Sensor)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

Sensor.updateSensor = Sensor.Update
Sensor.destroy = Sensor.Destroy

return Sensor
