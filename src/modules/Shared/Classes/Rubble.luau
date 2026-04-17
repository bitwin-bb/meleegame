--!strict
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)

local Rubble = {}
Rubble.__index = Rubble

local DEFAULT_COLLISION_GROUP = "Default"
local PLAYER_COLLISION_GROUP = "PlayersCharacters"
local ENEMY_COLLISION_GROUP = "NpcEnemies"

type ReusePolicy = "RecycleOldest" | "DropSpawn"

export type Tuning = {
	initialPoolSize: number?,
	maxPoolSize: number?,
	maxSpawnsPerStep: number?,
	reusePolicy: ReusePolicy?,
	defaultLifetime: number?,
	minLifetime: number?,
	maxLifetime: number?,
	minSize: number?,
	maxSize: number?,
	defaultScale: number?,
	minScale: number?,
	maxScale: number?,
	maxImpulse: number?,
	maxAngularImpulse: number?,
	maxVelocity: number?,
	forceToImpulseSeconds: number?,
	defaultFadeOut: boolean?,
	fadeDuration: number?,
	flingSpeedThreshold: number?,
	flingReflectionScale: number?,
	maxFlingBounces: number?,
	lodDistance: number?,
	lodCheckInterval: number?,
	lodFarAnchor: boolean?,
	lodFarDisableCollision: boolean?,
	enableNoGravityCompensation: boolean?,
	autoServerNetworkOwnership: boolean?,
	defaultCanCollide: boolean?,
	defaultCanTouch: boolean?,
	defaultCanQuery: boolean?,
}

export type Config = {
	template: BasePart?,
	tuning: Tuning?,
	initialPoolSize: number?,
	maxPoolSize: number?,
	reusePolicy: ReusePolicy?,
	containerName: string?,
	activeFolderName: string?,
	inactiveFolderName: string?,
	partNamePrefix: string?,
	parkingCFrame: CFrame?,
	activeCollisionGroup: string?,
	inactiveCollisionGroup: string?,
	lodReference: any?,
	raycastIgnore: { Instance }?,
	visualOnly: boolean?,
	mirrorRemoteEvent: RemoteEvent?,
	mirrorSendFromServer: boolean?,
	mirrorListenOnClient: boolean?,
}

export type SpawnParams = { [string]: any }
export type Rubble = typeof(setmetatable({} :: any, Rubble))

type Slot = {
	id: number,
	part: BasePart,
	active: boolean,
	token: number,
	expiresAt: number,
	baseTransparency: number,
	fadeOut: boolean,
	fadeDuration: number,
	canFling: boolean,
	flingBounces: number,
	maxFlingBounces: number,
	flingReflectionScale: number,
	noGravity: boolean,
	visualOnly: boolean,
	prevPos: Vector3,
	requestedAnchored: boolean,
	requestedCanCollide: boolean,
	requestedCanTouch: boolean,
	requestedCanQuery: boolean,
	requestedCollisionGroup: string,
	lodFar: boolean,
	lodReference: any?,
}

type ExpiryNode = { expiresAt: number, slotId: number, token: number }

local ZERO = Vector3.zero
local NEGINF = -math.huge

local DEFAULT_TUNING: Tuning = {
	initialPoolSize = 128,
	maxPoolSize = 768,
	maxSpawnsPerStep = 256,
	reusePolicy = "RecycleOldest",
	defaultLifetime = 2.25,
	minLifetime = 0.05,
	maxLifetime = 20,
	minSize = 0.08,
	maxSize = 24,
	defaultScale = 1,
	minScale = 0.1,
	maxScale = 8,
	maxImpulse = 6500,
	maxAngularImpulse = 18000,
	maxVelocity = 450,
	forceToImpulseSeconds = 1 / 60,
	defaultFadeOut = true,
	fadeDuration = 0.2,
	flingSpeedThreshold = 12,
	flingReflectionScale = 0.65,
	maxFlingBounces = 1,
	lodDistance = 260,
	lodCheckInterval = 0.2,
	lodFarAnchor = true,
	lodFarDisableCollision = true,
	enableNoGravityCompensation = true,
	autoServerNetworkOwnership = true,
	defaultCanCollide = true,
	defaultCanTouch = false,
	defaultCanQuery = false,
}

local function n(v: any, fallback: number, minV: number?, maxV: number?): number
	local out = if typeof(v) == "number" and v == v then v else fallback
	if minV ~= nil and out < minV then
		out = minV
	end
	if maxV ~= nil and out > maxV then
		out = maxV
	end
	return out
end

local function b(v: any, fallback: boolean): boolean
	return if typeof(v) == "boolean" then v else fallback
end

local function s(v: any, fallback: string): string
	return if typeof(v) == "string" and v ~= "" then v else fallback
end

local function g(src: { [string]: any }, lower: string, upper: string): any
	local lowerValue = src[lower]
	if lowerValue ~= nil then
		return lowerValue
	end
	return src[upper]
end

local function clampMag(v: Vector3, maxMag: number): Vector3
	local m = v.Magnitude
	if m <= maxMag or m <= 1e-6 then
		return v
	end
	return v * (maxMag / m)
end

local function now(): number
	local ok, val = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and typeof(val) == "number" and val == val then
		return val
	end
	return os.clock()
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function resolveRange(raw: any, minFallback: number, maxFallback: number): (number, number)
	if typeof(raw) == "NumberRange" then
		return math.min(raw.Min, raw.Max), math.max(raw.Min, raw.Max)
	end
	if typeof(raw) == "Vector2" then
		return math.min(raw.X, raw.Y), math.max(raw.X, raw.Y)
	end
	if typeof(raw) == "table" then
		local lo = (raw :: any).min or (raw :: any).Min or (raw :: any)[1]
		local hi = (raw :: any).max or (raw :: any).Max or (raw :: any)[2]
		if typeof(lo) == "number" and lo == lo and typeof(hi) == "number" and hi == hi then
			return math.min(lo, hi), math.max(lo, hi)
		end
	end
	return minFallback, maxFallback
end

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function resolveReferencePosition(reference: any): Vector3?
	if typeof(reference) == "Vector3" then
		return reference
	end
	if typeof(reference) == "CFrame" then
		return reference.Position
	end
	if typeof(reference) ~= "Instance" then
		return nil
	end
	local r = reference :: Instance
	if r:IsA("BasePart") then
		return r.Position
	elseif r:IsA("Attachment") then
		return r.WorldPosition
	elseif r:IsA("Camera") then
		return r.CFrame.Position
	elseif r:IsA("Model") then
		local root = resolveRootPart(r)
		return if root then root.Position else nil
	elseif r:IsA("Player") then
		local root = resolveRootPart((r :: Player).Character)
		return if root then root.Position else nil
	end
	return nil
end

local function firstPlayerPosition(): Vector3?
	for _, player in Players:GetPlayers() do
		local root = resolveRootPart(player.Character)
		if root then
			return root.Position
		end
	end
	return nil
end

local function resolvePhysical(
	customProps: any,
	massOverride: any,
	size: Vector3,
	fallback: PhysicalProperties?
): PhysicalProperties?
	local result = if typeof(customProps) == "PhysicalProperties" then customProps :: PhysicalProperties else fallback
	if typeof(massOverride) ~= "number" or massOverride ~= massOverride or massOverride <= 0 then
		return result
	end
	local volume = math.max(0.001, size.X * size.Y * size.Z)
	local density = math.max(0.01, massOverride / volume)
	if result then
		return PhysicalProperties.new(
			density,
			result.Friction,
			result.Elasticity,
			result.FrictionWeight,
			result.ElasticityWeight
		)
	end
	return PhysicalProperties.new(density, 0.3, 0.1, 1, 1)
end

local function sanitizeVector3(raw: any, fallback: Vector3): Vector3
	return if typeof(raw) == "Vector3" then raw else fallback
end

local function sanitizeCFrame(raw: any, fallback: CFrame): CFrame
	return if typeof(raw) == "CFrame" then raw else fallback
end

local function sanitizeMaterial(raw: any, fallback: Enum.Material): Enum.Material
	if typeof(raw) == "EnumItem" and (raw :: EnumItem).EnumType == Enum.Material then
		return raw :: any
	end
	return fallback
end

local function sanitizeColor(raw: any, fallback: Color3): Color3
	return if typeof(raw) == "Color3" then raw else fallback
end

local function safeRegisterCollisionGroup(groupName: string)
	if groupName == "" then
		return
	end
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
end

local function safeSetCollisionGroupCollidable(groupA: string, groupB: string, collidable: boolean)
	if groupA == "" or groupB == "" then
		return
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(groupA, groupB, collidable)
	end)
end

function Rubble.New(configRaw: Config?): Rubble
	local cfg = if typeof(configRaw) == "table" then configRaw else {}
	local tuning: Tuning = Sift.Dictionary.copy(DEFAULT_TUNING)
	if typeof(cfg.tuning) == "table" then
		for key, value in cfg.tuning :: any do
			(tuning :: any)[key] = value
		end
	end
	if cfg.initialPoolSize ~= nil then
		tuning.initialPoolSize = cfg.initialPoolSize
	end
	if cfg.maxPoolSize ~= nil then
		tuning.maxPoolSize = cfg.maxPoolSize
	end
	if cfg.reusePolicy ~= nil then
		tuning.reusePolicy = cfg.reusePolicy
	end
	tuning.maxPoolSize = n(tuning.maxPoolSize, DEFAULT_TUNING.maxPoolSize :: number, 1, 50000)
	tuning.initialPoolSize = n(tuning.initialPoolSize, DEFAULT_TUNING.initialPoolSize :: number, 0, tuning.maxPoolSize)
	tuning.maxSpawnsPerStep = n(tuning.maxSpawnsPerStep, DEFAULT_TUNING.maxSpawnsPerStep :: number, 1, 8192)
	tuning.defaultLifetime = n(tuning.defaultLifetime, DEFAULT_TUNING.defaultLifetime :: number, 0.01, 120)
	tuning.minLifetime = n(tuning.minLifetime, DEFAULT_TUNING.minLifetime :: number, 0.01, 120)
	tuning.maxLifetime = n(tuning.maxLifetime, DEFAULT_TUNING.maxLifetime :: number, tuning.minLifetime, 300)
	tuning.minSize = n(tuning.minSize, DEFAULT_TUNING.minSize :: number, 0.01, 10000)
	tuning.maxSize = n(tuning.maxSize, DEFAULT_TUNING.maxSize :: number, tuning.minSize, 20000)
	tuning.defaultScale = n(tuning.defaultScale, DEFAULT_TUNING.defaultScale :: number, 0.01, 1000)
	tuning.minScale = n(tuning.minScale, DEFAULT_TUNING.minScale :: number, 0.01, 1000)
	tuning.maxScale = n(tuning.maxScale, DEFAULT_TUNING.maxScale :: number, tuning.minScale, 10000)
	tuning.maxImpulse = n(tuning.maxImpulse, DEFAULT_TUNING.maxImpulse :: number, 1, 500000)
	tuning.maxAngularImpulse = n(tuning.maxAngularImpulse, DEFAULT_TUNING.maxAngularImpulse :: number, 1, 2000000)
	tuning.maxVelocity = n(tuning.maxVelocity, DEFAULT_TUNING.maxVelocity :: number, 1, 5000)
	tuning.forceToImpulseSeconds = n(tuning.forceToImpulseSeconds, DEFAULT_TUNING.forceToImpulseSeconds :: number, 0, 1)
	tuning.defaultFadeOut = b(tuning.defaultFadeOut, DEFAULT_TUNING.defaultFadeOut :: boolean)
	tuning.fadeDuration = n(tuning.fadeDuration, DEFAULT_TUNING.fadeDuration :: number, 0, 10)
	tuning.flingSpeedThreshold = n(tuning.flingSpeedThreshold, DEFAULT_TUNING.flingSpeedThreshold :: number, 0, 5000)
	tuning.flingReflectionScale = n(tuning.flingReflectionScale, DEFAULT_TUNING.flingReflectionScale :: number, 0, 2)
	tuning.maxFlingBounces = math.floor(n(tuning.maxFlingBounces, DEFAULT_TUNING.maxFlingBounces :: number, 0, 20))
	tuning.lodDistance = n(tuning.lodDistance, DEFAULT_TUNING.lodDistance :: number, 0, 50000)
	tuning.lodCheckInterval = n(tuning.lodCheckInterval, DEFAULT_TUNING.lodCheckInterval :: number, 0.02, 3)
	tuning.lodFarAnchor = b(tuning.lodFarAnchor, DEFAULT_TUNING.lodFarAnchor :: boolean)
	tuning.lodFarDisableCollision = b(tuning.lodFarDisableCollision, DEFAULT_TUNING.lodFarDisableCollision :: boolean)
	tuning.enableNoGravityCompensation =
		b(tuning.enableNoGravityCompensation, DEFAULT_TUNING.enableNoGravityCompensation :: boolean)
	tuning.autoServerNetworkOwnership =
		b(tuning.autoServerNetworkOwnership, DEFAULT_TUNING.autoServerNetworkOwnership :: boolean)
	tuning.defaultCanCollide = b(tuning.defaultCanCollide, DEFAULT_TUNING.defaultCanCollide :: boolean)
	tuning.defaultCanTouch = b(tuning.defaultCanTouch, DEFAULT_TUNING.defaultCanTouch :: boolean)
	tuning.defaultCanQuery = b(tuning.defaultCanQuery, DEFAULT_TUNING.defaultCanQuery :: boolean)
	tuning.reusePolicy = if tuning.reusePolicy == "DropSpawn" then "DropSpawn" else "RecycleOldest"

	local template = if cfg.template and cfg.template:IsA("BasePart")
		then cfg.template:Clone()
		else Instance.new("Part")
	template.Name = "RubbleTemplate"
	template.Anchored = true
	template.CanCollide = false
	template.CanTouch = false
	template.CanQuery = false
	template.Parent = nil

	local root = ensureFolder(WorkspaceFolders.getOrCreateGameFolder(), s(cfg.containerName, "RubbleRuntime"))
	local active = ensureFolder(root, s(cfg.activeFolderName, "Active"))
	local inactive = ensureFolder(root, s(cfg.inactiveFolderName, "Inactive"))
	local activeGroup = s(cfg.activeCollisionGroup, "RubbleActive")
	local inactiveGroup = s(cfg.inactiveCollisionGroup, "RubbleInactive")

	local self = setmetatable({
		tuning = tuning,
		random = Random.new(),
		template = template,
		templateSize = template.Size,
		templateMaterial = template.Material,
		templateColor = template.Color,
		templateTransparency = template.Transparency,
		templatePhysical = template.CustomPhysicalProperties,
		templateReflectance = template.Reflectance,
		templateCastShadow = template.CastShadow,
		root = root,
		active = active,
		inactive = inactive,
		parkingCFrame = sanitizeCFrame(cfg.parkingCFrame, CFrame.new(0, -10000, 0)),
		partNamePrefix = s(cfg.partNamePrefix, "Rubble_"),
		activeGroup = activeGroup,
		inactiveGroup = inactiveGroup,
		lodReference = cfg.lodReference,
		visualOnly = b(cfg.visualOnly, false),
		mirrorRemote = if cfg.mirrorRemoteEvent and cfg.mirrorRemoteEvent:IsA("RemoteEvent")
			then cfg.mirrorRemoteEvent
			else nil,
		mirrorSend = b(cfg.mirrorSendFromServer, true),
		mirrorListen = b(cfg.mirrorListenOnClient, true),
		slotById = {},
		idByPart = {},
		free = {},
		freeTop = 0,
		activeIds = {},
		activeIndex = {},
		expiryHeap = {},
		nextSlotId = 0,
		destroyed = false,
		lodAccumulator = 0,
		spawnBudget = tuning.maxSpawnsPerStep,
		totalSpawns = 0,
		totalRecycles = 0,
		totalDropped = 0,
		peakActive = 0,
		heartbeat = nil,
		mirrorConnection = nil,
		raycastParams = RaycastParams.new(),
	}, Rubble)
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.raycastParams.IgnoreWater = false
	local filter: { Instance } = { self.root }
	if typeof(cfg.raycastIgnore) == "table" then
		for _, inst in cfg.raycastIgnore :: { Instance } do
			if typeof(inst) == "Instance" then
				table.insert(filter, inst)
			end
		end
	end
	self.raycastParams.FilterDescendantsInstances = filter

	safeRegisterCollisionGroup(activeGroup)
	safeRegisterCollisionGroup(inactiveGroup)
	safeSetCollisionGroupCollidable(inactiveGroup, activeGroup, false)
	safeSetCollisionGroupCollidable(inactiveGroup, inactiveGroup, false)
	safeSetCollisionGroupCollidable(activeGroup, activeGroup, true)
	safeSetCollisionGroupCollidable(activeGroup, DEFAULT_COLLISION_GROUP, true)
	safeSetCollisionGroupCollidable(DEFAULT_COLLISION_GROUP, activeGroup, true)
	safeSetCollisionGroupCollidable(activeGroup, PLAYER_COLLISION_GROUP, false)
	safeSetCollisionGroupCollidable(PLAYER_COLLISION_GROUP, activeGroup, false)
	safeSetCollisionGroupCollidable(activeGroup, ENEMY_COLLISION_GROUP, false)
	safeSetCollisionGroupCollidable(ENEMY_COLLISION_GROUP, activeGroup, false)

	self:WarmPool(tuning.initialPoolSize)
	self.heartbeat = RunService.Heartbeat:Connect(function(dt)
		self:_onHeartbeat(dt)
	end)
	if not RunService:IsServer() and self.mirrorRemote and self.mirrorListen then
		self.mirrorConnection = self.mirrorRemote.OnClientEvent:Connect(function(action, payload)
			if action == "RubbleSpawn" and typeof(payload) == "table" then
				local p = Sift.Dictionary.copy(payload)
				local pAny = p :: any
				pAny.VisualOnly = true
				pAny.Mirror = false
				self:Spawn(p)
			elseif action == "RubbleRecycleAll" then
				self:RecycleAll()
			end
		end)
	end
	return self
end

function Rubble:_heapPush(node: ExpiryNode)
	local heap = self.expiryHeap
	local i = #heap + 1
	heap[i] = node
	while i > 1 do
		local p = math.floor(i / 2)
		if heap[p].expiresAt <= node.expiresAt then
			break
		end
		heap[p], heap[i] = heap[i], heap[p]
		i = p
	end
end

function Rubble:_heapPop(): ExpiryNode?
	local heap = self.expiryHeap
	if #heap == 0 then
		return nil
	end
	local root = heap[1]
	local last = heap[#heap]
	heap[#heap] = nil
	if #heap == 0 then
		return root
	end
	heap[1] = last
	local i = 1
	while true do
		local l = i * 2
		local r = l + 1
		local smallest = i
		if heap[l] and heap[l].expiresAt < heap[smallest].expiresAt then
			smallest = l
		end
		if heap[r] and heap[r].expiresAt < heap[smallest].expiresAt then
			smallest = r
		end
		if smallest == i then
			break
		end
		heap[i], heap[smallest] = heap[smallest], heap[i]
		i = smallest
	end
	return root
end

function Rubble:_pushFree(slot: Slot)
	self.freeTop += 1
	self.free[self.freeTop] = slot.id
end

function Rubble:_popFree(): Slot?
	if self.freeTop <= 0 then
		return nil
	end
	local id = self.free[self.freeTop]
	self.free[self.freeTop] = nil
	self.freeTop -= 1
	return if id then self.slotById[id] else nil
end

function Rubble:_makeSlot(): Slot?
	if self.nextSlotId >= self.tuning.maxPoolSize then
		return nil
	end
	local part = self.template:Clone()
	if not part:IsA("BasePart") then
		return nil
	end
	self.nextSlotId += 1
	local id = self.nextSlotId
	part.Name = self.partNamePrefix .. tostring(id)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.CastShadow = false
	part.AssemblyLinearVelocity = ZERO
	part.AssemblyAngularVelocity = ZERO
	part.CFrame = self.parkingCFrame
	part.CollisionGroup = self.inactiveGroup
	part.Parent = self.inactive
	local slot: Slot = {
		id = id,
		part = part,
		active = false,
		token = 0,
		expiresAt = NEGINF,
		baseTransparency = 0,
		fadeOut = false,
		fadeDuration = 0,
		canFling = false,
		flingBounces = 0,
		maxFlingBounces = 0,
		flingReflectionScale = self.tuning.flingReflectionScale,
		noGravity = false,
		visualOnly = false,
		prevPos = part.Position,
		requestedAnchored = false,
		requestedCanCollide = false,
		requestedCanTouch = false,
		requestedCanQuery = false,
		requestedCollisionGroup = self.activeGroup,
		lodFar = false,
		lodReference = nil,
	}
	self.slotById[id] = slot
	self.idByPart[part] = id
	self:_pushFree(slot)
	return slot
end

function Rubble:WarmPool(countRaw: any): number
	local count = math.floor(n(countRaw, 0, 0, self.tuning.maxPoolSize))
	local added = 0
	for _ = 1, count do
		if self:_makeSlot() == nil then
			break
		end
		added += 1
	end
	return added
end

function Rubble:_activeAdd(slot: Slot)
	local index = #self.activeIds + 1
	self.activeIds[index] = slot.id
	self.activeIndex[slot.id] = index
	if index > self.peakActive then
		self.peakActive = index
	end
end

function Rubble:_activeRemove(slot: Slot)
	local i = self.activeIndex[slot.id]
	if i == nil then
		return
	end
	local list = self.activeIds
	local last = list[#list]
	list[#list] = nil
	self.activeIndex[slot.id] = nil
	if last and i < #list + 1 then
		list[i] = last
		self.activeIndex[last] = i
	end
end

function Rubble:_resetPart(part: BasePart)
	part.AssemblyLinearVelocity = ZERO
	part.AssemblyAngularVelocity = ZERO
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.CastShadow = false
	part.Material = self.templateMaterial
	part.Color = self.templateColor
	part.Reflectance = self.templateReflectance
	part.Size = self.templateSize
	part.CustomPhysicalProperties = self.templatePhysical
	part.CollisionGroup = self.inactiveGroup
	part.CFrame = self.parkingCFrame
	part.Parent = self.inactive
end

function Rubble:_recycleSlot(slot: Slot)
	if not slot.active then
		return
	end
	slot.active = false
	slot.expiresAt = NEGINF
	slot.canFling = false
	slot.noGravity = false
	slot.fadeOut = false
	slot.lodFar = false
	slot.lodReference = nil
	self:_activeRemove(slot)
	self:_resetPart(slot.part)
	self:_pushFree(slot)
	self.totalRecycles += 1
end

function Rubble:_acquireSlot(): Slot?
	local slot = self:_popFree()
	if slot then
		return slot
	end
	if self:_makeSlot() then
		return self:_popFree()
	end
	if self.tuning.reusePolicy ~= "RecycleOldest" then
		return nil
	end
	while true do
		local node = self:_heapPop()
		if node == nil then
			return nil
		end
		local active = self.slotById[node.slotId]
		if active and active.active and active.token == node.token then
			self:_recycleSlot(active)
			return self:_popFree()
		end
	end
end

function Rubble:_resolveLodOrigin(slot: Slot, sharedOrigin: Vector3?): Vector3?
	if slot.lodReference ~= nil then
		if typeof(slot.lodReference) == "function" then
			local ok, out = pcall(slot.lodReference)
			if ok then
				local p = resolveReferencePosition(out)
				if p then
					return p
				end
			end
		else
			local p = resolveReferencePosition(slot.lodReference)
			if p then
				return p
			end
		end
	end
	return sharedOrigin
end

function Rubble:_updateSlot(slot: Slot, dt: number, currentNow: number, checkLod: boolean, sharedLodOrigin: Vector3?)
	local part = slot.part
	if part.Parent == nil then
		self:_recycleSlot(slot)
		return
	end
	if self.tuning.enableNoGravityCompensation and slot.noGravity and not part.Anchored then
		local v = part.AssemblyLinearVelocity
		part.AssemblyLinearVelocity = Vector3.new(v.X, v.Y + Workspace.Gravity * dt, v.Z)
	end
	if slot.canFling and not part.Anchored then
		local oldPos = slot.prevPos
		local newPos = part.Position
		slot.prevPos = newPos
		local travel = newPos - oldPos
		if travel.Magnitude > 1e-5 and part.AssemblyLinearVelocity.Magnitude >= self.tuning.flingSpeedThreshold then
			local hit = Workspace:Raycast(oldPos, travel, self.raycastParams)
			if hit then
				local normal = hit.Normal
				local reflected = part.AssemblyLinearVelocity - normal * (2 * part.AssemblyLinearVelocity:Dot(normal))
				part.AssemblyLinearVelocity = clampMag(reflected * slot.flingReflectionScale, self.tuning.maxVelocity)
				slot.flingBounces += 1
				if slot.flingBounces >= slot.maxFlingBounces then
					slot.canFling = false
				end
			end
		end
	end
	if slot.fadeOut and slot.fadeDuration > 0 then
		local remaining = slot.expiresAt - currentNow
		if remaining <= slot.fadeDuration then
			local a = 1 - math.clamp(remaining / slot.fadeDuration, 0, 1)
			part.Transparency = math.clamp(slot.baseTransparency + (1 - slot.baseTransparency) * a, 0, 1)
		end
	end
	if checkLod and self.tuning.lodDistance > 0 then
		local origin = self:_resolveLodOrigin(slot, sharedLodOrigin)
		if origin then
			local far = (part.Position - origin).Magnitude > self.tuning.lodDistance
			if far ~= slot.lodFar then
				slot.lodFar = far
				if far then
					if self.tuning.lodFarDisableCollision then
						part.CanCollide = false
						part.CanTouch = false
						part.CanQuery = false
					end
					if self.tuning.lodFarAnchor and not slot.requestedAnchored then
						part.Anchored = true
					end
				else
					part.Anchored = slot.requestedAnchored
					part.CanCollide = slot.requestedCanCollide
					part.CanTouch = slot.requestedCanTouch
					part.CanQuery = slot.requestedCanQuery
				end
			end
		end
	end
end

function Rubble:_onHeartbeat(dt: number)
	if self.destroyed then
		return
	end
	self.spawnBudget = self.tuning.maxSpawnsPerStep
	local tnow = now()
	while true do
		local top = self.expiryHeap[1]
		if top == nil or top.expiresAt > tnow then
			break
		end
		local node = self:_heapPop()
		if node then
			local slot = self.slotById[node.slotId]
			if slot and slot.active and slot.token == node.token and slot.expiresAt <= tnow then
				self:_recycleSlot(slot)
			end
		end
	end

	local checkLod = false
	self.lodAccumulator += dt
	if self.lodAccumulator >= self.tuning.lodCheckInterval then
		self.lodAccumulator = 0
		checkLod = true
	end

	local sharedLodOrigin: Vector3? = nil
	if checkLod then
		if self.lodReference ~= nil then
			if typeof(self.lodReference) == "function" then
				local ok, out = pcall(self.lodReference)
				if ok then
					sharedLodOrigin = resolveReferencePosition(out)
				end
			else
				sharedLodOrigin = resolveReferencePosition(self.lodReference)
			end
		end
		if sharedLodOrigin == nil and RunService:IsClient() and Workspace.CurrentCamera then
			sharedLodOrigin = Workspace.CurrentCamera.CFrame.Position
		end
		if sharedLodOrigin == nil then
			sharedLodOrigin = firstPlayerPosition()
		end
	end

	for i = #self.activeIds, 1, -1 do
		local id = self.activeIds[i]
		if id then
			local slot = self.slotById[id]
			if slot and slot.active then
				self:_updateSlot(slot, dt, tnow, checkLod, sharedLodOrigin)
			end
		end
	end
end

function Rubble:Spawn(paramsRaw: SpawnParams?): BasePart?
	if self.destroyed then
		return nil
	end
	if self.spawnBudget <= 0 then
		self.totalDropped += 1
		return nil
	end
	self.spawnBudget -= 1

	local params = if typeof(paramsRaw) == "table" then paramsRaw else {}
	local slot = self:_acquireSlot()
	if slot == nil then
		self.totalDropped += 1
		return nil
	end

	local sizeRaw = g(params, "size", "Size")
	local size: Vector3
	if sizeRaw ~= nil then
		if typeof(sizeRaw) == "number" then
			size = Vector3.new(sizeRaw, sizeRaw, sizeRaw)
		else
			size = sanitizeVector3(sizeRaw, self.templateSize)
		end
	else
		local scale =
			n(g(params, "scale", "Scale"), self.tuning.defaultScale, self.tuning.minScale, self.tuning.maxScale)
		local scaleRange = g(params, "scaleRange", "ScaleRange")
		if scaleRange ~= nil then
			local lo, hi = resolveRange(scaleRange, self.tuning.minScale, self.tuning.maxScale)
			scale = self.random:NextNumber(lo, hi)
		end
		size = self.templateSize * scale
	end
	size = Vector3.new(
		math.clamp(math.abs(size.X), self.tuning.minSize, self.tuning.maxSize),
		math.clamp(math.abs(size.Y), self.tuning.minSize, self.tuning.maxSize),
		math.clamp(math.abs(size.Z), self.tuning.minSize, self.tuning.maxSize)
	)

	local cframe = sanitizeCFrame(
		g(params, "initialCFrame", "InitialCFrame"),
		sanitizeCFrame(g(params, "cframe", "CFrame"), CFrame.new())
	)
	local material = sanitizeMaterial(g(params, "material", "Material"), self.templateMaterial)
	local color = sanitizeColor(g(params, "color", "Color"), self.templateColor)
	local transparency = n(g(params, "transparency", "Transparency"), self.templateTransparency, 0, 1)
	local customPhysicalProperties = resolvePhysical(
		g(params, "customPhysicalProperties", "CustomPhysicalProperties"),
		g(params, "massOverride", "MassOverride"),
		size,
		self.templatePhysical
	)
	local impactForce = sanitizeVector3(g(params, "impactForce", "ImpactForce"), ZERO)
	local impulse = sanitizeVector3(g(params, "impulse", "Impulse"), ZERO)
		+ impactForce * self.tuning.forceToImpulseSeconds
	impulse = clampMag(impulse, self.tuning.maxImpulse)
	local angularImpulse =
		clampMag(sanitizeVector3(g(params, "angularImpulse", "AngularImpulse"), ZERO), self.tuning.maxAngularImpulse)
	local anchored = b(g(params, "anchored", "Anchored"), false)
	local enableGravity = b(g(params, "enableGravity", "EnableGravity"), true)
	local visualOnly = b(g(params, "visualOnly", "VisualOnly"), self.visualOnly)
	local canCollide = b(g(params, "canCollide", "CanCollide"), self.tuning.defaultCanCollide)
	local canTouch = if visualOnly then false else b(g(params, "canTouch", "CanTouch"), self.tuning.defaultCanTouch)
	local canQuery = if visualOnly then false else b(g(params, "canQuery", "CanQuery"), self.tuning.defaultCanQuery)
	local collisionGroup = s(g(params, "collisionGroup", "CollisionGroup"), self.activeGroup)
	local lifetime = n(
		g(params, "lifetime", "Lifetime"),
		self.tuning.defaultLifetime,
		self.tuning.minLifetime,
		self.tuning.maxLifetime
	)
	local canFling = b(g(params, "canFling", "CanFling"), false)
	local fadeOut = b(g(params, "fadeOut", "FadeOut"), self.tuning.defaultFadeOut)
	local fadeDuration = math.min(
		n(g(params, "fadeDuration", "FadeDuration"), self.tuning.fadeDuration, 0, self.tuning.maxLifetime),
		lifetime
	)
	local flingReflectionScale =
		n(g(params, "flingReflectionScale", "FlingReflectionScale"), self.tuning.flingReflectionScale, 0, 2)
	local maxFlingBounces =
		math.floor(n(g(params, "maxFlingBounces", "MaxFlingBounces"), self.tuning.maxFlingBounces, 0, 20))

	local part = slot.part
	slot.token += 1
	slot.active = true
	slot.expiresAt = now() + lifetime
	slot.baseTransparency = transparency
	slot.fadeOut = fadeOut
	slot.fadeDuration = fadeDuration
	slot.canFling = canFling
	slot.flingBounces = 0
	slot.maxFlingBounces = maxFlingBounces
	slot.flingReflectionScale = flingReflectionScale
	slot.noGravity = not enableGravity
	slot.visualOnly = visualOnly
	slot.prevPos = cframe.Position
	slot.requestedAnchored = anchored
	slot.requestedCanCollide = canCollide
	slot.requestedCanTouch = canTouch
	slot.requestedCanQuery = canQuery
	slot.requestedCollisionGroup = collisionGroup
	slot.lodFar = false
	slot.lodReference = g(params, "lodReference", "LodReference")

	part.Parent = self.inactive
	part.AssemblyLinearVelocity = ZERO
	part.AssemblyAngularVelocity = ZERO
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Reflectance = self.templateReflectance
	part.CastShadow = self.templateCastShadow
	part.CustomPhysicalProperties = customPhysicalProperties
	part.CollisionGroup = collisionGroup
	part.Parent = self.active

	part.CanCollide = canCollide
	part.CanTouch = canTouch
	part.CanQuery = canQuery
	part.Anchored = slot.requestedAnchored

	if not part.Anchored then
		if RunService:IsServer() and self.tuning.autoServerNetworkOwnership and not visualOnly then
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
		if impulse.Magnitude > 0 then
			part:ApplyImpulse(impulse)
		end
		if angularImpulse.Magnitude > 0 then
			part:ApplyAngularImpulse(angularImpulse)
		end
		part.AssemblyLinearVelocity = clampMag(part.AssemblyLinearVelocity, self.tuning.maxVelocity)
	end

	self:_heapPush({ expiresAt = slot.expiresAt, slotId = slot.id, token = slot.token })
	self:_activeAdd(slot)
	self.totalSpawns += 1

	local mirror = b(g(params, "mirror", "Mirror"), true)
	if mirror and not visualOnly and RunService:IsServer() and self.mirrorRemote and self.mirrorSend then
		self.mirrorRemote:FireAllClients("RubbleSpawn", {
			Size = size,
			CFrame = cframe,
			Material = material,
			Color = color,
			Transparency = transparency,
			Impulse = impulse,
			AngularImpulse = angularImpulse,
			Anchored = anchored,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Lifetime = lifetime,
			CanFling = canFling,
			EnableGravity = enableGravity,
			FadeOut = fadeOut,
			FadeDuration = fadeDuration,
			MaxFlingBounces = maxFlingBounces,
			FlingReflectionScale = flingReflectionScale,
			Mirror = false,
		})
	end

	return part
end

function Rubble:Recycle(target: any): boolean
	local slot: Slot? = nil
	if typeof(target) == "number" then
		slot = self.slotById[math.floor(target)]
	elseif typeof(target) == "Instance" and target:IsA("BasePart") then
		local id = self.idByPart[target]
		if id ~= nil then
			slot = self.slotById[id]
		end
	end
	if slot == nil then
		return false
	end
	self:_recycleSlot(slot)
	return true
end

function Rubble:RecycleAll()
	for i = #self.activeIds, 1, -1 do
		local id = self.activeIds[i]
		local slot = if id then self.slotById[id] else nil
		if slot and slot.active then
			self:_recycleSlot(slot)
		end
	end
	if RunService:IsServer() and self.mirrorRemote and self.mirrorSend then
		self.mirrorRemote:FireAllClients("RubbleRecycleAll")
	end
end

function Rubble:GetStats(): { [string]: number }
	return {
		active = #self.activeIds,
		pooled = self.freeTop,
		allocated = self.nextSlotId,
		peakActive = self.peakActive,
		totalSpawns = self.totalSpawns,
		totalRecycles = self.totalRecycles,
		totalDropped = self.totalDropped,
	}
end

function Rubble:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.heartbeat then
		self.heartbeat:Disconnect()
		self.heartbeat = nil
	end
	if self.mirrorConnection then
		self.mirrorConnection:Disconnect()
		self.mirrorConnection = nil
	end
	self:RecycleAll()
	for _, slot in self.slotById do
		if slot.part.Parent ~= nil then
			slot.part:Destroy()
		end
	end
	table.clear(self.slotById)
	table.clear(self.idByPart)
	table.clear(self.free)
	table.clear(self.activeIds)
	table.clear(self.activeIndex)
	table.clear(self.expiryHeap)
	if self.template and self.template.Parent == nil then
		self.template:Destroy()
	end
end

Rubble.DefaultTuning = DEFAULT_TUNING

Rubble.new = Rubble.New

return Rubble
