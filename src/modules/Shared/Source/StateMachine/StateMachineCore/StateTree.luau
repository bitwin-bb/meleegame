
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")

local StateTree = {}
StateTree.__index = StateTree

export type StateTree = typeof(setmetatable(
	{} :: {
		parents: { [string]: string? },
		children: { [string]: { string } },
		Registered: any,
	},
	StateTree
))

local function getPathParent(stateName: string): string?
	local lastDot = string.find(stateName, "%.[^%.]*$")
	if lastDot == nil or lastDot <= 1 then
		return nil
	end
	return string.sub(stateName, 1, lastDot - 1)
end

function StateTree.new(): StateTree
	return setmetatable({
		parents = {},
		children = {},
		Registered = Signal.new(),
	}, StateTree)
end

function StateTree.Register(self: StateTree, stateNameRaw: any, parentRaw: any?): boolean
	if typeof(stateNameRaw) ~= "string" or stateNameRaw == "" then
		return false
	end

	local parent = if typeof(parentRaw) == "string" and parentRaw ~= ""
		then parentRaw
		else getPathParent(stateNameRaw)
	self.parents[stateNameRaw] = parent
	if parent ~= nil then
		if self.children[parent] == nil then
			self.children[parent] = {}
		end
		if not table.find(self.children[parent], stateNameRaw) then
			table.insert(self.children[parent], stateNameRaw)
		end
	end
	self.Registered:Fire(stateNameRaw, parent)
	return true
end

function StateTree.GetParent(self: StateTree, stateNameRaw: any): string?
	if typeof(stateNameRaw) ~= "string" then
		return nil
	end
	return self.parents[stateNameRaw]
end

function StateTree.GetPath(self: StateTree, stateNameRaw: any): { string }
	if typeof(stateNameRaw) ~= "string" or stateNameRaw == "" then
		return {}
	end

	local out = {}
	local cursor: string? = stateNameRaw
	local guard = 0
	while cursor ~= nil and cursor ~= "" do
		guard += 1
		if guard > 1024 then
			break
		end
		table.insert(out, 1, cursor)
		cursor = self.parents[cursor]
	end
	return out
end

function StateTree.GetChildren(self: StateTree, stateNameRaw: any): { string }
	if typeof(stateNameRaw) ~= "string" then
		return {}
	end
	return Table.copy(self.children[stateNameRaw] or {})
end

function StateTree.Destroy(self: StateTree)
	table.clear(self.parents)
	table.clear(self.children)
	self.Registered:Destroy()
end
return StateTree
