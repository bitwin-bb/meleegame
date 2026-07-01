
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

local Transition = {}
Transition.__index = Transition

export type TransitionConfig = {
	From: string?,
	To: string?,
	Guard: ((machine: any) -> boolean)?,
	Action: ((machine: any) -> ())?,
	Priority: number?,
	AllowSelfTransition: boolean?,
}

export type Transition = typeof(setmetatable(
	{} :: {
		From: string,
		To: string,
		Guard: ((machine: any) -> boolean)?,
		Action: ((machine: any) -> ())?,
		Priority: number,
		AllowSelfTransition: boolean,
		_order: number,
	},
	Transition
))

local function CoercePriority(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.clamp(math.floor(valueRaw), -1000000, 1000000)
end

function Transition.new(configRaw: TransitionConfig): Transition
	local config: any = if typeof(configRaw) == "table" then Table.copy(configRaw :: any) else {}
	local from = if typeof(config.From) == "string" and config.From ~= "" then config.From else "*"
	local to = if typeof(config.To) == "string" and config.To ~= "" then config.To else ""

	return setmetatable({
		From = from,
		To = to,
		Guard = if typeof(config.Guard) == "function" then config.Guard else nil,
		Action = if typeof(config.Action) == "function" then config.Action else nil,
		Priority = CoercePriority(config.Priority),
		AllowSelfTransition = config.AllowSelfTransition == true,
		_order = 0,
	}, Transition)
end

function Transition.CanRun(self: Transition, machine: any): boolean
	if self.Guard == nil then
		return true
	end

	local ok, result = pcall(self.Guard, machine)
	return ok and result == true
end

function Transition.RunAction(self: Transition, machine: any)
	if self.Action == nil then
		return
	end
	pcall(self.Action, machine)
end
return Transition
