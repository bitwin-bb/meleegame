local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local BaseObject = require("BaseObject")
local InstanceUtils = require("InstanceUtils")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TagBinder = require("TagBinder")

export type BinderDependencies = {
	AudioServiceClient: any?,
	AutotileRenderServiceClient: any?,
	WallAutotileServiceClient: any?,
	BossServiceServer: any?,
	BuildServiceClient: any?,
	GoreServiceServer: any?,
	HpServiceServer: any?,
	InventoryServiceServer: any?,
	LiquidServiceServer: any?,
	LootServiceServer: any?,
	MagicServiceServer: any?,
	MeleeServiceServer: any?,
	NpcServiceServer: any?,
	WindFoliageServiceClient: any?,
}

export type BinderContext = {
	dependencies: BinderDependencies?,
	tags: { string }?,
	serviceBag: ServiceBag.ServiceBag?,
}

local ModelBinder = setmetatable({}, BaseObject)
ModelBinder.ClassName = "ModelBinder"
ModelBinder.__index = ModelBinder

export type ModelBinder =
	typeof(setmetatable(
		{} :: {
			_obj: Instance,
			_maid: Maid.Maid,
			_serviceBag: ServiceBag.ServiceBag?,
			instance: Instance,
			janitor: Maid.Maid,
			context: BinderContext?,
			destroyed: boolean,
		},
		ModelBinder
	))
	& BaseObject.BaseObject

local function getBoundInstance(targetRaw: any): Instance?
	if typeof(targetRaw) == "Instance" then
		return targetRaw
	end

	if typeof(targetRaw) == "table" then
		local instance = (targetRaw :: any)._obj or (targetRaw :: any).instance
		if typeof(instance) == "Instance" then
			return instance
		end
	end

	return nil
end

function ModelBinder.CollectBaseParts(instanceRaw: any): { BasePart }
	local instance = getBoundInstance(instanceRaw)
	if instance == nil then
		return {}
	end

	if instance:IsA("BasePart") then
		return { instance }
	end

	local parts = {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end
	return parts
end

function ModelBinder.CollectLights(instanceRaw: any): { Instance }
	local instance = getBoundInstance(instanceRaw)
	if instance == nil then
		return {}
	end

	local lights: { Instance } = {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
			lights[#lights + 1] = descendant
		end
	end
	return lights
end

function ModelBinder.BindTouchedParts(instanceRaw: any, janitor: any, callback: (part: BasePart, other: BasePart) -> ())
	local instance = getBoundInstance(instanceRaw)
	if instance == nil then
		return
	end

	local bound = {} :: { [BasePart]: boolean }

	local function bindPart(part: BasePart)
		if bound[part] == true then
			return
		end

		bound[part] = true
		janitor:GiveTask(part.Touched:Connect(function(other: BasePart)
			callback(part, other)
		end))
	end

	for _, part in ModelBinder.CollectBaseParts(instance) do
		bindPart(part)
	end

	janitor:GiveTask(instance.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			bindPart(descendant)
		end
	end))
end

function ModelBinder.GetPlayer(instanceRaw: any): Player?
	local model = ModelBinder.GetModel(instanceRaw)
	if model == nil then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

function ModelBinder.GetAdornee(instanceRaw: any): Instance?
	local instance = getBoundInstance(instanceRaw)
	if instance == nil then
		return nil
	end

	if instance:IsA("Model") then
		return instance
	end

	local model = instance:FindFirstAncestorOfClass("Model")
	if model ~= nil then
		return model
	end

	return ModelBinder.GetRootPart(instance)
end

function ModelBinder.GetWorldPosition(instanceRaw: any): Vector3?
	local instance = getBoundInstance(instanceRaw)
	if instance == nil then
		return nil
	end

	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end

	local rootPart = ModelBinder.GetRootPart(instance)
	if rootPart ~= nil then
		return rootPart.Position
	end

	return nil
end

function ModelBinder.new(instanceRaw: any, contextRaw: any, classRaw: any?): any
	if typeof(instanceRaw) ~= "Instance" then
		error("ModelBinder.new expects an Instance")
	end

	local class = if typeof(classRaw) == "table" then classRaw else ModelBinder
	local context = if typeof(contextRaw) == "table" then contextRaw :: BinderContext else nil
	local self = setmetatable(BaseObject.new(instanceRaw) :: any, class)
	self.instance = instanceRaw
	self.janitor = self._maid
	self.context = context
	self._serviceBag = if context ~= nil then context.serviceBag else nil
	self.destroyed = false

	self._maid:GiveTask(self._obj.Destroying:Connect(function()
		self:Destroy()
	end))

	return self
end

function ModelBinder.GetModel(instanceRaw: any): Model?
	local instance = getBoundInstance(instanceRaw)
	if instance == nil then
		return nil
	end

	if instance:IsA("Model") then
		return instance
	end
	return instance:FindFirstAncestorOfClass("Model")
end

function ModelBinder.GetHumanoid(instanceRaw: any): Humanoid?
	local model = ModelBinder.GetModel(instanceRaw)
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function ModelBinder.GetRootPart(instanceRaw: any): BasePart?
	local instance = getBoundInstance(instanceRaw)
	if instance == nil then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	local model = ModelBinder.GetModel(instanceRaw)
	if model ~= nil then
		return InstanceUtils.GetModelRootPart(model, false)
	end

	return InstanceUtils.GetInstanceRootPart(instance, false)
end

function ModelBinder.HasTag(self: ModelBinder, tagRaw: any): boolean
	return TagBinder.hasTag(self._obj, tagRaw)
end

function ModelBinder.GetMatchedTags(self: ModelBinder): { string }
	local context = self.context
	if context == nil then
		return {}
	end

	return TagBinder.getMatchedTags(self._obj, context.tags)
end

function ModelBinder.GetDependencies(self: ModelBinder): BinderDependencies
	local context = assert(self.context, "binder context is unavailable")
	return assert(context.dependencies, "binder dependencies are unavailable")
end

function ModelBinder.Connect(self: ModelBinder, signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(callback)
	self._maid:GiveTask(connection)
	return connection
end

function ModelBinder.ObserveAttribute(
	self: ModelBinder,
	attributeName: string,
	callback: (nextValue: any, instance: Instance) -> ()
): RBXScriptConnection
	callback(self._obj:GetAttribute(attributeName), self._obj)
	return self:Connect(self._obj:GetAttributeChangedSignal(attributeName), function()
		callback(self._obj:GetAttribute(attributeName), self._obj)
	end)
end

function ModelBinder.AddCleanup(self: ModelBinder, cleanup: any)
	return self._maid:GiveTask(cleanup)
end

function ModelBinder.Destroy(self: ModelBinder)
	if self.destroyed then
		return
	end

	self.destroyed = true
	local cleanupMethod = (getmetatable(self) :: any).Cleanup
	local cleanupOk = true
	local cleanupError = nil
	if typeof(cleanupMethod) == "function" then
		cleanupOk, cleanupError = pcall(cleanupMethod, self)
	end

	self._maid:DoCleaning()
	if not cleanupOk then
		error(cleanupError)
	end
end
return ModelBinder
