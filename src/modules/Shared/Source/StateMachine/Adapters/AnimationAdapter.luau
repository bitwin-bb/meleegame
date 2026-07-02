
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local AnimationPromiseUtils = Nevermore.Get("AnimationPromiseUtils")
local AnimationTrackUtils = Nevermore.Get("AnimationTrackUtils")
local Maid = Nevermore.Get("Maid")
local Table = Nevermore.Get("Table")

local AnimationAdapter = {}
AnimationAdapter.__index = AnimationAdapter

export type AnimationAdapter = typeof(setmetatable(
	{} :: {
		handler: any?,
		animator: (Animator | Humanoid)?,
		animations: { [string]: string },
		tracks: { [string]: AnimationTrack },
		finished: { [string]: boolean },
		maid: any,
	},
	AnimationAdapter
))

function AnimationAdapter.new(handlerRaw: any?, configRaw: any?): AnimationAdapter
	local config = if typeof(configRaw) == "table" then configRaw else {}
	return setmetatable({
		handler = handlerRaw,
		animator = if typeof(config.Animator) == "Instance"
				and (config.Animator:IsA("Animator") or config.Animator:IsA("Humanoid"))
			then config.Animator
			else nil,
		animations = if typeof(config.Animations) == "table" then Table.copy(config.Animations) else {},
		tracks = {},
		finished = {},
		maid = Maid.new(),
	}, AnimationAdapter)
end

function AnimationAdapter.Load(self: AnimationAdapter, nameRaw: any, animationIdRaw: any?): AnimationTrack?
	if typeof(nameRaw) ~= "string" or nameRaw == "" then
		return nil
	end
	local animator = self.animator
	local animationId = if typeof(animationIdRaw) == "string" and animationIdRaw ~= ""
		then animationIdRaw
		else self.animations[nameRaw]
	if animator == nil or typeof(animationId) ~= "string" or animationId == "" then
		return self.tracks[nameRaw]
	end

	local track = AnimationTrackUtils.loadAnimationFromId(animator, animationId)
	self.tracks[nameRaw] = track
	self.finished[nameRaw] = false
	self.maid[track] = track.Stopped:Connect(function()
		self.finished[nameRaw] = true
	end)
	return track
end

function AnimationAdapter.Play(self: AnimationAdapter, nameRaw: any, optionsRaw: any?): any?
	if self.handler ~= nil then
		local play = self.handler.Play or self.handler.play
		if typeof(play) == "function" then
			return play(self.handler, nameRaw, optionsRaw)
		end
	end

	if typeof(nameRaw) ~= "string" then
		return nil
	end
	self.finished[nameRaw] = false
	local track = self.tracks[nameRaw] or self:Load(nameRaw)
	if track ~= nil then
		track:Play()
	end
	return track
end

function AnimationAdapter.Stop(self: AnimationAdapter, nameRaw: any, fadeTimeRaw: any?)
	if self.handler ~= nil then
		local stop = self.handler.Stop or self.handler.stop
		if typeof(stop) == "function" then
			stop(self.handler, nameRaw, fadeTimeRaw)
			return
		end
	end

	if typeof(nameRaw) == "string" then
		local track = self.tracks[nameRaw]
		if track ~= nil then
			track:Stop(if typeof(fadeTimeRaw) == "number" then fadeTimeRaw else 0)
		end
		self.finished[nameRaw] = true
	end
end

function AnimationAdapter.IsPlaying(self: AnimationAdapter, nameRaw: any): boolean
	if self.handler ~= nil then
		local isPlaying = self.handler.IsPlaying or self.handler.isPlaying
		if typeof(isPlaying) == "function" then
			return isPlaying(self.handler, nameRaw) == true
		end
	end
	if typeof(nameRaw) ~= "string" then
		return false
	end
	return self.finished[nameRaw] ~= true
end

function AnimationAdapter.IsFinished(self: AnimationAdapter, nameRaw: any): boolean
	if self.handler ~= nil then
		local isFinished = self.handler.IsFinished or self.handler.isFinished
		if typeof(isFinished) == "function" then
			return isFinished(self.handler, nameRaw) == true
		end
	end
	return not self:IsPlaying(nameRaw)
end

function AnimationAdapter.PromiseFinished(self: AnimationAdapter, nameRaw: any, markerNameRaw: any?): any?
	if typeof(nameRaw) ~= "string" then
		return nil
	end
	local track = self.tracks[nameRaw]
	if track == nil then
		return nil
	end
	local markerName = if typeof(markerNameRaw) == "string" and markerNameRaw ~= "" then markerNameRaw else nil
	return AnimationPromiseUtils.promiseFinished(track, markerName)
end

function AnimationAdapter.Destroy(self: AnimationAdapter)
	self.maid:DoCleaning()
	table.clear(self.tracks)
	table.clear(self.finished)
	table.clear(self.animations)
	self.animator = nil
	self.handler = nil
end
AnimationAdapter.copy = Table.copy

return AnimationAdapter
