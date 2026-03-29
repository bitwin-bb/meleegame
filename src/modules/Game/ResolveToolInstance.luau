--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)

local ResolveToolInstance = {}

local ITEM_ID_ATTRIBUTE_NAMES = { "itemId", "ItemId", "ittemId", "id" }
local ITEM_TYPE_ATTRIBUTE_NAMES = { "itemType", "ItemType", "itemtype", "type", "Type" }
local PREFERRED_TOOL_BRANCH_NAMES = {
	tool = true,
}
local PREFERRED_MODEL_BRANCH_NAMES = {
	model = true,
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeString(valueRaw: any): string?
	local value = trim(valueRaw)
	if value == "" then
		return nil
	end
	return value
end

local function normalizeNameToken(valueRaw: any): string
	local value = sanitizeString(valueRaw)
	if value == nil then
		return ""
	end
	return string.lower(value)
end

local function isPreferredBranch(instance: Instance, lookup: { [string]: boolean }): boolean
	return lookup[normalizeNameToken(instance.Name)] == true
end

local function isVisualInstance(instance: Instance): boolean
	return instance:IsA("Model") or instance:IsA("BasePart") or instance:IsA("Accessory")
end

local function isDescendantOfInstance(instance: Instance, ancestor: Instance): boolean
	local parent = instance.Parent
	while parent ~= nil do
		if parent == ancestor then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function collectPreferredChildren(root: Instance, lookup: { [string]: boolean }): { Instance }
	local children = root:GetChildren()
	local ordered = {}

	for _, child in children do
		if isPreferredBranch(child, lookup) then
			table.insert(ordered, child)
		end
	end

	for _, child in children do
		if not isPreferredBranch(child, lookup) then
			table.insert(ordered, child)
		end
	end

	return ordered
end

local function collectMatchingChildren(root: Instance, lookup: { [string]: boolean }): { Instance }
	local matched = {}
	for _, child in root:GetChildren() do
		if isPreferredBranch(child, lookup) then
			table.insert(matched, child)
		end
	end
	return matched
end

local function collectExcludedToolRoots(root: Instance): { Instance }
	local excluded = {}
	for _, child in root:GetChildren() do
		if child:IsA("Tool") or isPreferredBranch(child, PREFERRED_TOOL_BRANCH_NAMES) then
			table.insert(excluded, child)
		end
	end
	return excluded
end

local function isInsideExcludedRoot(instance: Instance, excludedRoots: { Instance }): boolean
	for _, excludedRoot in excludedRoots do
		if instance == excludedRoot or isDescendantOfInstance(instance, excludedRoot) then
			return true
		end
	end
	return false
end

local function isInsidePreferredToolBranch(instance: Instance): boolean
	local parent = instance.Parent
	while parent ~= nil do
		if parent:IsA("Tool") or isPreferredBranch(parent, PREFERRED_TOOL_BRANCH_NAMES) then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function collectToolAttributeSources(tool: Tool): { Instance }
	local sources = { tool :: Instance }

	for _, child in tool:GetChildren() do
		table.insert(sources, child)
	end

	for _, descendant in tool:GetDescendants() do
		if descendant.Parent ~= tool then
			table.insert(sources, descendant)
		end
	end

	return sources
end

local function resolveAttributeText(instances: { Instance }, attributeNames: { string }): string?
	for _, instance in instances do
		for _, attributeName in attributeNames do
			local attributeValue = sanitizeString(instance:GetAttribute(attributeName))
			if attributeValue ~= nil then
				return attributeValue
			end
		end
	end
	return nil
end

function ResolveToolInstance.resolveTool(instanceRaw: any): Tool?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	if instance:IsA("Tool") then
		return instance
	end
	local ancestorTool = instance:FindFirstAncestorWhichIsA("Tool")
	if ancestorTool ~= nil then
		return ancestorTool
	end

	for _, child in collectPreferredChildren(instance, PREFERRED_TOOL_BRANCH_NAMES) do
		if child:IsA("Tool") then
			return child
		end

		local descendant = child:FindFirstChildWhichIsA("Tool", true)
		if descendant ~= nil then
			return descendant
		end
	end

	return nil
end

local function resolveVisualFromContainer(container: Instance, excludedToolRoots: { Instance }): Instance?
	if
		container:IsA("Tool")
		or isPreferredBranch(container, PREFERRED_TOOL_BRANCH_NAMES)
		or isInsideExcludedRoot(container, excludedToolRoots)
	then
		return nil
	end

	if isVisualInstance(container) then
		return container
	end

	for _, child in container:GetChildren() do
		if
			child:IsA("Tool")
			or isPreferredBranch(child, PREFERRED_TOOL_BRANCH_NAMES)
			or isInsideExcludedRoot(child, excludedToolRoots)
		then
			continue
		end
		if isVisualInstance(child) then
			return child
		end
	end

	for _, descendant in container:GetDescendants() do
		if
			descendant:IsA("Tool")
			or isInsideExcludedRoot(descendant, excludedToolRoots)
			or isInsidePreferredToolBranch(descendant)
		then
			continue
		end
		if isVisualInstance(descendant) then
			return descendant
		end
	end

	return nil
end

function ResolveToolInstance.resolveVisualTemplate(instanceRaw: any): Instance?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	if instance:IsA("Tool") then
		return nil
	end

	local excludedToolRoots = collectExcludedToolRoots(instance)
	for _, child in collectMatchingChildren(instance, PREFERRED_MODEL_BRANCH_NAMES) do
		local visual = resolveVisualFromContainer(child, {})
		if visual ~= nil then
			return visual
		end
	end

	local directVisual = resolveVisualFromContainer(instance, excludedToolRoots)
	if directVisual ~= nil then
		return directVisual
	end

	for _, child in collectPreferredChildren(instance, PREFERRED_MODEL_BRANCH_NAMES) do
		if isInsideExcludedRoot(child, excludedToolRoots) then
			continue
		end
		local visual = resolveVisualFromContainer(child, excludedToolRoots)
		if visual ~= nil then
			return visual
		end
	end

	return nil
end

function ResolveToolInstance.resolveToolItemId(toolRaw: any): string?
	local tool = ResolveToolInstance.resolveTool(toolRaw)
	if tool == nil then
		return nil
	end

	local attributeSources = collectToolAttributeSources(tool)
	local directItemId = resolveAttributeText(attributeSources, ITEM_ID_ATTRIBUTE_NAMES)
	if directItemId ~= nil then
		local canonicalItemId = ItemRegistry.resolveCanonicalItemId(directItemId)
		if canonicalItemId ~= nil then
			return canonicalItemId
		end
	end

	local fromName = sanitizeString(tool.Name)
	if fromName ~= nil then
		return ItemRegistry.resolveCanonicalItemId(fromName)
	end

	return nil
end

function ResolveToolInstance.resolveToolItemType(toolRaw: any): string?
	local tool = ResolveToolInstance.resolveTool(toolRaw)
	if tool == nil then
		return nil
	end

	local attributeSources = collectToolAttributeSources(tool)
	local directItemType = resolveAttributeText(attributeSources, ITEM_TYPE_ATTRIBUTE_NAMES)
	if directItemType ~= nil then
		return directItemType
	end

	local itemId = ResolveToolInstance.resolveToolItemId(tool)
	if itemId == nil then
		return nil
	end

	local definition = ItemRegistry.resolveDefinition(itemId)
	if typeof(definition) ~= "table" then
		return nil
	end

	local definitionTable = definition :: { [string]: any }
	return sanitizeString(definitionTable.itemType) or sanitizeString(definitionTable.type)
end

return ResolveToolInstance
