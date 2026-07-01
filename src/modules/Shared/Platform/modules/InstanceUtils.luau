
local require = require(script.Parent.loader).load(script)

local StringUtils = require("StringUtils")

local InstanceUtils = {}

function InstanceUtils.GetChildPath(root: Instance?, pathSegments: { string }): Instance?
	local cursor = root
	for _, segment in pathSegments do
		if cursor == nil then
			return nil
		end
		cursor = cursor:FindFirstChild(segment)
	end
	return cursor
end

function InstanceUtils.GetBasePartByPath(root: Instance?, pathSegments: { string }): BasePart?
	local Got = InstanceUtils.GetChildPath(root, pathSegments)
	if Got ~= nil and Got:IsA("BasePart") then
		return Got
	end
	return nil
end

function InstanceUtils.GetFirstBasePart(instanceRaw: Instance?): BasePart?
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

function InstanceUtils.GetModelRootPart(model: Model?, assignPrimaryPartRaw: boolean?): BasePart?
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

function InstanceUtils.GetInstanceRootPart(instanceRaw: Instance?, assignPrimaryPartRaw: boolean?): BasePart?
	if instanceRaw == nil then
		return nil
	end
	if instanceRaw:IsA("BasePart") then
		return instanceRaw
	end
	if instanceRaw:IsA("Model") then
		return InstanceUtils.GetModelRootPart(instanceRaw, assignPrimaryPartRaw)
	end
	return InstanceUtils.GetFirstBasePart(instanceRaw)
end

function InstanceUtils.FindDescendantBasePartByToken(root: Instance?, tokenRaw: any): BasePart?
	if root == nil then
		return nil
	end

	local targetToken = StringUtils.CompactToken(tokenRaw)
	if targetToken == "" then
		return nil
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and StringUtils.CompactToken(descendant.Name) == targetToken then
			return descendant
		end
	end

	return nil
end

return InstanceUtils
