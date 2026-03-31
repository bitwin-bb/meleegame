--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StringUtils = require(ReplicatedStorage.Shared.Modules.Core.StringUtils)

local InstanceUtils = {}

function InstanceUtils.resolveChildPath(root: Instance?, pathSegments: { string }): Instance?
	local cursor = root
	for _, segment in pathSegments do
		if cursor == nil then
			return nil
		end
		cursor = cursor:FindFirstChild(segment)
	end
	return cursor
end

function InstanceUtils.resolveBasePartByPath(root: Instance?, pathSegments: { string }): BasePart?
	local resolved = InstanceUtils.resolveChildPath(root, pathSegments)
	if resolved ~= nil and resolved:IsA("BasePart") then
		return resolved
	end
	return nil
end

function InstanceUtils.resolveFirstBasePart(instanceRaw: Instance?): BasePart?
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

function InstanceUtils.resolveModelRootPart(model: Model?, assignPrimaryPartRaw: boolean?): BasePart?
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

function InstanceUtils.resolveInstanceRootPart(instanceRaw: Instance?, assignPrimaryPartRaw: boolean?): BasePart?
	if instanceRaw == nil then
		return nil
	end
	if instanceRaw:IsA("BasePart") then
		return instanceRaw
	end
	if instanceRaw:IsA("Model") then
		return InstanceUtils.resolveModelRootPart(instanceRaw, assignPrimaryPartRaw)
	end
	return InstanceUtils.resolveFirstBasePart(instanceRaw)
end

function InstanceUtils.findDescendantBasePartByToken(root: Instance?, tokenRaw: any): BasePart?
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

return InstanceUtils
