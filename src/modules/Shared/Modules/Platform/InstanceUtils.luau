--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StringUtils = require(script:FindFirstAncestor("game").Shared.Modules.Core.StringUtils)

local InstanceUtils = {}

function InstanceUtils.ResolveChildPath(root: Instance?, pathSegments: { string }): Instance?
	local cursor = root
	for _, segment in pathSegments do
		if cursor == nil then
			return nil
		end
		cursor = cursor:FindFirstChild(segment)
	end
	return cursor
end

function InstanceUtils.ResolveBasePartByPath(root: Instance?, pathSegments: { string }): BasePart?
	local resolved = InstanceUtils.ResolveChildPath(root, pathSegments)
	if resolved ~= nil and resolved:IsA("BasePart") then
		return resolved
	end
	return nil
end

function InstanceUtils.ResolveFirstBasePart(instanceRaw: Instance?): BasePart?
	if instanceRaw == nil then
		return nil
	end
	if instanceRaw:IsA("BasePart") then
		return instanceRaw
	end

	local asModel = if instanceRaw:IsA("Model") then instanceRaw else nil
	if asModel ~= nil and asModel.PrimaryPart ~= nil then
		return asModel.PrimaryPart
	end

	for _, descendant in instanceRaw:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

function InstanceUtils.ResolveModelRootPart(model: Model?, assignPrimaryPartRaw: boolean?): BasePart?
	if model == nil then
		return nil
	end

	local assignPrimaryPart = assignPrimaryPartRaw == true
	local humanoidRoot = model:FindFirstChild("HumanoidRootPart")
	if humanoidRoot ~= nil and humanoidRoot:IsA("BasePart") then
		if assignPrimaryPart and model.PrimaryPart == nil then
			model.PrimaryPart = humanoidRoot
		end
		return humanoidRoot
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if assignPrimaryPart and model.PrimaryPart == nil then
				model.PrimaryPart = descendant
			end
			return descendant
		end
	end

	return nil
end

function InstanceUtils.ResolveInstanceRootPart(instanceRaw: Instance?, assignPrimaryPartRaw: boolean?): BasePart?
	if instanceRaw == nil then
		return nil
	end
	if instanceRaw:IsA("BasePart") then
		return instanceRaw
	end
	if instanceRaw:IsA("Model") then
		return InstanceUtils.ResolveModelRootPart(instanceRaw, assignPrimaryPartRaw)
	end
	return InstanceUtils.ResolveFirstBasePart(instanceRaw)
end

function InstanceUtils.FindDescendantBasePartByToken(root: Instance?, tokenRaw: any): BasePart?
	if root == nil then
		return nil
	end

	local targetToken = StringUtils.compactToken(tokenRaw)
	if targetToken == "" then
		return nil
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and StringUtils.compactToken(descendant.Name) == targetToken then
			return descendant
		end
	end

	return nil
end

InstanceUtils.resolveChildPath = InstanceUtils.ResolveChildPath
InstanceUtils.resolveBasePartByPath = InstanceUtils.ResolveBasePartByPath
InstanceUtils.resolveFirstBasePart = InstanceUtils.ResolveFirstBasePart
InstanceUtils.resolveModelRootPart = InstanceUtils.ResolveModelRootPart
InstanceUtils.resolveInstanceRootPart = InstanceUtils.ResolveInstanceRootPart
InstanceUtils.findDescendantBasePartByToken = InstanceUtils.FindDescendantBasePartByToken

return InstanceUtils
