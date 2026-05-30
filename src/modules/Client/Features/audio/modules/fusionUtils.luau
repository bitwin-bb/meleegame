--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Maid = loader("Maid")

local Children = Fusion.Children

local FusionUtils = {}

export type AttributeMap = { [string]: any }
export type CallbackMap = { [string]: (...any) -> any }
export type OutputMap = { [string]: any }

export type InstanceWrapperConfig = {
	name: string?,
	parent: Instance?,
	children: any?,
	attributes: AttributeMap?,
	attributeChanges: CallbackMap?,
	attributeOuts: OutputMap?,
	events: CallbackMap?,
	changes: CallbackMap?,
	outs: OutputMap?,
	props: { [any]: any }?,
}

type MaidPackage = {
	new: () -> any,
}

local function resolveMaidPackage(maidPackageRaw: any): MaidPackage
	if typeof(maidPackageRaw) == "table" and typeof((maidPackageRaw :: any).new) == "function" then
		return maidPackageRaw :: MaidPackage
	end

	return Maid :: MaidPackage
end

local function resolveConfig(configRaw: InstanceWrapperConfig?): InstanceWrapperConfig
	if typeof(configRaw) == "table" then
		return configRaw :: InstanceWrapperConfig
	end

	return {} :: any
end

local function resolveClassName(classNameRaw: string): string
	if typeof(classNameRaw) == "string" and classNameRaw ~= "" then
		return classNameRaw
	end

	error("FusionUtils.CreateInstanceWrapper expects a class name", 3)
end

local function resolveDefaultName(defaultNameRaw: string?): string?
	if typeof(defaultNameRaw) == "string" and defaultNameRaw ~= "" then
		return defaultNameRaw
	end

	return nil
end

local function resolveInstance(className: string, instanceRaw: any): Instance?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	if not instance:IsA(className) then
		return nil
	end

	return instance
end

local function copyProps(props: { [any]: any }, propsRaw: { [any]: any }?)
	if typeof(propsRaw) ~= "table" then
		return
	end

	for key, value in propsRaw do
		props[key] = value
	end
end

local function assignName(props: { [any]: any }, nameRaw: any, defaultName: string?)
	if typeof(nameRaw) == "string" and nameRaw ~= "" then
		props.Name = nameRaw
		return
	end

	if props.Name == nil and defaultName ~= nil then
		props.Name = defaultName
	end
end

local function assignParent(props: { [any]: any }, parentRaw: any)
	if typeof(parentRaw) == "Instance" then
		props.Parent = parentRaw
	end
end

local function assignChildren(props: { [any]: any }, childrenRaw: any)
	if childrenRaw ~= nil then
		props[Children] = childrenRaw
	end
end

local function assignAttributes(props: { [any]: any }, attributesRaw: AttributeMap?)
	if typeof(attributesRaw) ~= "table" then
		return
	end

	for key, value in attributesRaw do
		if typeof(key) == "string" then
			props[Fusion.Attribute(key)] = value
		end
	end
end

local function assignEventCallbacks(props: { [any]: any }, eventsRaw: CallbackMap?)
	if typeof(eventsRaw) ~= "table" then
		return
	end

	for eventName, callback in eventsRaw do
		if typeof(eventName) == "string" and type(callback) == "function" then
			props[Fusion.OnEvent(eventName)] = callback
		end
	end
end

local function assignChangeCallbacks(props: { [any]: any }, changesRaw: CallbackMap?)
	if typeof(changesRaw) ~= "table" then
		return
	end

	for propertyName, callback in changesRaw do
		if typeof(propertyName) == "string" and type(callback) == "function" then
			props[Fusion.OnChange(propertyName)] = callback
		end
	end
end

local function assignOutputs(props: { [any]: any }, outsRaw: OutputMap?)
	if typeof(outsRaw) ~= "table" then
		return
	end

	for propertyName, output in outsRaw do
		if typeof(propertyName) == "string" then
			props[Fusion.Out(propertyName)] = output
		end
	end
end

local function assignAttributeChanges(props: { [any]: any }, changesRaw: CallbackMap?)
	if typeof(changesRaw) ~= "table" then
		return
	end

	for attributeName, callback in changesRaw do
		if typeof(attributeName) == "string" and type(callback) == "function" then
			props[Fusion.AttributeChange(attributeName)] = callback
		end
	end
end

local function assignAttributeOutputs(props: { [any]: any }, outsRaw: OutputMap?)
	if typeof(outsRaw) ~= "table" then
		return
	end

	for attributeName, output in outsRaw do
		if typeof(attributeName) == "string" then
			props[Fusion.AttributeOut(attributeName)] = output
		end
	end
end

local function createProps(configRaw: InstanceWrapperConfig?, defaultName: string?): { [any]: any }
	local config = resolveConfig(configRaw)
	local props = {}

	copyProps(props, config.props)
	assignName(props, config.name, defaultName)
	assignParent(props, config.parent)
	assignChildren(props, config.children)
	assignAttributes(props, config.attributes)
	assignEventCallbacks(props, config.events)
	assignChangeCallbacks(props, config.changes)
	assignOutputs(props, config.outs)
	assignAttributeChanges(props, config.attributeChanges)
	assignAttributeOutputs(props, config.attributeOuts)

	return props
end

local function attachOwnedScopeCleanup(instance: Instance, scope: any, maidPackageRaw: any)
	local maidPackage = resolveMaidPackage(maidPackageRaw)
	local maid = maidPackage.new()

	maid:GiveTask(function()
		Fusion.doCleanup(scope)
	end)
	maid:GiveTask(instance.Destroying:Connect(function()
		maid:DoCleaning()
	end))
end

function FusionUtils.CreateWithScope(
	scope: any,
	classNameRaw: string,
	defaultNameRaw: string?,
	configRaw: InstanceWrapperConfig?
): Instance
	local className = resolveClassName(classNameRaw)
	local defaultName = resolveDefaultName(defaultNameRaw)
	local props = createProps(configRaw, defaultName)
	local scopeAny = scope :: any

	if typeof(scopeAny) ~= "table" or typeof(scopeAny.New) ~= "function" then
		error("FusionUtils.CreateWithScope expects a Fusion scope", 2)
	end

	return (scopeAny:New(className))(props) :: Instance
end

function FusionUtils.HydrateWithScope(
	scope: any,
	classNameRaw: string,
	instanceRaw: any,
	configRaw: InstanceWrapperConfig?
): Instance?
	local className = resolveClassName(classNameRaw)
	local instance = resolveInstance(className, instanceRaw)
	if instance == nil then
		return nil
	end

	local props = createProps(configRaw, nil)
	local scopeAny = scope :: any
	if typeof(scopeAny) ~= "table" or typeof(scopeAny.Hydrate) ~= "function" then
		error("FusionUtils.HydrateWithScope expects a Fusion scope", 2)
	end

	return (scopeAny:Hydrate(instance))(props) :: Instance
end

function FusionUtils.Create(
	classNameRaw: string,
	defaultNameRaw: string?,
	configRaw: InstanceWrapperConfig?,
	maidPackageRaw: any?
): Instance
	local scope = Fusion.scoped(Fusion)
	local instance = FusionUtils.CreateWithScope(scope, classNameRaw, defaultNameRaw, configRaw)

	attachOwnedScopeCleanup(instance, scope, maidPackageRaw)

	return instance
end

function FusionUtils.Hydrate(
	classNameRaw: string,
	instanceRaw: any,
	configRaw: InstanceWrapperConfig?,
	maidPackageRaw: any?
): Instance?
	local scope = Fusion.scoped(Fusion)
	local instance = FusionUtils.HydrateWithScope(scope, classNameRaw, instanceRaw, configRaw)
	if instance == nil then
		Fusion.doCleanup(scope)
		return nil
	end

	attachOwnedScopeCleanup(instance, scope, maidPackageRaw)

	return instance
end

function FusionUtils.CreateInstanceWrapper(classNameRaw: string, defaultNameRaw: string?, maidPackageRaw: any?)
	local className = resolveClassName(classNameRaw)
	local defaultName = resolveDefaultName(defaultNameRaw)
	local maidPackage = resolveMaidPackage(maidPackageRaw)
	local wrapper = {
		ClassName = className,
		DefaultName = defaultName,
	}

	function wrapper.Component(scope: any, configRaw: InstanceWrapperConfig?): Instance
		return FusionUtils.CreateWithScope(scope, className, defaultName, configRaw)
	end

	function wrapper.HydrateComponent(scope: any, instanceRaw: any, configRaw: InstanceWrapperConfig?): Instance?
		return FusionUtils.HydrateWithScope(scope, className, instanceRaw, configRaw)
	end

	function wrapper.Create(configRaw: InstanceWrapperConfig?): Instance
		return FusionUtils.Create(className, defaultName, configRaw, maidPackage)
	end

	function wrapper.Hydrate(instanceRaw: any, configRaw: InstanceWrapperConfig?): Instance?
		return FusionUtils.Hydrate(className, instanceRaw, configRaw, maidPackage)
	end

	wrapper.component = wrapper.Component
	wrapper.hydrateComponent = wrapper.HydrateComponent
	wrapper.create = wrapper.Create
	wrapper.hydrate = wrapper.Hydrate

	return wrapper
end

FusionUtils.createWithScope = FusionUtils.CreateWithScope
FusionUtils.hydrateWithScope = FusionUtils.HydrateWithScope
FusionUtils.create = FusionUtils.Create
FusionUtils.hydrate = FusionUtils.Hydrate
FusionUtils.createInstanceWrapper = FusionUtils.CreateInstanceWrapper

return FusionUtils
