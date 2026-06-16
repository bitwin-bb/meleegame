
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local HumanoidUtils = Nevermore.Get("HumanoidUtils")
local Table = Nevermore.Get("Table")

local CharacterAdapter = {}
CharacterAdapter.__index = CharacterAdapter

export type CharacterAdapter = typeof(setmetatable(
	{} :: {
		character: Model?,
	},
	CharacterAdapter
))

function CharacterAdapter.new(characterRaw: any?): CharacterAdapter
	return setmetatable({
		character = if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model") then characterRaw else nil,
	}, CharacterAdapter)
end

function CharacterAdapter.SetCharacter(self: CharacterAdapter, characterRaw: any?)
	self.character = if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model") then characterRaw else nil
end

function CharacterAdapter.GetCharacter(self: CharacterAdapter): Model?
	return self.character
end

function CharacterAdapter.GetHumanoid(self: CharacterAdapter): Humanoid?
	local character = self.character
	if character == nil then
		return nil
	end
	return HumanoidUtils.getHumanoid(character)
end

function CharacterAdapter.GetRoot(self: CharacterAdapter): BasePart?
	local character = self.character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

function CharacterAdapter.IsAlive(self: CharacterAdapter): boolean
	local humanoid = self:GetHumanoid()
	return humanoid == nil or humanoid.Health > 0
end

function CharacterAdapter.Destroy(self: CharacterAdapter)
	self.character = nil
end

CharacterAdapter.setCharacter = CharacterAdapter.SetCharacter
CharacterAdapter.getCharacter = CharacterAdapter.GetCharacter
CharacterAdapter.getHumanoid = CharacterAdapter.GetHumanoid
CharacterAdapter.getRoot = CharacterAdapter.GetRoot
CharacterAdapter.isAlive = CharacterAdapter.IsAlive
CharacterAdapter.destroy = CharacterAdapter.Destroy
CharacterAdapter.copy = Table.copy

return CharacterAdapter
