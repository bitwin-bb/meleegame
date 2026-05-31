--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")

local StateHistory = {}
StateHistory.__index = StateHistory

export type StateHistory = typeof(setmetatable(
	{} :: {
		limit: number,
		entries: { { [string]: any } },
		Recorded: any,
	},
	StateHistory
))

function StateHistory.new(limitRaw: any?): StateHistory
	return setmetatable({
		limit = if typeof(limitRaw) == "number" and limitRaw > 0 then math.floor(limitRaw) else 64,
		entries = {},
		Recorded = Signal.new(),
	}, StateHistory)
end

function StateHistory.Record(self: StateHistory, fromState: string?, toState: string?, reason: any?)
	local entry = {
		from = fromState,
		to = toState,
		reason = reason,
		at = os.clock(),
	}
	table.insert(self.entries, entry)
	while #self.entries > self.limit do
		table.remove(self.entries, 1)
	end
	self.Recorded:Fire(entry)
end

function StateHistory.GetSnapshot(self: StateHistory): { { [string]: any } }
	return Table.copy(self.entries)
end

function StateHistory.Clear(self: StateHistory)
	table.clear(self.entries)
end

function StateHistory.Destroy(self: StateHistory)
	self:Clear()
	self.Recorded:Destroy()
end

StateHistory.record = StateHistory.Record
StateHistory.getSnapshot = StateHistory.GetSnapshot
StateHistory.clear = StateHistory.Clear
StateHistory.destroy = StateHistory.Destroy

return StateHistory
