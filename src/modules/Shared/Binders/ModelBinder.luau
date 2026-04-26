--!strict

local Players = game:GetService("Players")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)
local Maid = loader("Maid")
local InstanceUtils = require(script:FindFirstAncestor("game").Shared.Modules.Platform.InstanceUtils)
local TagBinder = require(script.Parent.TagBinder)

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

export type BinderContext = {
	tags: { string }?,
	serviceBag: any?,
}

local ModelBinder = {}
ModelBinder.__index = ModelBinder

export type ModelBinder = typeof(setmetatable(
	{} :: {
		instance: Instance,
		janitor: MaidClass,
		context: BinderContext?,
		destroyed: boolean,
	},
	ModelBinder
))

local function createJanitor(): MaidClass
	return Maid.new() :: MaidClass
end

function ModelBinder.CollectBaseParts(instanceRaw: any): { BasePart }
	if typeof(instanceRaw) ~= "Instance" then
		return {}
	end

	local instance = instanceRaw :: Instance
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
	if typeof(instanceRaw) ~= "Instance" then
		return {}
	end

	local instance = instanceRaw :: Instance
	local lights = {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
			lights[#lights + 1] = descendant
		end
	end
	return lights
end

function ModelBinder.BindTouchedParts(
	instanceRaw: any,
	janitor: any,
	callback: (part: BasePart, other: BasePart) -> ()
)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end

	local bound = {} :: { [BasePart]: boolean }
	local instance = instanceRaw :: Instance

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

function ModelBinder.ResolveModel(instanceRaw: any): Model?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	if instance:IsA("Model") then
		return instance
	end

	return instance:FindFirstAncestorOfClass("Model")
end

function ModelBinder.ResolveHumanoid(instanceRaw: any): Humanoid?
	local model = ModelBinder.ResolveModel(instanceRaw)
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function ModelBinder.ResolvePlayer(instanceRaw: any): Player?
	local model = ModelBinder.ResolveModel(instanceRaw)
	if model == nil then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

function ModelBinder.ResolveRootPart(instanceRaw: any): BasePart?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	if instance:IsA("BasePart") then
		return instance
	end

	return InstanceUtils.resolveInstanceRootPart(instance, false)
end

function ModelBinder.ResolveAdornee(instanceRaw: any): Instance?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	if instance:IsA("Model") then
		return instance
	end

	local model = instance:FindFirstAncestorOfClass("Model")
	if model ~= nil then
		return model
	end

	return ModelBinder.ResolveRootPart(instance)
end

function ModelBinder.ResolveWorldPosition(instanceRaw: any): Vector3?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end

	local rootPart = ModelBinder.ResolveRootPart(instance)
	if rootPart ~= nil then
		return rootPart.Position
	end

	return nil
end

function ModelBinder.new(instanceRaw: any, contextRaw: any, classRaw: any?): ModelBinder
	if typeof(instanceRaw) ~= "Instance" then
		error("ModelBinder.new expects an Instance")
	end

	local class = if typeof(classRaw) == "table" then classRaw else ModelBinder
	local self = setmetatable({
		instance = instanceRaw,
		janitor = createJanitor(),
		context = if typeof(contextRaw) == "table" then contextRaw else nil,
		destroyed = false,
	}, class)

	self.janitor:GiveTask(self.instance.Destroying:Connect(function()
		self:Destroy()
	end))

	return self
end

function ModelBinder.GetModel(self: ModelBinder): Model?
	local instance = self.instance
	if instance:IsA("Model") then
		return instance
	end
	return instance:FindFirstAncestorOfClass("Model")
end

function ModelBinder.GetHumanoid(self: ModelBinder): Humanoid?
	local model = self:GetModel()
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function ModelBinder.GetRootPart(self: ModelBinder): BasePart?
	local instance = self.instance
	if instance:IsA("BasePart") then
		return instance
	end

	local model = self:GetModel()
	if model ~= nil then
		return InstanceUtils.resolveModelRootPart(model, false)
	end

	return InstanceUtils.resolveInstanceRootPart(instance, false)
end

function ModelBinder.HasTag(self: ModelBinder, tagRaw: any): boolean
	return TagBinder.hasTag(self.instance, tagRaw)
end

function ModelBinder.GetMatchedTags(self: ModelBinder): { string }
	local context = self.context
	if context == nil then
		return {}
	end

	return TagBinder.getMatchedTags(self.instance, context.tags)
end

function ModelBinder.Connect(self: ModelBinder, signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(callback)
	self.janitor:GiveTask(connection)
	return connection
end

function ModelBinder.ObserveAttribute(
	self: ModelBinder,
	attributeName: string,
	callback: (nextValue: any, instance: Instance) -> ()
): RBXScriptConnection
	callback(self.instance:GetAttribute(attributeName), self.instance)
	return self:Connect(self.instance:GetAttributeChangedSignal(attributeName), function()
		callback(self.instance:GetAttribute(attributeName), self.instance)
	end)
end

function ModelBinder.AddCleanup(self: ModelBinder, cleanup: any, ...: any)
	return self.janitor:GiveTask(cleanup)
end

function ModelBinder.Destroy(self: ModelBinder)
	if self.destroyed then
		return
	end

	self.destroyed = true
	local cleanupMethod = (getmetatable(self) :: any).Cleanup
	if typeof(cleanupMethod) == "function" then
		pcall(cleanupMethod, self)
	end

	self.janitor:Destroy()
end

ModelBinder.getModel = ModelBinder.GetModel
ModelBinder.getHumanoid = ModelBinder.GetHumanoid
ModelBinder.getRootPart = ModelBinder.GetRootPart
ModelBinder.collectBaseParts = ModelBinder.CollectBaseParts
ModelBinder.collectLights = ModelBinder.CollectLights
ModelBinder.bindTouchedParts = ModelBinder.BindTouchedParts
ModelBinder.resolveModel = ModelBinder.ResolveModel
ModelBinder.resolveHumanoid = ModelBinder.ResolveHumanoid
ModelBinder.resolvePlayer = ModelBinder.ResolvePlayer
ModelBinder.resolveRootPart = ModelBinder.ResolveRootPart
ModelBinder.resolveAdornee = ModelBinder.ResolveAdornee
ModelBinder.resolveWorldPosition = ModelBinder.ResolveWorldPosition
ModelBinder.hasTag = ModelBinder.HasTag
ModelBinder.getMatchedTags = ModelBinder.GetMatchedTags
ModelBinder.connect = ModelBinder.Connect
ModelBinder.observeAttribute = ModelBinder.ObserveAttribute
ModelBinder.addCleanup = ModelBinder.AddCleanup
ModelBinder.destroy = ModelBinder.Destroy

return ModelBinder
