--!strict

export type EventName = string
export type EventCallback = (...any) -> ()
export type EventConnection = {
	Connected: boolean,
	Disconnect: (self: EventConnection) -> (),
}

return {}
