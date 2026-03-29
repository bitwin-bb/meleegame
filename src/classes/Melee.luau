--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

local DEFAULT_START_EVENTS = { "startSwing", "StartSwing", "swingStart", "SwingStart" }
local DEFAULT_END_EVENTS = { "endSwing", "EndSwing", "swingEnd", "SwingEnd" }
local DEFAULT_PROJECTILE_EVENTS = { "projectile", "Projectile", "spawnProjectile", "SpawnProjectile" }

local DEFAULT_COOLDOWN = 0.2
local DEFAULT_TIMEOUT = 0.5
local DEFAULT_TIMEOUT_PADDING = 0.08
local DEFAULT_SLASH_RESET_COOLDOWN = 0.9
local DEFAULT_STANCE_DELAY = 1.35

local NAMED_ANIMATION_STATE_ALIASES: { [string]: { string } } = {
	Equip = { "equip", "draw", "equipanimation", "drawanimation" },
	Idle = { "idle", "weaponidle", "holdidle", "idleanimation" },
	Unequip = { "unequip", "holster", "sheath", "sheathe", "unequipanimation" },
	StanceTransition = {
		"stancetransition",
		"transitiontostance",
		"enterstance",
		"stancestart",
		"stancetransitionanimation",
	},
	StanceIdle = { "stanceidle", "stance", "combatidle", "readyidle", "stanceidleanimation" },
}
local NAMED_ANIMATION_TOKEN_TO_STATE: { [string]: string } = {}

for stateName, aliases in NAMED_ANIMATION_STATE_ALIASES do
	for _, alias in aliases do
		NAMED_ANIMATION_TOKEN_TO_STATE[alias] = stateName
	end
end

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeEventName(nameRaw: any): string
	return string.lower(trim(nameRaw))
end

local function normalizeToken(valueRaw: any): string
	local normalized = string.lower(trim(valueRaw))
	if normalized == "" then
		return ""
	end
	return string.gsub(normalized, "[%s_%-]+", "")
end

local function normalizeNamedAnimationStateKey(nameRaw: any): string?
	local token = normalizeToken(nameRaw)
	if token == "" then
		return nil
	end
	return NAMED_ANIMATION_TOKEN_TO_STATE[token]
end

local function toBool(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function toNumber(valueRaw: any, fallback: number, minValue: number?, maxValue: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minValue ~= nil and value < minValue then
		value = minValue
	end
	if maxValue ~= nil and value > maxValue then
		value = maxValue
	end
	return value
end

local function toArray(valueRaw: any, fallback: { string }): { string }
	local out = {}
	if typeof(valueRaw) == "table" then
		for _, entry in valueRaw do
			if typeof(entry) == "string" then
				local text = trim(entry)
				if text ~= "" then
					table.insert(out, text)
				end
			end
		end
		return out
	end
	if typeof(valueRaw) == "string" then
		local text = trim(valueRaw)
		if text ~= "" then
			table.insert(out, text)
		end
		return out
	end
	for _, entry in fallback do
		table.insert(out, entry)
	end
	return out
end

local function normalizeAnimationId(idRaw: any): string?
	if typeof(idRaw) == "number" then
		if idRaw <= 0 or idRaw ~= idRaw then
			return nil
		end
		return "rbxassetid://" .. tostring(math.floor(idRaw))
	end

	if typeof(idRaw) ~= "string" then
		return nil
	end

	local text = trim(idRaw)
	if text == "" then
		return nil
	end

	if string.find(text, "rbxassetid://", 1, true) == 1 then
		return text
	end

	local digits = string.match(text, "^%d+$")
	if digits ~= nil then
		return "rbxassetid://" .. digits
	end

	return text
end

local function normalizeAnimationMode(modeRaw: any): string
	local mode = string.lower(trim(modeRaw))
	if mode == "sequence" or mode == "sequential" or mode == "ordered" then
		return "Sequence"
	end
	return "Sequence"
end

local function resolveClipAnimationId(clipRaw: { [string]: any }): string?
	local animationId = normalizeAnimationId(clipRaw.id)
	if animationId ~= nil then
		return animationId
	end

	animationId = normalizeAnimationId(clipRaw.animationId)
	if animationId ~= nil then
		return animationId
	end

	animationId = normalizeAnimationId(clipRaw.AnimationId)
	if animationId ~= nil then
		return animationId
	end

	animationId = normalizeAnimationId(clipRaw.assetId)
	if animationId ~= nil then
		return animationId
	end

	animationId = normalizeAnimationId(clipRaw.animId)
	if animationId ~= nil then
		return animationId
	end

	animationId = normalizeAnimationId(clipRaw.animation)
	if animationId ~= nil then
		return animationId
	end

	return nil
end

local function isAnimationClipTable(valueRaw: any): boolean
	if typeof(valueRaw) ~= "table" then
		return false
	end

	local value = valueRaw :: { [string]: any }
	return value.id ~= nil
		or value.animation ~= nil
		or value.animationId ~= nil
		or value.AnimationId ~= nil
		or value.assetId ~= nil
		or value.animId ~= nil
end

local function resolveAnimationConfigClips(configRaw: any): any
	if configRaw == nil then
		return {}
	end

	if typeof(configRaw) ~= "table" then
		return { configRaw }
	end

	local config = configRaw :: { [string]: any }
	if config.clips ~= nil then
		return config.clips
	end
	if isAnimationClipTable(config) then
		return { config }
	end
	return configRaw
end

local function normalizeNamedAnimationClip(clipRaw: any, fallbackName: string, defaultLooped: boolean?): { [string]: any }?
	local clipTable = if typeof(clipRaw) == "table" then clipRaw else { animation = clipRaw }
	if typeof(clipTable) ~= "table" then
		return nil
	end

	local animation = if typeof(clipTable.animation) == "Instance" and clipTable.animation:IsA("Animation")
		then clipTable.animation
		else nil
	if animation == nil and typeof(clipRaw) == "Instance" and clipRaw:IsA("Animation") then
		animation = clipRaw
	end

	local animationId = resolveClipAnimationId(clipTable)
	if animationId == nil and animation ~= nil then
		animationId = normalizeAnimationId(animation.AnimationId)
	end

	if animation == nil and animationId == nil then
		return nil
	end

	local clip = {
		name = trim(clipTable.name) ~= "" and trim(clipTable.name) or fallbackName,
		animation = animation,
		id = animationId,
		looped = if typeof(clipTable.looped) == "boolean" then clipTable.looped else defaultLooped,
		priority = if typeof(clipTable.priority) == "EnumItem" then clipTable.priority else nil,
		speed = if typeof(clipTable.speed) == "number" then clipTable.speed else nil,
		weight = if typeof(clipTable.weight) == "number" then clipTable.weight else nil,
		fadeTime = if typeof(clipTable.fadeTime) == "number" then clipTable.fadeTime else nil,
		duration = if typeof(clipTable.duration) == "number" then clipTable.duration else nil,
	}
	return clip
end

local function mergeNamedAnimationStateClips(
	target: { [string]: { [string]: any } },
	sourceRaw: any,
	defaultLoopedByState: { [string]: boolean }
)
	if typeof(sourceRaw) ~= "table" then
		return
	end

	for key, value in sourceRaw do
		local stateKey = normalizeNamedAnimationStateKey(key)
		if stateKey == nil or target[stateKey] ~= nil then
			continue
		end

		local clip = normalizeNamedAnimationClip(value, stateKey, defaultLoopedByState[stateKey])
		if clip ~= nil then
			target[stateKey] = clip
		end
	end
end

local function resolveNamedAnimationStateClips(configRaw: any): { [string]: { [string]: any } }
	local clipsByState: { [string]: { [string]: any } } = {}
	local defaultLoopedByState = {
		Idle = true,
		StanceIdle = true,
	}

	if typeof(configRaw) ~= "table" then
		return clipsByState
	end

	local config = configRaw :: { [string]: any }
	mergeNamedAnimationStateClips(clipsByState, config.namedAnimations, defaultLoopedByState)
	mergeNamedAnimationStateClips(clipsByState, config.named, defaultLoopedByState)
	mergeNamedAnimationStateClips(clipsByState, config, defaultLoopedByState)
	return clipsByState
end

local function createAnimatorFromHumanoid(humanoid: Humanoid?): Animator?
	if humanoid == nil then
		return nil
	end
	local existing = humanoid:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Name = "Animator"
	animator.Parent = humanoid
	return animator
end

local function createAnimatorFromCharacter(character: Model?): Animator?
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	return createAnimatorFromHumanoid(humanoid)
end

local function buildEventSet(eventsRaw: any, defaults: { string }): ({ [string]: boolean }, { string })
	local names = toArray(eventsRaw, defaults)
	local eventSet = {}
	local markerSet = {}
	local markers = {}

	local function pushMarker(nameRaw: any)
		if typeof(nameRaw) ~= "string" then
			return
		end
		local value = trim(nameRaw)
		if value == "" or markerSet[value] then
			return
		end
		markerSet[value] = true
		table.insert(markers, value)
	end

	for _, name in names do
		local normalized = normalizeEventName(name)
		if normalized ~= "" then
			eventSet[normalized] = true
			pushMarker(name)
			pushMarker(string.lower(name))
			pushMarker(string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2))
		end
	end

	return eventSet, markers
end

local function mergeUniqueStringLists(...: { string }): { string }
	local out = {}
	local seen = {}
	for _, list in { ... } do
		for _, name in list do
			local text = trim(name)
			if text ~= "" and not seen[text] then
				seen[text] = true
				table.insert(out, text)
			end
		end
	end
	return out
end

local AnimationController = {}
AnimationController.__index = AnimationController

function AnimationController.new(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		janitor = Janitor.new(),
		trackJanitor = Janitor.new(),
		signals = {
			markerReached = Signal.new(),
			keyframeReached = Signal.new(),
			trackStopped = Signal.new(),
		},
		animator = nil :: Animator?,
		clips = {},
		mode = normalizeAnimationMode(config.mode),
		random = if typeof(config.random) == "Random" then config.random else Random.new(),
		sequenceIndex = 0,
		markers = toArray(config.markerNames, {}),
		trackCache = {},
	}, AnimationController)

	self.janitor:GiveChore(self.trackJanitor)
	self.janitor:GiveChore(function()
		for _, signalObject in self.signals do
			local signalObjectTyped = signalObject :: SignalObject
			signalObjectTyped:Destroy()
		end
	end)

	self:setClips(resolveAnimationConfigClips(configRaw))
	return self
end

function AnimationController:setAnimator(animatorRaw: any)
	local animator = if typeof(animatorRaw) == "Instance" and animatorRaw:IsA("Animator") then animatorRaw else nil
	if self.animator == animator then
		return
	end
	self.animator = animator
	self:clearTracks()
end

function AnimationController:setMode(modeRaw: any)
	self.mode = normalizeAnimationMode(modeRaw)
end

function AnimationController:resetSequence()
	self.sequenceIndex = 0
end

function AnimationController:setMarkers(markersRaw: any)
	self.markers = toArray(markersRaw, {})
	self:clearTracks()
end

function AnimationController:getMarkers(): { string }
	local out = {}
	for _, marker in self.markers do
		table.insert(out, marker)
	end
	return out
end

function AnimationController:setClips(clipsRaw: any)
	local clips = {}
	if typeof(clipsRaw) ~= "table" then
		clipsRaw = if clipsRaw == nil then {} else { clipsRaw }
	end

	local fallbackIndex = 0
	for i, clipRaw in clipsRaw do
		fallbackIndex += 1
		local fallbackName = if typeof(i) == "number" and i == i
			then ("Swing_%d"):format(math.floor(i))
			else ("Swing_%d"):format(fallbackIndex)
		local clipTable = if typeof(clipRaw) == "table" then clipRaw else { id = clipRaw }
		if typeof(clipTable) ~= "table" then
			continue
		end

		local animation = if typeof(clipTable.animation) == "Instance" and clipTable.animation:IsA("Animation")
			then clipTable.animation
			else nil
		local animationId = resolveClipAnimationId(clipTable)
		if animation == nil and typeof(clipRaw) == "Instance" and clipRaw:IsA("Animation") then
			animation = clipRaw
			animationId = normalizeAnimationId(clipRaw.AnimationId)
		end

		if animation ~= nil or animationId ~= nil then
			table.insert(clips, {
				name = trim(clipTable.name) ~= "" and trim(clipTable.name) or fallbackName,
				animation = animation,
				id = animationId,
				looped = if typeof(clipTable.looped) == "boolean" then clipTable.looped else nil,
				priority = if typeof(clipTable.priority) == "EnumItem" then clipTable.priority else nil,
				speed = if typeof(clipTable.speed) == "number" then clipTable.speed else nil,
				weight = if typeof(clipTable.weight) == "number" then clipTable.weight else nil,
				fadeTime = if typeof(clipTable.fadeTime) == "number" then clipTable.fadeTime else nil,
				cooldown = if typeof(clipTable.cooldown) == "number" then clipTable.cooldown else nil,
				duration = if typeof(clipTable.duration) == "number" then clipTable.duration else nil,
			})
		end
	end
	self.clips = clips
	self.sequenceIndex = 0
	self:clearTracks()
end

function AnimationController:clearTracks()
	for _, track in self.trackCache do
		pcall(function()
			track:Stop(0)
		end)
	end
	self.trackJanitor:Clean()
	self.trackCache = {}
end

function AnimationController:loadTrack(index: number): AnimationTrack?
	if self.trackCache[index] ~= nil then
		return self.trackCache[index]
	end
	if self.animator == nil then
		return nil
	end
	local clip = self.clips[index]
	if clip == nil then
		return nil
	end

	local anim = clip.animation
	local destroyAnim = false
	if anim == nil then
		if clip.id == nil then
			return nil
		end
		local generated = Instance.new("Animation")
		generated.Name = clip.name
		generated.AnimationId = clip.id
		anim = generated
		destroyAnim = true
	end

	local ok, trackOrErr = pcall(function()
		return self.animator:LoadAnimation(anim :: Animation)
	end)
	if destroyAnim and anim ~= nil then
		anim:Destroy()
	end
	if not ok then
		warn("[Melee] Failed to load animation:", tostring(trackOrErr))
		return nil
	end

	local track = trackOrErr :: AnimationTrack
	if clip.looped ~= nil then
		track.Looped = clip.looped
	end
	if clip.priority ~= nil then
		track.Priority = clip.priority
	end

	for _, markerName in self.markers do
		self.trackJanitor:GiveChore(track:GetMarkerReachedSignal(markerName):Connect(function(param: string)
			self.signals.markerReached:Fire(markerName, param, track, clip, index)
		end))
	end

	self.trackJanitor:GiveChore(track.KeyframeReached:Connect(function(keyframeName: string)
		self.signals.keyframeReached:Fire(keyframeName, nil, track, clip, index)
	end))

	self.trackJanitor:GiveChore(track.Stopped:Connect(function()
		self.signals.trackStopped:Fire(track, clip, index)
	end))

	self.trackCache[index] = track
	return track
end

function AnimationController:pickClipIndex(): number?
	if #self.clips <= 0 then
		return nil
	end
	if self.mode == "Random" then
		return self.random:NextInteger(1, #self.clips)
	end
	self.sequenceIndex += 1
	if self.sequenceIndex > #self.clips then
		self.sequenceIndex = 1
	end
	return self.sequenceIndex
end

function AnimationController:playNext(playbackRaw: any): { [string]: any }?
	local index = self:pickClipIndex()
	if index == nil then
		return nil
	end

	local track = self:loadTrack(index)
	if track == nil then
		return nil
	end

	local clip = self.clips[index]
	local playback = if typeof(playbackRaw) == "table" then playbackRaw else {}

	for _, otherTrack in self.trackCache do
		if otherTrack ~= track and otherTrack.IsPlaying then
			pcall(function()
				otherTrack:Stop(toNumber(playback.stopFadeTime, 0.04, 0, nil))
			end)
		end
	end

	local fadeTime = toNumber(playback.fadeTime, clip.fadeTime or 0.06, 0, nil)
	local weight = toNumber(playback.weight, clip.weight or 1, 0, nil)
	local speed = toNumber(playback.speed, clip.speed or 1, 0.01, nil)

	local ok, err = pcall(function()
		track:Play(fadeTime, weight, speed)
	end)
	if not ok then
		warn("[Melee] Failed to play animation:", tostring(err))
		return nil
	end

	return {
		track = track,
		clip = clip,
		index = index,
	}
end

function AnimationController:stopAll(fadeTimeRaw: any)
	local fadeTime = toNumber(fadeTimeRaw, 0.06, 0, nil)
	for _, track in self.trackCache do
		pcall(function()
			track:Stop(fadeTime)
		end)
	end
end

function AnimationController:destroy()
	self:clearTracks()
	self.janitor:Destroy()
end

function AnimationController:Destroy()
	self:destroy()
end

local Melee = {}
Melee.__index = Melee
Melee.AnimationController = AnimationController

function Melee.new(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local projectile = if typeof(config.projectile) == "table" then config.projectile else {}

	local startSet, startMarkers = buildEventSet(config.startSwingEvents, DEFAULT_START_EVENTS)
	local endSet, endMarkers = buildEventSet(config.endSwingEvents, DEFAULT_END_EVENTS)
	local projectileSet, projectileMarkers = buildEventSet(projectile.markerNames, DEFAULT_PROJECTILE_EVENTS)
	local extraMarkers = toArray(config.trackedMarkerNames, {})

	local animationConfig = config.animations
	local controller = AnimationController.new(animationConfig)
	local namedAnimationStateClips = resolveNamedAnimationStateClips(animationConfig)
	local hasStanceNamedAnimations = namedAnimationStateClips.StanceTransition ~= nil or namedAnimationStateClips.StanceIdle ~= nil

	local stanceConfig = {}
	if typeof(animationConfig) == "table" and typeof((animationConfig :: any).stance) == "table" then
		stanceConfig = (animationConfig :: any).stance
	end
	local stanceEnabled = toBool(
		if config.stanceEnabled ~= nil
			then config.stanceEnabled
			else if (animationConfig :: any) ~= nil and typeof(animationConfig) == "table"
				then ((animationConfig :: any).stanceEnabled or (stanceConfig :: any).enabled)
				else nil,
		hasStanceNamedAnimations
	)
	local stanceDelay = toNumber(
		if config.stanceDelay ~= nil
			then config.stanceDelay
			else if (animationConfig :: any) ~= nil and typeof(animationConfig) == "table"
				then ((animationConfig :: any).stanceDelay or (animationConfig :: any).weaponStanceDelay or (stanceConfig :: any).delay)
				else nil,
		DEFAULT_STANCE_DELAY,
		0.05,
		nil
	)
	local namedAnimationPlaybackEnabled = toBool(config.namedAnimationPlaybackEnabled, true)

	local mergedMarkers = mergeUniqueStringLists(controller:getMarkers(), startMarkers, endMarkers, projectileMarkers, extraMarkers)
	controller:setMarkers(mergedMarkers)

	local trackedKeyframes = {}
	for _, name in toArray(config.trackedKeyframeNames, {}) do
		local normalized = normalizeEventName(name)
		if normalized ~= "" then
			trackedKeyframes[normalized] = true
		end
	end

	local self = setmetatable({
		janitor = Janitor.new(),
		toolJanitor = Janitor.new(),
		presentationJanitor = Janitor.new(),
		namedTrackJanitor = Janitor.new(),
		controller = controller,
		signals = {
			attackRequested = Signal.new(),
			attackStarted = Signal.new(),
			swingStarted = Signal.new(),
			swingEnded = Signal.new(),
			attackFinished = Signal.new(),
			animationEvent = Signal.new(),
			projectileFired = Signal.new(),
			inputHeldChanged = Signal.new(),
			enabledChanged = Signal.new(),
		},
		callbacks = if typeof(config.callbacks) == "table" then config.callbacks else {},
		startEventSet = startSet,
		endEventSet = endSet,
		projectileEventSet = projectileSet,
		trackedKeyframes = trackedKeyframes,
		trackAllKeyframes = toBool(config.trackAllKeyframes, false),
		enabled = toBool(config.enabled, true),
		autoRepeat = toBool(config.autoRepeatWhileHeld, true),
		cooldown = toNumber(config.cooldown, DEFAULT_COOLDOWN, 0, nil),
		slashResetCooldown = toNumber(config.slashResetCooldown, DEFAULT_SLASH_RESET_COOLDOWN, 0, nil),
		cooldownStartsOn = if trim(config.cooldownStartsOn) == "SwingStart" then "SwingStart" else "SwingEnd",
		timeout = toNumber(config.fallbackSwingDuration, DEFAULT_TIMEOUT, 0.01, nil),
		timeoutPadding = toNumber(config.fallbackSwingPadding, DEFAULT_TIMEOUT_PADDING, 0, nil),
		syntheticSwingEvents = toBool(config.syntheticSwingEventsWhenMissing, true),
		syntheticAttackWhenNoTrack = toBool(config.syntheticAttackWhenNoTrack, false),
		projectileEnabled = toBool(projectile.enabled, projectile.spawn ~= nil),
		projectileCooldown = toNumber(projectile.cooldown, 0, 0, nil),
		projectileSpawnOnStart = toBool(projectile.spawnOnAttackStart, false),
		projectileSpawn = if typeof(projectile.spawn) == "function" then projectile.spawn else nil,
		inputHeld = false,
		queued = false,
		attackActive = false,
		swingStarted = false,
		swingEnded = false,
		swingWindowOpen = false,
		cooldownUntil = 0,
		lastAttackFinishedAt = -math.huge,
		lastProjectileAt = -math.huge,
		swingCount = 0,
		tokenCount = 0,
		active = nil,
		lastTrigger = "Queue",
		retryToken = 0,
		timeoutToken = 0,
		boundTool = nil,
		namedAnimationPlaybackEnabled = namedAnimationPlaybackEnabled,
		namedAnimationStateClips = namedAnimationStateClips,
		namedAnimationTrackCache = {},
		presentationState = nil,
		presentationTrack = nil,
		presentationToken = 0,
		stanceEnabled = stanceEnabled,
		stanceDelay = stanceDelay,
		stanceTimerToken = 0,
		isToolEquipped = false,
		destroyed = false,
	}, Melee)

	self.janitor:GiveChore(self.toolJanitor)
	self.janitor:GiveChore(self.presentationJanitor)
	self.janitor:GiveChore(self.namedTrackJanitor)
	self.janitor:GiveChore(function()
		self.controller:destroy()
	end)
	self.janitor:GiveChore(function()
		for _, signalObject in self.signals do
			local signalObjectTyped = signalObject :: SignalObject
			signalObjectTyped:Destroy()
		end
	end)

	self.janitor:GiveChore(self.controller.signals.markerReached:Connect(function(name: string, param: string?, track: AnimationTrack, clip: any, index: number)
		self:_onAnimationEvent(name, "Marker", param, track, clip, index)
	end))

	self.janitor:GiveChore(self.controller.signals.keyframeReached:Connect(function(name: string, _: any, track: AnimationTrack, clip: any, index: number)
		self:_onAnimationEvent(name, "Keyframe", nil, track, clip, index)
	end))

	self.janitor:GiveChore(self.controller.signals.trackStopped:Connect(function(track: AnimationTrack)
		self:_onTrackStopped(track)
	end))

	if config.animator ~= nil then
		self:setAnimator(config.animator)
	elseif config.humanoid ~= nil then
		self:setHumanoid(config.humanoid)
	elseif config.character ~= nil then
		self:setCharacter(config.character)
	end

	if config.tool ~= nil then
		self:bindTool(config.tool, config.toolOptions)
	end

	return self
end

function Melee:_context(eventName: any, eventType: any, param: any): { [string]: any }
	local active = self.active
	local clip = if active ~= nil then active.clip else nil
	return {
		now = os.clock(),
		eventName = eventName,
		eventType = eventType,
		eventParameter = param,
		enabled = self.enabled,
		inputHeld = self.inputHeld,
		queued = self.queued,
		attackActive = self.attackActive,
		swingWindowOpen = self.swingWindowOpen,
		cooldownUntil = self.cooldownUntil,
		token = if active ~= nil then active.token else nil,
		swingIndex = if active ~= nil then active.swingIndex else nil,
		trigger = if active ~= nil then active.trigger else self.lastTrigger,
		startedAt = if active ~= nil then active.startedAt else nil,
		clip = clip,
		clipName = if clip ~= nil then clip.name else nil,
		clipIndex = if active ~= nil then active.index else nil,
		track = if active ~= nil then active.track else nil,
	}
end

function Melee:_invokeCallback(name: string, context: { [string]: any })
	local callback = self.callbacks[name]
	if typeof(callback) ~= "function" then
		return
	end
	local ok, err = pcall(callback, self, context)
	if not ok then
		warn(("[Melee] %s callback failed: %s"):format(name, tostring(err)))
	end
end

function Melee:_cancelStanceTimer()
	self.stanceTimerToken += 1
end

function Melee:_stopPresentationTrack(fadeTimeRaw: any)
	local track = self.presentationTrack
	self.presentationTrack = nil
	self.presentationState = nil
	self.presentationToken += 1
	self.presentationJanitor:Clean()

	if track ~= nil and track.IsPlaying then
		local fadeTime = toNumber(fadeTimeRaw, 0.08, 0, nil)
		pcall(function()
			track:Stop(fadeTime)
		end)
	end
end

function Melee:_clearNamedTracks()
	self:_stopPresentationTrack(0)

	for _, track in self.namedAnimationTrackCache do
		if track.IsPlaying then
			pcall(function()
				track:Stop(0)
			end)
		end
	end

	self.namedAnimationTrackCache = {}
	self.namedTrackJanitor:Clean()
end

function Melee:_loadNamedAnimationTrack(stateKeyRaw: any): AnimationTrack?
	local stateKey = if typeof(stateKeyRaw) == "string" then stateKeyRaw else nil
	if stateKey == nil then
		return nil
	end

	local cached = self.namedAnimationTrackCache[stateKey]
	if cached ~= nil then
		return cached
	end

	local clip = self.namedAnimationStateClips[stateKey]
	if clip == nil then
		return nil
	end

	local animator = self.controller.animator
	if animator == nil then
		return nil
	end

	local animation = clip.animation
	local destroyGeneratedAnimation = false
	if animation == nil then
		if clip.id == nil then
			return nil
		end
		local generated = Instance.new("Animation")
		generated.Name = clip.name
		generated.AnimationId = clip.id
		animation = generated
		destroyGeneratedAnimation = true
	end

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation :: Animation)
	end)
	if destroyGeneratedAnimation and animation ~= nil then
		animation:Destroy()
	end
	if not ok then
		warn(("[Melee] Failed to load named animation '%s': %s"):format(stateKey, tostring(trackOrError)))
		return nil
	end

	local track = trackOrError :: AnimationTrack
	if clip.looped ~= nil then
		track.Looped = clip.looped
	end
	if clip.priority ~= nil then
		track.Priority = clip.priority
	end

	self.namedAnimationTrackCache[stateKey] = track
	return track
end

function Melee:_canUseStance(): boolean
	if not self.namedAnimationPlaybackEnabled or not self.stanceEnabled then
		return false
	end
	if not self.isToolEquipped or self.attackActive or self.inputHeld then
		return false
	end
	return self.namedAnimationStateClips.StanceTransition ~= nil or self.namedAnimationStateClips.StanceIdle ~= nil
end

function Melee:_playNamedState(stateKeyRaw: any, optionsRaw: any): boolean
	if not self.namedAnimationPlaybackEnabled then
		return false
	end
	local stateKey = if typeof(stateKeyRaw) == "string" then stateKeyRaw else nil
	if stateKey == nil then
		return false
	end

	local clip = self.namedAnimationStateClips[stateKey]
	if clip == nil then
		return false
	end

	local track = self:_loadNamedAnimationTrack(stateKey)
	if track == nil then
		return false
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	if self.presentationState == stateKey and self.presentationTrack == track and track.IsPlaying then
		return true
	end
	self.presentationToken += 1
	local token = self.presentationToken
	self.presentationJanitor:Clean()
	self:_cancelStanceTimer()

	for _, otherTrack in self.namedAnimationTrackCache do
		if otherTrack ~= track and otherTrack.IsPlaying then
			pcall(function()
				otherTrack:Stop(toNumber(options.stopFadeTime, 0.06, 0, nil))
			end)
		end
	end

	local fadeTime = toNumber(options.fadeTime, clip.fadeTime or 0.08, 0, nil)
	local weight = toNumber(options.weight, clip.weight or 1, 0, nil)
	local speed = toNumber(options.speed, clip.speed or 1, 0.01, nil)
	local ok, err = pcall(function()
		track:Play(fadeTime, weight, speed)
	end)
	if not ok then
		warn(("[Melee] Failed to play named animation '%s': %s"):format(stateKey, tostring(err)))
		return false
	end

	self.presentationTrack = track
	self.presentationState = stateKey
	local onStopped = options.onStopped
	if typeof(onStopped) == "function" then
		local stoppedConnection = track.Stopped:Connect(function()
			if self.destroyed or token ~= self.presentationToken then
				return
			end
			onStopped()
		end)
		self.presentationJanitor:GiveChore(stoppedConnection)
	end

	return true
end

function Melee:_enterStance()
	if not self:_canUseStance() then
		return
	end

	local playedTransition = self:_playNamedState("StanceTransition", {
		onStopped = function()
			if not self:_canUseStance() then
				return
			end
			self:_playNamedState("StanceIdle")
		end,
	})
	if playedTransition then
		return
	end

	self:_playNamedState("StanceIdle")
end

function Melee:_scheduleStance()
	if not self:_canUseStance() then
		self:_cancelStanceTimer()
		return
	end

	local expectedToken = self.stanceTimerToken + 1
	self.stanceTimerToken = expectedToken
	task.delay(self.stanceDelay, function()
		if self.destroyed or expectedToken ~= self.stanceTimerToken then
			return
		end
		self:_enterStance()
	end)
end

function Melee:_playIdleAndScheduleStance()
	if not self.namedAnimationPlaybackEnabled then
		return
	end
	if not self.isToolEquipped or self.attackActive or self.inputHeld then
		self:_cancelStanceTimer()
		return
	end

	local hasIdle = self.namedAnimationStateClips.Idle ~= nil
	if hasIdle then
		self:_playNamedState("Idle")
	end
	self:_scheduleStance()
end

function Melee:_onToolEquipped()
	self.isToolEquipped = true
	self:_cancelStanceTimer()
	if self.attackActive then
		return
	end

	local playedEquip = self:_playNamedState("Equip", {
		onStopped = function()
			if self.destroyed or not self.isToolEquipped or self.attackActive then
				return
			end
			self:_playIdleAndScheduleStance()
		end,
	})
	if playedEquip then
		return
	end
	self:_playIdleAndScheduleStance()
end

function Melee:_onToolUnequipped()
	self.isToolEquipped = false
	self:_cancelStanceTimer()

	local playedUnequip = self:_playNamedState("Unequip", {
		onStopped = function()
			if self.destroyed then
				return
			end
			self:_stopPresentationTrack(0)
		end,
	})
	if playedUnequip then
		return
	end
	self:_stopPresentationTrack(0.06)
end

function Melee:_onPresentationAnimatorChanged()
	self:_clearNamedTracks()
	if self.destroyed or not self.namedAnimationPlaybackEnabled then
		return
	end
	if self.isToolEquipped and not self.attackActive and not self.inputHeld then
		self:_playIdleAndScheduleStance()
	end
end

function Melee:_resolveCooldown(clipRaw: any): number
	local clip = if typeof(clipRaw) == "table" then clipRaw else nil
	if clip ~= nil and typeof((clip :: any).cooldown) == "number" then
		return toNumber((clip :: any).cooldown, self.cooldown, 0, nil)
	end
	return self.cooldown
end

function Melee:_commitActiveCooldown(startedAtRaw: any?, clipRaw: any?)
	local active = self.active
	if active == nil or active.cooldownCommitted == true then
		return
	end

	local startedAt = toNumber(startedAtRaw, os.clock(), 0, nil)
	local clip = if clipRaw ~= nil then clipRaw else active.clip
	active.cooldownCommitted = true
	self.cooldownUntil = math.max(self.cooldownUntil, startedAt + self:_resolveCooldown(clip))
end

function Melee:_emitSwingStart(eventName: any, eventType: any, param: any, synthetic: boolean?)
	if self.swingStarted then
		return
	end
	self.swingStarted = true
	self.swingWindowOpen = true
	local ctx = self:_context(eventName, eventType, param)
	ctx.synthetic = synthetic == true
	self.signals.swingStarted:Fire(ctx)
	self:_invokeCallback("onSwingStarted", ctx)
end

function Melee:_emitSwingEnd(eventName: any, eventType: any, param: any, synthetic: boolean?)
	if self.swingEnded then
		return
	end
	self.swingEnded = true
	self.swingWindowOpen = false
	local ctx = self:_context(eventName, eventType, param)
	ctx.synthetic = synthetic == true
	self.signals.swingEnded:Fire(ctx)
	self:_invokeCallback("onSwingEnded", ctx)
end

function Melee:_spawnProjectile(eventName: any, eventType: any, param: any)
	if not self.projectileEnabled or self.projectileSpawn == nil then
		return
	end
	local now = os.clock()
	if now - self.lastProjectileAt < self.projectileCooldown then
		return
	end
	self.lastProjectileAt = now
	local ctx = self:_context(eventName, eventType, param)
	self.signals.projectileFired:Fire(ctx)
	self:_invokeCallback("onProjectileFired", ctx)
	local ok, err = pcall(self.projectileSpawn, self, ctx)
	if not ok then
		warn("[Melee] Projectile spawn failed:", tostring(err))
	end
end

function Melee:_scheduleRetry(waitTime: number)
	self.retryToken += 1
	local token = self.retryToken
	task.delay(math.max(0, waitTime), function()
		if token ~= self.retryToken or self.destroyed then
			return
		end
		self:_processQueue("CooldownReady")
	end)
end

function Melee:_processQueue(triggerRaw: any)
	if not self.enabled or self.attackActive or not self.queued then
		return
	end
	local now = os.clock()
	if now < self.cooldownUntil then
		self:_scheduleRetry(self.cooldownUntil - now)
		return
	end

	self.queued = false
	self.lastTrigger = trim(triggerRaw)
	if self.lastTrigger == "" then
		self.lastTrigger = "Queue"
	end
	self:_startAttack()
end

function Melee:_startAttack()
	if self.attackActive or not self.enabled then
		return
	end
	self:_cancelStanceTimer()
	self:_stopPresentationTrack(0.05)

	local now = os.clock()
	local shouldResetSequence = not self.inputHeld and (now - self.lastAttackFinishedAt) >= self.slashResetCooldown
	if shouldResetSequence then
		self.controller:resetSequence()
		self.swingCount = 0
	end

	local play = self.controller:playNext(nil)
	local usedSyntheticAttack = false
	if play == nil and self.syntheticAttackWhenNoTrack then
		usedSyntheticAttack = true
		play = {
			track = nil,
			clip = {
				name = "SyntheticSwing",
				cooldown = self.cooldown,
				duration = self.timeout,
			},
			index = 0,
		}
	end

	if play == nil then
		self.queued = true
		self.cooldownUntil = math.max(self.cooldownUntil, os.clock() + self.cooldown)
		self:_scheduleRetry(self.cooldown)
		return
	end

	self.attackActive = true
	self.swingStarted = false
	self.swingEnded = false
	self.swingWindowOpen = false
	self.swingCount += 1
	self.tokenCount += 1
	self.active = {
		token = self.tokenCount,
		swingIndex = self.swingCount,
		trigger = self.lastTrigger,
		startedAt = now,
		track = play.track,
		clip = play.clip,
		index = play.index,
		synthetic = usedSyntheticAttack,
		cooldownCommitted = false,
	}

	if self.cooldownStartsOn == "SwingStart" then
		self:_commitActiveCooldown(now, play.clip)
	end

	local startedContext = self:_context(nil, "AttackStarted", nil)
	self.signals.attackStarted:Fire(startedContext)
	self:_invokeCallback("onAttackStarted", startedContext)

	if self.projectileSpawnOnStart then
		self:_spawnProjectile("attackStart", "Synthetic", nil)
	end

	local clipSpeed = if typeof(play.clip.speed) == "number" and play.clip.speed > 0 then play.clip.speed else 1
	local duration = if typeof(play.clip.duration) == "number"
		then play.clip.duration
		else if play.track ~= nil and play.track.Length > 0 then play.track.Length / clipSpeed else self.timeout
	self.timeoutToken += 1
	local token = self.timeoutToken
	task.delay(math.max(0.01, duration + self.timeoutPadding), function()
		if token ~= self.timeoutToken or self.destroyed then
			return
		end
		if self.attackActive then
			self:_finishAttack("Timeout")
		end
	end)
end

function Melee:_finishAttack(reasonRaw: any)
	if not self.attackActive then
		return
	end
	local reason = trim(reasonRaw)
	if reason == "" then
		reason = "Finished"
	end

	if self.syntheticSwingEvents and not self.swingStarted then
		self:_emitSwingStart("syntheticStart", "Synthetic", nil, true)
	end
	if self.syntheticSwingEvents and not self.swingEnded then
		self:_emitSwingEnd("syntheticEnd", "Synthetic", nil, true)
	end

	local active = self.active
	local activeTrack = if active ~= nil then active.track else nil
	local activeClip = if active ~= nil then active.clip else nil
	if self.cooldownStartsOn == "SwingEnd" then
		self:_commitActiveCooldown(os.clock(), activeClip)
	end

	local finishedContext = self:_context(reason, "AttackFinished", nil)
	finishedContext.reason = reason

	self.attackActive = false
	self.swingWindowOpen = false
	self.active = nil
	self.timeoutToken += 1
	self.lastAttackFinishedAt = os.clock()

	self.signals.attackFinished:Fire(finishedContext)
	self:_invokeCallback("onAttackFinished", finishedContext)

	-- If a track never reported completion, force it down before the next queued swing can begin.
	if reason == "Timeout" and activeTrack ~= nil and activeTrack.IsPlaying then
		pcall(function()
			activeTrack:Stop(toNumber(if activeClip ~= nil then activeClip.fadeTime else nil, 0.02, 0, nil))
		end)
	end

	if not self.inputHeld and self.isToolEquipped then
		self:_playIdleAndScheduleStance()
	end

	if self.autoRepeat and self.inputHeld then
		self:queueSwing("HoldRepeat")
	elseif self.queued then
		self:_processQueue("Pending")
	end
end

function Melee:_onAnimationEvent(nameRaw: any, eventType: string, param: any, track: AnimationTrack, clip: any, index: number)
	if not self.attackActive or self.active == nil then
		return
	end
	if self.active.track ~= track then
		return
	end

	local normalized = normalizeEventName(nameRaw)
	if normalized == "" then
		return
	end

	if eventType == "Keyframe" and not self.trackAllKeyframes then
		local tracked = self.trackedKeyframes[normalized]
			or self.startEventSet[normalized]
			or self.endEventSet[normalized]
			or self.projectileEventSet[normalized]
		if not tracked then
			return
		end
	end

	self.active.clip = clip
	self.active.index = index

	local eventContext = self:_context(nameRaw, eventType, param)
	self.signals.animationEvent:Fire(eventContext)
	self:_invokeCallback("onAnimationEvent", eventContext)

	if self.startEventSet[normalized] then
		self:_emitSwingStart(nameRaw, eventType, param, false)
	end

	if self.projectileEventSet[normalized] then
		self:_spawnProjectile(nameRaw, eventType, param)
	end

	if self.endEventSet[normalized] then
		self:_emitSwingEnd(nameRaw, eventType, param, false)
		if self.cooldownStartsOn == "SwingEnd" then
			self:_commitActiveCooldown(eventContext.now, clip)
		end
	end
end

function Melee:_onTrackStopped(track: AnimationTrack)
	if not self.attackActive or self.active == nil then
		return
	end
	if self.active.track ~= track then
		return
	end
	if not self.swingEnded then
		self:_emitSwingEnd("trackStopped", "TrackStopped", nil, self.syntheticSwingEvents)
	end
	self:_finishAttack("TrackStopped")
end

function Melee:queueSwing(triggerRaw: any): boolean
	if not self.enabled then
		return false
	end
	self.queued = true
	self.lastTrigger = trim(triggerRaw)
	if self.lastTrigger == "" then
		self.lastTrigger = "Queue"
	end

	local requestContext = self:_context(nil, "AttackRequested", nil)
	requestContext.trigger = self.lastTrigger
	self.signals.attackRequested:Fire(requestContext)
	self:_invokeCallback("onAttackRequested", requestContext)

	self:_processQueue(self.lastTrigger)
	return true
end

function Melee:inputBegan(triggerRaw: any): boolean
	local wasHeld = self.inputHeld
	self.inputHeld = true
	if wasHeld ~= self.inputHeld then
		self.signals.inputHeldChanged:Fire(self.inputHeld)
	end
	self:_cancelStanceTimer()
	return self:queueSwing(triggerRaw or "InputBegan")
end

function Melee:inputEnded(_: any): boolean
	local wasHeld = self.inputHeld
	self.inputHeld = false
	if wasHeld ~= self.inputHeld then
		self.signals.inputHeldChanged:Fire(self.inputHeld)
	end
	if not self.attackActive and self.isToolEquipped then
		self:_playIdleAndScheduleStance()
	end
	return true
end

function Melee:tap(triggerRaw: any): boolean
	return self:queueSwing(triggerRaw or "Tap")
end

function Melee:setEnabled(enabledRaw: any)
	local enabled = toBool(enabledRaw, self.enabled)
	if self.enabled == enabled then
		return
	end
	self.enabled = enabled
	self.signals.enabledChanged:Fire(self.enabled)
	if not enabled then
		self:cancel("Disabled")
	elseif self.queued then
		self:_processQueue("Enabled")
	end
end

function Melee:setCooldown(secondsRaw: any)
	self.cooldown = toNumber(secondsRaw, self.cooldown, 0, nil)
end

function Melee:setSlashResetCooldown(secondsRaw: any)
	self.slashResetCooldown = toNumber(secondsRaw, self.slashResetCooldown, 0, nil)
end

function Melee:setAnimator(animatorRaw: any)
	self.controller:setAnimator(animatorRaw)
	self:_onPresentationAnimatorChanged()
end

function Melee:setHumanoid(humanoidRaw: any)
	local humanoid = if typeof(humanoidRaw) == "Instance" and humanoidRaw:IsA("Humanoid") then humanoidRaw else nil
	self.controller:setAnimator(createAnimatorFromHumanoid(humanoid))
	self:_onPresentationAnimatorChanged()
end

function Melee:setCharacter(characterRaw: any)
	local character = if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model") then characterRaw else nil
	self.controller:setAnimator(createAnimatorFromCharacter(character))
	self:_onPresentationAnimatorChanged()
end

function Melee:setClips(clipsRaw: any)
	self.controller:setClips(clipsRaw)
end

function Melee:setMode(modeRaw: any)
	self.controller:setMode(modeRaw)
end

function Melee:bindTool(toolRaw: any, optionsRaw: any): boolean
	local tool = if typeof(toolRaw) == "Instance" and toolRaw:IsA("Tool") then toolRaw else nil
	if tool == nil then
		return false
	end

	if self.boundTool ~= nil and self.boundTool ~= tool then
		self:_onToolUnequipped()
	end
	self.toolJanitor:Clean()
	self.boundTool = tool

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local resolveAnimatorOnEquip = toBool(options.resolveAnimatorOnEquip, true)
	local cancelOnUnequip = toBool(options.cancelOnUnequip, true)

	if resolveAnimatorOnEquip and tool.Parent and tool.Parent:IsA("Model") then
		self:setCharacter(tool.Parent)
	end
	if tool.Parent ~= nil and tool.Parent:IsA("Model") then
		self:_onToolEquipped()
	else
		self.isToolEquipped = false
		self:_cancelStanceTimer()
		self:_stopPresentationTrack(0)
	end

	self.toolJanitor:GiveChore(tool.Equipped:Connect(function()
		if resolveAnimatorOnEquip and tool.Parent and tool.Parent:IsA("Model") then
			self:setCharacter(tool.Parent)
		end
		self:_onToolEquipped()
	end))

	self.toolJanitor:GiveChore(tool.Activated:Connect(function()
		self:inputBegan("ToolActivated")
	end))

	self.toolJanitor:GiveChore(tool.Deactivated:Connect(function()
		self:inputEnded("ToolDeactivated")
	end))

	self.toolJanitor:GiveChore(tool.Unequipped:Connect(function()
		self:_onToolUnequipped()
		self:inputEnded("ToolUnequipped")
		if cancelOnUnequip then
			self:cancel("ToolUnequipped")
		end
	end))

	self.toolJanitor:GiveChore(tool.Destroying:Connect(function()
		if self.boundTool == tool then
			self:unbindTool()
		end
	end))

	return true
end

function Melee:unbindTool()
	self:_onToolUnequipped()
	self.toolJanitor:Clean()
	self.boundTool = nil
end

function Melee:on(signalNameRaw: any, callback: (...any) -> ()): RBXScriptConnection?
	if typeof(signalNameRaw) ~= "string" or typeof(callback) ~= "function" then
		return nil
	end
	local signalObject = self.signals[signalNameRaw]
	if signalObject == nil then
		return nil
	end
	return (signalObject :: SignalObject):Connect(callback)
end

function Melee:cancel(reasonRaw: any)
	self.queued = false
	local wasHeld = self.inputHeld
	self.inputHeld = false
	if wasHeld ~= self.inputHeld then
		self.signals.inputHeldChanged:Fire(self.inputHeld)
	end
	self.retryToken += 1
	self:_cancelStanceTimer()
	self.controller:resetSequence()
	self.swingCount = 0
	self.lastAttackFinishedAt = -math.huge

	local activeTrack = if self.active ~= nil then self.active.track else nil
	self:_finishAttack(reasonRaw or "Cancelled")
	if activeTrack ~= nil and activeTrack.IsPlaying then
		pcall(function()
			activeTrack:Stop(0)
		end)
	end
	if self.isToolEquipped then
		self:_playIdleAndScheduleStance()
	else
		self:_stopPresentationTrack(0.05)
	end
end

function Melee:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:unbindTool()
	self:_clearNamedTracks()
	self:cancel("Destroyed")
	self.janitor:Destroy()
end

function Melee:Destroy()
	self:destroy()
end

return Melee
