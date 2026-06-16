
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

export type Blackboard = {
	Set: (self: Blackboard, key: string, value: any) -> (),
	Get: (self: Blackboard, key: string) -> any?,
	Has: (self: Blackboard, key: string) -> boolean,
	Remove: (self: Blackboard, key: string) -> any?,
	Clear: (self: Blackboard) -> (),
	Destroy: (self: Blackboard) -> (),
}

export type State = {
	Name: string,
	Enter: (self: any, machine: any) -> (),
	Exit: (self: any, machine: any) -> (),
	Update: (self: any, machine: any, dt: number) -> (),
	CanEnter: ((self: any, machine: any) -> boolean)?,
	CanExit: ((self: any, machine: any) -> boolean)?,
	Destroy: ((self: any) -> ())?,
}

export type Transition = {
	From: string,
	To: string,
	Guard: ((machine: any) -> boolean)?,
	Action: ((machine: any) -> ())?,
	Priority: number,
	AllowSelfTransition: boolean,
}

export type Guard = (machine: any) -> boolean
export type Action = (machine: any) -> ()

return Table.copy({
	Version = 1,
})
