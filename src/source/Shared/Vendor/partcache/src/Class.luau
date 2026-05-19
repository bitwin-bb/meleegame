--!strict

--[[
	PartCache V4.0 by Xan the Dragon // Eti the Spirit -- RBX 18406183
	Update V4.0 has added Luau Strong Type Enforcement.
	
	Creating parts is laggy, especially if they are supposed to be there for a split second and/or need to be made frequently.
	This module aims to resolve this lag by pre-creating the parts and CFraming them to a location far away and out of sight.
	When necessary, the user can get one of these parts and CFrame it to where they need, then return it to the cache when they are done with it.
	
	According to someone instrumental in Roblox's backend technology, zeuxcg (https://devforum.roblox.com/u/zeuxcg/summary)...
		>> CFrame is currently the only "fast" property in that you can change it every frame without really heavy code kicking in. Everything else is expensive.
		
		- https://devforum.roblox.com/t/event-that-fires-when-rendering-finishes/32954/19
	
	This alone should ensure the speed granted by this module.
		
		
	HOW TO USE THIS MODULE:
	
	Look at the bottom of my thread for an API! https://devforum.roblox.com/t/partcache-for-all-your-quick-part-creation-needs/246641
--]]

--// Modules
local table = require(script.Parent.Parent.Table)

--// Types
type ClassData = {
	Open: { BasePart },
	InUse: { BasePart },
	CurrentCacheParent: Instance,
	Template: BasePart,
	ExpansionSize: number,
}

--// Variables
local CF_REALLY_FAR_AWAY = CFrame.new(0, 10e8, 0) -- A CFrame that's really far away. Ideally. You are free to change this as needed.

local TEMPLATE_ARCHIVABLE_FALSE =
	"The template's Archivable property has been set to false, which prevents it from being cloned. It will temporarily be set to true."

--// Functions
local function MakeFromTemplate(template: BasePart, currentCacheParent: Instance): BasePart
	local part: BasePart = template:Clone()

	part.CFrame = CF_REALLY_FAR_AWAY
	part.Anchored = true
	part.Parent = currentCacheParent

	return part
end

--// Class Setup
local Class = {}
Class.__index = Class
Class.__type = "PartCache" -- For compatibility with TypeMarshaller
export type Class = typeof(setmetatable({} :: ClassData, Class))

function Class.new(template: BasePart, numPrecreatedParts: number?, currentCacheParent: Instance?): Class
	-- Warnings
	assert(numPrecreatedParts > 0, "PrecreatedParts can not be negative!")

	local self = setmetatable({}, Class) :: Class

	self.Open = {}
	self.InUse = {}
	self.CurrentCacheParent = currentCacheParent or workspace
	self.Template = self:GetTemplate(template)
	self.ExpansionSize = 10

	-- Add 5 (or specified create part amt) parts into cache
	for _ = 1, numPrecreatedParts or 5 do
		table.insert(self.Open, MakeFromTemplate(template, self.CurrentCacheParent))
	end

	-- Set template parent to nil
	self.Template.Parent = nil

	return self
end

function Class.GetTemplate(_, template: BasePart)
	if template.Archivable then
		return template:Clone()
	end

	-- Warn
	if not template.Archivable then
		warn(TEMPLATE_ARCHIVABLE_FALSE)
	end

	-- Set to true, clone, then set to prev value
	template.Archivable = true
	local clone = template:Clone()
	template.Archivable = false

	-- Return clone
	return clone
end

--[[
	Gets a part from the cache, or creates one if no more are available.
]]
function Class.GetPart(self: Class): BasePart
	-- No parts, so create parts
	if #self.Open == 0 then
		warn(
			"No parts available in the cache! Creating ["
				.. self.ExpansionSize
				.. "] new part instance(s) - this amount can be edited by changing the ExpansionSize property of the PartCache instance... (This cache now contains a grand total of "
				.. tostring(#self.Open + #self.InUse + self.ExpansionSize)
				.. " parts.)"
		)

		for _ = 1, self.ExpansionSize do
			table.insert(self.Open, MakeFromTemplate(self.Template, self.CurrentCacheParent))
		end
	end

	-- Move final part to in use
	local part = self.Open[#self.Open]
	table.remove(self.Open)
	table.insert(self.InUse, part)

	return part
end

--[[
	Returns a part to the cache.
]]
function Class.ReturnPart(self: Class, part: BasePart)
	local index = table.indexOf(self.InUse, part)
	if not index then
		error(
			'Attempted to return part "'
				.. part.Name
				.. '" ('
				.. part:GetFullName()
				.. ") to the cache, but it's not in-use! Did you call this on the wrong part?"
		)
	end

	table.remove(self.InUse, index)
	table.insert(self.Open, part)

	part.CFrame = CF_REALLY_FAR_AWAY
	part.Anchored = true
end

--[[
	Sets the parent of all cached parts.
]]
function Class.SetCacheParent(self: Class, newParent: Instance)
	assert(
		newParent:IsDescendantOf(workspace) or newParent == workspace,
		"Cache parent is not a descendant of Workspace! Parts should be kept where they will remain in the visible world."
	)

	self.CurrentCacheParent = newParent

	for _, part in self.Open do
		part.Parent = newParent
	end
	for _, part in self.InUse do
		part.Parent = newParent
	end
end

--[[
	Adds numParts more parts to the cache.
]]
function Class.Expand(self: Class, numParts: number?)
	for _ = 1, numParts or self.ExpansionSize do
		table.insert(self.Open, MakeFromTemplate(self.Template, self.CurrentCacheParent))
	end
end

--[[
	Destroys this cache entirely. Use this when you don't need this cache object anymore.
]]
function Class.Dispose(self: Class)
	-- Destroy parts
	for _, part in self.Open do
		part:Destroy()
	end
	for _, part in self.InUse do
		part:Destroy()
	end
	self.Template:Destroy()

	-- Empty arrays
	self.Open = {}
	self.InUse = {}
end

return Class
