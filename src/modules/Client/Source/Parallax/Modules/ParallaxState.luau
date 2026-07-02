local require = require(script.Parent.loader).load(script)

local Math = require("Math")

local Profile = require("ParallaxProfiles")

local State = {}
State.__index = State

local Styles = Profile.Styles

local CLOSE_STYLE_COUNT = 9
local FAR_GROUP_COUNT = 6
local DEFAULT_BG_DELAY_SECONDS = 1
local DEFAULT_TRAN_SPEED = 0.05

local FarGroups = table.freeze({
	Default = 0,
	Evil = 1,
	Desert = 2,
	Ocean = 3,
	Snow = 4,
	Crimson = 5,
	Mushroom = 6,
})

local function createAlphaTable(maxIndex: number, activeIndex: number): { [number]: number }
	local values: { [number]: number } = {}
	for index = 0, maxIndex do
		values[index] = if index == activeIndex then 1 else 0
	end
	return values
end

local function GetFarGroup(style: number): number
	if style == Styles.Desert then
		return FarGroups.Desert
	end
	if style == Styles.Corruption or style == Styles.DesertHybrid or style == Styles.Hallow then
		return FarGroups.Evil
	end
	if style == Styles.Ocean then
		return FarGroups.Ocean
	end
	if style == Styles.Snow then
		return FarGroups.Snow
	end
	if style == Styles.Crimson then
		return FarGroups.Crimson
	end
	if style == Styles.Mushroom then
		return FarGroups.Mushroom
	end
	return FarGroups.Default
end

local function fadeAlphaTable(values: { [number]: number }, targetIndex: number, maxIndex: number, alpha: number)
	for index = 0, maxIndex do
		local target = if index == targetIndex then 1 else 0
		values[index] = Math.lerp(values[index] or 0, target, alpha)
		if math.abs(values[index] - target) <= 0.001 then
			values[index] = target
		end
	end
end

local function createState()
	local self = setmetatable({}, State)
	self.bgStyle = Styles.Overworld
	self.targetBgStyle = Styles.Overworld
	self.pendingBgStyle = nil
	self.bgDelay = 0
	self.bgDelaySeconds = DEFAULT_BG_DELAY_SECONDS
	self.tranSpeed = DEFAULT_TRAN_SPEED
	self.bgAlpha = createAlphaTable(CLOSE_STYLE_COUNT, Styles.Overworld)
	self.bgAlpha2 = createAlphaTable(FAR_GROUP_COUNT, FarGroups.Default)
	return self
end

function State.Update(self: State, targetStyle: number, dt: number)
	local GotTargetStyle = if typeof(targetStyle) == "number"
		then math.clamp(math.floor(targetStyle), 0, CLOSE_STYLE_COUNT)
		else Styles.Overworld
	local deltaSeconds = if typeof(dt) == "number" and Math.isFinite(dt) then math.max(dt, 0) else 0

	self.targetBgStyle = GotTargetStyle
	if GotTargetStyle ~= self.bgStyle then
		if self.pendingBgStyle ~= GotTargetStyle then
			self.pendingBgStyle = GotTargetStyle
			self.bgDelay = self.bgDelaySeconds
		else
			self.bgDelay = math.max(self.bgDelay - deltaSeconds, 0)
			if self.bgDelay <= 0 then
				self.bgStyle = GotTargetStyle
				self.pendingBgStyle = nil
			end
		end
	else
		self.pendingBgStyle = nil
		self.bgDelay = 0
	end

	local alpha = math.clamp(self.tranSpeed * deltaSeconds * 60, 0, 1)
	fadeAlphaTable(self.bgAlpha, self.bgStyle, CLOSE_STYLE_COUNT, alpha)
	fadeAlphaTable(self.bgAlpha2, GetFarGroup(self.bgStyle), FAR_GROUP_COUNT, alpha)
end

function State.GetStyleAlpha(self: State, style: number): number
	local GotStyle = if typeof(style) == "number"
		then math.clamp(math.floor(style), 0, CLOSE_STYLE_COUNT)
		else Styles.Overworld
	return math.clamp(self.bgAlpha[GotStyle] or 0, 0, 1)
end

function State.GetFarAlpha(self: State, groupIndex: number): number
	local GotGroup = GetFarGroup(groupIndex)
	return math.clamp(self.bgAlpha2[GotGroup] or 0, 0, 1)
end

State.new = createState



export type State = typeof(setmetatable(
	{} :: {
		bgStyle: number,
		targetBgStyle: number,
		pendingBgStyle: number?,
		bgDelay: number,
		bgDelaySeconds: number,
		tranSpeed: number,
		bgAlpha: { [number]: number },
		bgAlpha2: { [number]: number },
	},
	{} :: typeof({ __index = State })
))

return State
