--!strict

local State = {}
State.__index = State

export type StateSnapshot = {
	enabled: boolean,
	mode: string,
	reason: string,
	hasTarget: boolean,
	hasOverride: boolean,
	hasDirectCameraOverride: boolean,
	hasTemporaryOverride: boolean,
	subjectKind: string?,
	updatedAt: number,
}

export type State = typeof(setmetatable(
	{} :: {
		enabled: boolean,
		snapshot: StateSnapshot,
	},
	State
))

local function createSnapshot(): StateSnapshot
	return {
		enabled = false,
		mode = "Disabled",
		reason = "disabled",
		hasTarget = false,
		hasOverride = false,
		hasDirectCameraOverride = false,
		hasTemporaryOverride = false,
		subjectKind = nil,
		updatedAt = 0,
	}
end

local function cloneSnapshot(snapshot: StateSnapshot): StateSnapshot
	return {
		enabled = snapshot.enabled,
		mode = snapshot.mode,
		reason = snapshot.reason,
		hasTarget = snapshot.hasTarget,
		hasOverride = snapshot.hasOverride,
		hasDirectCameraOverride = snapshot.hasDirectCameraOverride,
		hasTemporaryOverride = snapshot.hasTemporaryOverride,
		subjectKind = snapshot.subjectKind,
		updatedAt = snapshot.updatedAt,
	}
end

function State.New(): State
	return setmetatable({
		enabled = false,
		snapshot = createSnapshot(),
	}, State)
end

function State.SetEnabled(self: State, enabledRaw: any)
	self.enabled = enabledRaw == true
end

function State.Resolve(self: State, contextRaw: any): StateSnapshot
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	local target = if typeof((context :: any).target) == "table" then (context :: any).target else nil
	local override = if typeof((context :: any).override) == "table" then (context :: any).override else nil
	local hasTarget = target ~= nil and typeof((target :: any).position) == "Vector3"
	local hasOverride = override ~= nil
	local hasDirectCameraOverride = hasOverride
		and (
			typeof((override :: any).cameraCFrame) == "CFrame" or typeof((override :: any).cameraPosition) == "Vector3"
		)
	local hasTemporaryOverride = target ~= nil and (target :: any).kind == "TemporaryOverride"
	local subjectKind = if target ~= nil and typeof((target :: any).kind) == "string" then (target :: any).kind else nil

	local mode = "Disabled"
	local reason = "disabled"
	if self.enabled then
		if hasDirectCameraOverride then
			mode = "DirectOverride"
			reason = if typeof((override :: any).kind) == "string" then (override :: any).kind else "direct_override"
		elseif hasOverride then
			mode = "Override"
			reason = if typeof((override :: any).kind) == "string" then (override :: any).kind else "override"
		elseif hasTemporaryOverride then
			mode = "TemporaryOverride"
			reason = "temporary_override"
		elseif hasTarget then
			mode = "Follow"
			reason = if subjectKind ~= nil then subjectKind else "target"
		else
			mode = "AwaitingTarget"
			reason = "target_missing"
		end
	end

	self.snapshot = {
		enabled = self.enabled,
		mode = mode,
		reason = reason,
		hasTarget = hasTarget,
		hasOverride = hasOverride,
		hasDirectCameraOverride = hasDirectCameraOverride,
		hasTemporaryOverride = hasTemporaryOverride,
		subjectKind = subjectKind,
		updatedAt = os.clock(),
	}
	return self:getSnapshot()
end

function State.GetSnapshot(self: State): StateSnapshot
	return cloneSnapshot(self.snapshot)
end

State.new = State.New
State.setEnabled = State.SetEnabled
State.resolve = State.Resolve
State.getSnapshot = State.GetSnapshot

return State
