
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Maid = Nevermore.Get("Maid")
local SoundPromiseUtils = Nevermore.Get("SoundPromiseUtils")

local SoundHandler = {}
SoundHandler.__index = SoundHandler

export type SoundHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		sounds: { [string]: Sound },
	},
	SoundHandler
))

function SoundHandler.new(): SoundHandler
	return setmetatable({
		maid = Maid.new(),
		sounds = {},
	}, SoundHandler)
end

function SoundHandler.Register(self: SoundHandler, nameRaw: any, soundRaw: any): boolean
	if typeof(nameRaw) ~= "string" or nameRaw == "" then
		return false
	end
	if typeof(soundRaw) ~= "Instance" or not soundRaw:IsA("Sound") then
		return false
	end
	self.sounds[nameRaw] = soundRaw
	return true
end

function SoundHandler.Play(self: SoundHandler, nameRaw: any): Sound?
	if typeof(nameRaw) ~= "string" then
		return nil
	end
	local sound = self.sounds[nameRaw]
	if sound ~= nil then
		sound:Play()
	end
	return sound
end

function SoundHandler.PromisePlayed(self: SoundHandler, nameRaw: any): any?
	local sound = self:Play(nameRaw)
	return if sound ~= nil then SoundPromiseUtils.promisePlayed(sound) else nil
end

function SoundHandler.Destroy(self: SoundHandler)
	self.maid:DoCleaning()
	table.clear(self.sounds)
end

SoundHandler.register = SoundHandler.Register
SoundHandler.play = SoundHandler.Play
SoundHandler.promisePlayed = SoundHandler.PromisePlayed
SoundHandler.destroy = SoundHandler.Destroy

return SoundHandler
