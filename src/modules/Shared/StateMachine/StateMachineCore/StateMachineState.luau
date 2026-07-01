
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

local State = {}
State.__index = State

export type State = typeof(setmetatable(
	{} :: {
		Name: string,
		_data: { [string]: any },
	},
	State
))

export type StateConfig = {
	Name: string?,
	Enter: ((self: any, machine: any) -> ())?,
	Exit: ((self: any, machine: any) -> ())?,
	Update: ((self: any, machine: any, dt: number) -> ())?,
	CanEnter: ((self: any, machine: any) -> boolean)?,
	CanExit: ((self: any, machine: any) -> boolean)?,
	Destroy: ((self: any) -> ())?,
}

function State.new(configRaw: StateConfig?): State
	local config: any = if typeof(configRaw) == "table" then Table.copy(configRaw :: any) else {}
	local self = setmetatable({
		Name = if typeof(config.Name) == "string" and config.Name ~= "" then config.Name else "State",
		_data = config,
	}, State)

	return self
end

function State.Enter(self: State, machine: any)
	local callback = self._data.Enter
	if typeof(callback) == "function" then
		callback(self, machine)
	end
end

function State.Exit(self: State, machine: any)
	local callback = self._data.Exit
	if typeof(callback) == "function" then
		callback(self, machine)
	end
end

function State.Update(self: State, machine: any, dt: number)
	local callback = self._data.Update
	if typeof(callback) == "function" then
		callback(self, machine, dt)
	end
end

function State.CanEnter(self: State, machine: any): boolean
	local callback = self._data.CanEnter
	if typeof(callback) ~= "function" then
		return true
	end
	return callback(self, machine) == true
end

function State.CanExit(self: State, machine: any): boolean
	local callback = self._data.CanExit
	if typeof(callback) ~= "function" then
		return true
	end
	return callback(self, machine) == true
end

function State.Destroy(self: State)
	local callback = self._data.Destroy
	if typeof(callback) == "function" then
		callback(self)
	end
	table.clear(self._data)
end
return State
