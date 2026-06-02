--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Runtime")
local Maid = packages.Maid
local Table = packages.Table

local ActionRunner = {}
ActionRunner.__index = ActionRunner

export type ActionRunner = typeof(setmetatable(
	{} :: {
		maid: any,
		started: { [any]: boolean },
		destroyed: boolean,
	},
	ActionRunner
))

local function callMethod(action: any, methodNames: { string }, ...): (boolean, any?)
	if typeof(action) ~= "table" then
		return false, nil
	end
	for _, methodName in methodNames do
		local method = action[methodName]
		if typeof(method) == "function" then
			local ok, result = pcall(method, action, ...)
			return ok, result
		end
	end
	return true, nil
end

function ActionRunner.new(): ActionRunner
	return setmetatable({
		maid = Maid.new(),
		started = {},
		destroyed = false,
	}, ActionRunner)
end

function ActionRunner.CanRun(self: ActionRunner, action: any, agent: any): boolean
	if self.destroyed then
		return false
	end
	local ok, result = callMethod(action, { "CanRun", "canRunAction", "canRun" }, agent)
	return ok and (result == nil or result == true)
end

function ActionRunner.Start(self: ActionRunner, action: any, agent: any): boolean
	if self.destroyed or self.started[action] then
		return not self.destroyed
	end
	if not self:CanRun(action, agent) then
		return false
	end
	local ok = callMethod(action, { "Start", "startAction", "start" }, agent)
	if not ok then
		return false
	end
	self.started[action] = true
	return true
end

function ActionRunner.Update(self: ActionRunner, action: any, agent: any, dtRaw: any): boolean
	if self.destroyed then
		return false
	end
	local dt = if typeof(dtRaw) == "number" and dtRaw == dtRaw then math.max(0, dtRaw) else 0
	local ok = callMethod(action, { "Update", "updateAction", "update" }, agent, dt)
	return ok
end

function ActionRunner.IsFinished(self: ActionRunner, action: any, agent: any): boolean
	if self.destroyed then
		return true
	end
	local ok, result = callMethod(action, { "IsFinished", "isFinishedAction", "isFinished" }, agent)
	return ok and (result == nil or result == true)
end

function ActionRunner.Cancel(self: ActionRunner, action: any, agent: any)
	if self.destroyed then
		return
	end
	callMethod(action, { "Cancel", "cancelAction", "cancel" }, agent)
	self.started[action] = nil
end

function ActionRunner.Reset(self: ActionRunner)
	table.clear(self.started)
end

function ActionRunner.Destroy(self: ActionRunner)
	if self.destroyed then
		return
	end
	self.destroyed = true
	table.clear(self.started)
	self.maid:DoCleaning()
end

ActionRunner.copy = Table.copy
ActionRunner.canRun = ActionRunner.CanRun
ActionRunner.start = ActionRunner.Start
ActionRunner.update = ActionRunner.Update
ActionRunner.isFinished = ActionRunner.IsFinished
ActionRunner.cancel = ActionRunner.Cancel
ActionRunner.reset = ActionRunner.Reset
ActionRunner.destroy = ActionRunner.Destroy

return ActionRunner
