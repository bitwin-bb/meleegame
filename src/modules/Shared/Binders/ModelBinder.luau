local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local InstanceUtils = require("InstanceUtils")
local Maid = require("Maid")
local TagBinder = require("TagBinder")

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

local function GetBoundInstance(targetRaw: any): Instance?
	if typeof(targetRaw) == "Instance" then
		return targetRaw
	end

	if typeof(targetRaw) == "table" then
		local instance = (targetRaw :: any).instance
		if typeof(instance) == "Instance" then
			return instance
		end
	end

	return nil
end

function ModelBinder.CollectBaseParts(instanceRaw: any): { BasePart }
	local instance = GetBoundInstance(instanceRaw)
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
	local instance = GetBoundInstance(instanceRaw)
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
	local instance = GetBoundInstance(instanceRaw)
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

function ModelBinder.GetModel(instanceRaw: any): Model?
	local instance = GetBoundInstance(instanceRaw)
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

function ModelBinder.GetPlayer(instanceRaw: any): Player?
	local model = ModelBinder.GetModel(instanceRaw)
	if model == nil then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

function ModelBinder.GetRootPart(instanceRaw: any): BasePart?
	local instance = GetBoundInstance(instanceRaw)
	if instance == nil then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	return InstanceUtils.GetInstanceRootPart(instance, false)
end

function ModelBinder.GetAdornee(instanceRaw: any): Instance?
	local instance = GetBoundInstance(instanceRaw)
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
	local instance = GetBoundInstance(instanceRaw)
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
	local instance = GetBoundInstance(self)
	if instance == nil then
		return nil
	end

	if instance:IsA("Model") then
		return instance
	end
	return instance:FindFirstAncestorOfClass("Model")
end

function ModelBinder.GetHumanoid(self: ModelBinder): Humanoid?
	local model = ModelBinder.GetModel(self)
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function ModelBinder.GetRootPart(self: ModelBinder): BasePart?
	local instance = GetBoundInstance(self)
	if instance == nil then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	local model = ModelBinder.GetModel(self)
	if model ~= nil then
		return InstanceUtils.GetModelRootPart(model, false)
	end

	return InstanceUtils.GetInstanceRootPart(instance, false)
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
return ModelBinder
