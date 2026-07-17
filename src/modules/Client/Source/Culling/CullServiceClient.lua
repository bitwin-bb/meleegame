local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ServiceBag = require("ServiceBag")
local Maid = require("Maid")
local Queue = require("Queue")
local Signal = require("Signal")

local CullClient = require("CullClient")
local CullUtil = require("CullUtil")

type TileBounds = CullUtil.TileBounds

local CullServiceClient = {}
CullServiceClient.ServiceName = "CullServiceClient"

local CULL_REFRESH_INTERVAL_SECONDS = 1 / 30
local MAX_TILE_RECONCILES_PER_HEARTBEAT = 256
local MAX_TILE_RECONCILES_PER_CLIENT = 32
local TILE_RECONCILE_TIME_BUDGET_SECONDS = 0.0025
local DEFAULT_VIEWPORT_MARGIN_PIXELS = 384
local DEFAULT_LOAD_MARGIN_PIXELS = 768
local DEFAULT_COLLISION_MARGIN_PIXELS = 384
local DEFAULT_MAX_TILE_SPAN = 1024

local function getOptionValue(options: any, name: string, fallback: any): any
	local callback = options[name]
	if typeof(callback) ~= "function" then
		return fallback
	end
	local value = callback()
	return if value ~= nil then value else fallback
end

function CullServiceClient.Init(self: any, serviceBag: ServiceBag.ServiceBag?)
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	if self._maid ~= nil then
		return
	end

	self._maid = Maid.new()
	self._clients = {}
	self._clientsByKey = {}
	self._retiredClients = {}
	self._queuedClients = {}
	self._warnedClients = {}
	self._clientQueue = Queue.new()
	self._options = nil
	self._visibleBounds = nil
	self._loadBounds = nil
	self._collisionBounds = nil
	self._refreshAccumulator = CULL_REFRESH_INTERVAL_SECONDS
	self.visibleBoundsChanged = Signal.new()
	self.loadBoundsChanged = Signal.new()
	self.collisionBoundsChanged = Signal.new()
	self._maid:GiveTask(self.visibleBoundsChanged)
	self._maid:GiveTask(self.loadBoundsChanged)
	self._maid:GiveTask(self.collisionBoundsChanged)
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:OnHeartbeat(deltaTime)
	end))
end

function CullServiceClient.Configure(self: any, optionsRaw: any?)
	if self._maid == nil then
		self:Init()
	end

	self._options = if typeof(optionsRaw) == "table" then optionsRaw else nil
	self._refreshAccumulator = CULL_REFRESH_INTERVAL_SECONDS
	if self._options == nil then
		self:SetVisibleBounds(nil)
		self:SetLoadBounds(nil)
		self:SetCollisionBounds(nil)
		return
	end
	self:RefreshVisibleBounds()
end

function CullServiceClient.IsConfigured(self: any): boolean
	return self._options ~= nil
end

function CullServiceClient.QueueClient(self: any, cullClient: any)
	if self._clients[cullClient] ~= true or self._queuedClients[cullClient] == true or not cullClient:HasWork() then
		return
	end

	self._queuedClients[cullClient] = true
	self._clientQueue:PushRight(cullClient)
end

function CullServiceClient.Register(self: any, cullClient: any)
	if self._maid == nil then
		self:Init()
	end
	if self._clients[cullClient] == true then
		return
	end

	self._clients[cullClient] = true
	self._retiredClients[cullClient] = nil
	local key = cullClient:GetKey()
	if key ~= nil then
		local clientsForKey = self._clientsByKey[key]
		if clientsForKey == nil then
			clientsForKey = {}
			self._clientsByKey[key] = clientsForKey
		end
		clientsForKey[cullClient] = true
	end
	cullClient:SetVisibleBounds(self._visibleBounds)
	self:QueueClient(cullClient)
end

function CullServiceClient.Unregister(self: any, cullClient: any)
	if self._clients == nil then
		return
	end
	self._clients[cullClient] = nil
	self._retiredClients[cullClient] = nil
	self._queuedClients[cullClient] = nil
	self._warnedClients[cullClient] = nil
	local key = cullClient:GetKey()
	if key ~= nil then
		local clientsForKey = self._clientsByKey[key]
		if clientsForKey ~= nil then
			clientsForKey[cullClient] = nil
			if next(clientsForKey) == nil then
				self._clientsByKey[key] = nil
			end
		end
	end
end

function CullServiceClient.CreateClient(self: any, optionsRaw: any?): any
	local cullClient = CullClient.new(optionsRaw)
	self:Register(cullClient)
	return cullClient
end

function CullServiceClient.RefreshClient(self: any, cullClient: any)
	if self._clients[cullClient] ~= true then
		return
	end
	cullClient:Refresh()
	self:QueueClient(cullClient)
end

function CullServiceClient.HasActiveTiles(self: any, keyRaw: any): boolean
	if typeof(keyRaw) ~= "string" or self._clientsByKey == nil then
		return false
	end
	local clientsForKey = self._clientsByKey[keyRaw]
	if clientsForKey == nil then
		return false
	end
	for cullClient in clientsForKey do
		if cullClient:GetActiveTileCount() > 0 then
			return true
		end
	end
	return false
end

function CullServiceClient.RetireKey(self: any, keyRaw: any): boolean
	if typeof(keyRaw) ~= "string" or self._clientsByKey == nil then
		return false
	end
	local clientsForKey = self._clientsByKey[keyRaw]
	if clientsForKey == nil then
		return false
	end

	local retired = false
	for cullClient in clientsForKey do
		self._retiredClients[cullClient] = true
		cullClient:SetVisibleBounds(nil)
		self:QueueClient(cullClient)
		retired = true
	end
	return retired
end

function CullServiceClient.RestoreKey(self: any, keyRaw: any): boolean
	if typeof(keyRaw) ~= "string" or self._clientsByKey == nil then
		return false
	end
	local clientsForKey = self._clientsByKey[keyRaw]
	if clientsForKey == nil then
		return false
	end

	local restored = false
	for cullClient in clientsForKey do
		if self._retiredClients[cullClient] == true then
			self._retiredClients[cullClient] = nil
			cullClient:SetVisibleBounds(self._visibleBounds)
			self:QueueClient(cullClient)
			restored = true
		end
	end
	return restored
end

function CullServiceClient.SetVisibleBounds(self: any, nextBounds: TileBounds?): boolean
	if CullUtil.BoundsEqual(self._visibleBounds, nextBounds) then
		return false
	end

	self._visibleBounds = CullUtil.CloneBounds(nextBounds)
	for cullClient in self._clients do
		local clientBounds = if self._retiredClients[cullClient] == true then nil else nextBounds
		if cullClient:SetVisibleBounds(clientBounds) then
			self:QueueClient(cullClient)
		end
	end
	self.visibleBoundsChanged:Fire(CullUtil.CloneBounds(nextBounds))
	return true
end

function CullServiceClient.SetLoadBounds(self: any, nextBounds: TileBounds?): boolean
	if CullUtil.BoundsEqual(self._loadBounds, nextBounds) then
		return false
	end

	self._loadBounds = CullUtil.CloneBounds(nextBounds)
	self.loadBoundsChanged:Fire(CullUtil.CloneBounds(nextBounds))
	return true
end

function CullServiceClient.SetCollisionBounds(self: any, nextBounds: TileBounds?): boolean
	if CullUtil.BoundsEqual(self._collisionBounds, nextBounds) then
		return false
	end

	self._collisionBounds = CullUtil.CloneBounds(nextBounds)
	self.collisionBoundsChanged:Fire(CullUtil.CloneBounds(nextBounds))
	return true
end

function CullServiceClient.RefreshVisibleBounds(self: any): boolean
	local options = self._options
	if options == nil then
		return false
	end

	local camera = Workspace.CurrentCamera
	local worldOrigin = getOptionValue(options, "getWorldOrigin", Vector3.zero)
	local basePlaneX = getOptionValue(options, "getBasePlaneX", 0)
	local tileSize = getOptionValue(options, "getTileSize", 1)
	local maxTileSpan = (options :: any).maxTileSpan or DEFAULT_MAX_TILE_SPAN
	local viewportMarginPixels = (options :: any).viewportMarginPixels or DEFAULT_VIEWPORT_MARGIN_PIXELS
	local loadMarginPixels = (options :: any).loadMarginPixels or DEFAULT_LOAD_MARGIN_PIXELS
	local collisionMarginPixels = (options :: any).collisionMarginPixels or DEFAULT_COLLISION_MARGIN_PIXELS
	local nextVisibleBounds =
		CullUtil.GetCameraTileBounds(camera, worldOrigin, basePlaneX, tileSize, viewportMarginPixels, maxTileSpan)
	if nextVisibleBounds == nil then
		return false
	end

	local nextLoadBounds = if loadMarginPixels == viewportMarginPixels
		then nextVisibleBounds
		else CullUtil.GetCameraTileBounds(camera, worldOrigin, basePlaneX, tileSize, loadMarginPixels, maxTileSpan)
	if nextLoadBounds == nil then
		nextLoadBounds = nextVisibleBounds
	end
	local nextCollisionBounds = if collisionMarginPixels == loadMarginPixels
		then nextLoadBounds
		else CullUtil.GetCameraTileBounds(
			camera,
			worldOrigin,
			basePlaneX,
			tileSize,
			collisionMarginPixels,
			maxTileSpan
		)
	if nextCollisionBounds == nil then
		nextCollisionBounds = nextLoadBounds
	end

	local visibleChanged = self:SetVisibleBounds(nextVisibleBounds)
	local loadChanged = self:SetLoadBounds(nextLoadBounds)
	local collisionChanged = self:SetCollisionBounds(nextCollisionBounds)
	return visibleChanged or loadChanged or collisionChanged
end

function CullServiceClient.ProcessQueue(self: any): number
	local processed = 0
	local deadline = os.clock() + TILE_RECONCILE_TIME_BUDGET_SECONDS
	while processed < MAX_TILE_RECONCILES_PER_HEARTBEAT and os.clock() < deadline and not self._clientQueue:IsEmpty() do
		local cullClient = self._clientQueue:PopLeft()
		self._queuedClients[cullClient] = nil
		if self._clients[cullClient] ~= true then
			continue
		end

		local remaining = MAX_TILE_RECONCILES_PER_HEARTBEAT - processed
		local ok, stepResult = xpcall(function()
			return cullClient:Step(math.min(remaining, MAX_TILE_RECONCILES_PER_CLIENT), deadline)
		end, debug.traceback)
		if not ok then
			cullClient:Reconcile()
			if self._warnedClients[cullClient] ~= true then
				self._warnedClients[cullClient] = true
				warn(`cull client step failed\n{stepResult}`)
			end
			self:QueueClient(cullClient)
			break
		end

		self._warnedClients[cullClient] = nil
		processed += stepResult
		self:QueueClient(cullClient)
	end
	return processed
end

function CullServiceClient.OnHeartbeat(self: any, deltaTime: number)
	self._refreshAccumulator += deltaTime
	if self._refreshAccumulator >= CULL_REFRESH_INTERVAL_SECONDS then
		self._refreshAccumulator %= CULL_REFRESH_INTERVAL_SECONDS
		self:RefreshVisibleBounds()
	end

	self:ProcessQueue()
end

function CullServiceClient.GetVisibleBounds(self: any): TileBounds?
	return CullUtil.CloneBounds(self._visibleBounds)
end

function CullServiceClient.GetLoadBounds(self: any): TileBounds?
	return CullUtil.CloneBounds(self._loadBounds)
end

function CullServiceClient.GetCollisionBounds(self: any): TileBounds?
	return CullUtil.CloneBounds(self._collisionBounds)
end

function CullServiceClient.Destroy(self: any)
	self._serviceBag = nil
	if self._maid == nil then
		return
	end

	local clients = self._clients
	self._clients = {}
	self._clientsByKey = {}
	self._retiredClients = {}
	self._queuedClients = {}
	self._warnedClients = {}
	self._clientQueue = Queue.new()
	for cullClient in clients do
		cullClient:Destroy()
	end
	self._visibleBounds = nil
	self._loadBounds = nil
	self._collisionBounds = nil
	self._options = nil
	self._maid:DoCleaning()
	self._maid = nil
end

return CullServiceClient
