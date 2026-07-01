local require = require(script.Parent.loader).load(script)

local Cache = {}
Cache.__index = Cache

type DroppedToolEntry = {
	itemId: string,
	ownerUserId: number?,
	tools: { Tool },
	createdAt: number,
}

local function CoerceString(raw: any): string?
	if typeof(raw) ~= "string" then
		return nil
	end
	local trimmed = string.match(raw, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return nil
	end
	return trimmed
end

local function CoerceUserId(raw: any): number?
	if typeof(raw) ~= "number" or raw ~= raw then
		return nil
	end
	local userId = math.floor(raw)
	if userId <= 0 then
		return nil
	end
	return userId
end

local function GetToolArray(toolsRaw: any): { Tool }
	local output = {}
	if typeof(toolsRaw) ~= "table" then
		return output
	end

	for _, value in toolsRaw do
		if typeof(value) == "Instance" and value:IsA("Tool") then
			local tool = value :: Tool
			tool.Parent = nil
			table.insert(output, tool)
		end
	end
	return output
end

function Cache.New(): Cache
	local self = setmetatable({
		droppedToolsByLootId = {} :: { [string]: DroppedToolEntry },
		toolTemplateByItemId = {} :: { [string]: Tool | boolean },
	}, Cache)

	return self
end

function Cache.RememberToolTemplate(self: Cache, itemIdRaw: any, templateRaw: any): boolean
	local itemId = CoerceString(itemIdRaw)
	if itemId == nil then
		return false
	end
	if typeof(templateRaw) ~= "Instance" or not templateRaw:IsA("Tool") then
		return false
	end

	self.toolTemplateByItemId[itemId] = templateRaw :: Tool
	return true
end

function Cache.CloneToolTemplate(self: Cache, itemIdRaw: any): Tool?
	local itemId = CoerceString(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local cached = self.toolTemplateByItemId[itemId]
	if cached == nil or cached == false then
		return nil
	end

	local template = cached :: Tool
	if template.Parent == nil then
		self.toolTemplateByItemId[itemId] = nil
		return nil
	end

	local clone = template:Clone()
	if not clone:IsA("Tool") then
		clone:Destroy()
		return nil
	end
	clone.Parent = nil
	return clone
end

function Cache.DiscardDroppedTools(self: Cache, lootIdRaw: any)
	local lootId = CoerceString(lootIdRaw)
	if lootId == nil then
		return
	end

	local existing = self.droppedToolsByLootId[lootId]
	if existing == nil then
		return
	end

	for _, tool in existing.tools do
		tool:Destroy()
	end
	self.droppedToolsByLootId[lootId] = nil
end

function Cache.CacheDroppedTools(
	self: Cache,
	lootIdRaw: any,
	itemIdRaw: any,
	ownerUserIdRaw: any,
	toolsRaw: any
): number
	local lootId = CoerceString(lootIdRaw)
	local itemId = CoerceString(itemIdRaw)
	if lootId == nil or itemId == nil then
		return 0
	end

	local tools = GetToolArray(toolsRaw)
	if #tools <= 0 then
		return 0
	end

	self:DiscardDroppedTools(lootId)
	self.droppedToolsByLootId[lootId] = {
		itemId = itemId,
		ownerUserId = CoerceUserId(ownerUserIdRaw),
		tools = tools,
		createdAt = os.clock(),
	}
	return #tools
end

function Cache.PopDroppedTool(self: Cache, lootIdRaw: any, itemIdRaw: any): Tool?
	local lootId = CoerceString(lootIdRaw)
	local expectedItemId = CoerceString(itemIdRaw)
	if lootId == nil or expectedItemId == nil then
		return nil
	end

	local entry = self.droppedToolsByLootId[lootId]
	if entry == nil then
		return nil
	end
	if entry.itemId ~= expectedItemId then
		return nil
	end

	local lastIndex = #entry.tools
	if lastIndex <= 0 then
		self.droppedToolsByLootId[lootId] = nil
		return nil
	end

	local tool = entry.tools[lastIndex]
	entry.tools[lastIndex] = nil
	if #entry.tools <= 0 then
		self.droppedToolsByLootId[lootId] = nil
	end
	return tool
end

function Cache.Destroy(self: Cache)
	for lootId in self.droppedToolsByLootId do
		self:DiscardDroppedTools(lootId)
	end
	table.clear(self.toolTemplateByItemId)
end

export type Cache = typeof(setmetatable(
	{} :: {
		droppedToolsByLootId: { [string]: DroppedToolEntry },
		toolTemplateByItemId: { [string]: Tool | boolean },
	},
	Cache
))
return Cache
