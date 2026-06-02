--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local AnimationPromiseUtils = Nevermore.Get("AnimationPromiseUtils")
local AnimationTrackUtils = Nevermore.Get("AnimationTrackUtils")
local Maid = Nevermore.Get("Maid")
local Table = Nevermore.Get("Table")

local AnimationHandler = {}
AnimationHandler.__index = AnimationHandler

export type AnimationHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		animator: (Animator | Humanoid)?,
		animations: { [string]: string },
		tracks: { [string]: AnimationTrack },
		finished: { [string]: boolean },
	},
	AnimationHandler
))

function AnimationHandler.new(animatorRaw: any?, animationsRaw: { [string]: string }?): AnimationHandler
	return setmetatable({
		maid = Maid.new(),
		animator = if typeof(animatorRaw) == "Instance"
				and (animatorRaw:IsA("Animator") or animatorRaw:IsA("Humanoid"))
			then animatorRaw
			else nil,
		animations = if typeof(animationsRaw) == "table" then Table.copy(animationsRaw) else {},
		tracks = {},
		finished = {},
	}, AnimationHandler)
end

function AnimationHandler.SetAnimator(self: AnimationHandler, animatorRaw: any?)
	self.animator = if typeof(animatorRaw) == "Instance"
			and (animatorRaw:IsA("Animator") or animatorRaw:IsA("Humanoid"))
		then animatorRaw
		else nil
end

function AnimationHandler.Load(self: AnimationHandler, nameRaw: any, animationIdRaw: any?): AnimationTrack?
	if typeof(nameRaw) ~= "string" or nameRaw == "" then
		return nil
	end
	local animationId = if typeof(animationIdRaw) == "string" and animationIdRaw ~= ""
		then animationIdRaw
		else self.animations[nameRaw]
	if self.animator == nil or typeof(animationId) ~= "string" or animationId == "" then
		return self.tracks[nameRaw]
	end

	local track = AnimationTrackUtils.loadAnimationFromId(self.animator, animationId)
	self.tracks[nameRaw] = track
	self.finished[nameRaw] = false
	self.maid[track] = track.Stopped:Connect(function()
		self.finished[nameRaw] = true
	end)
	return track
end

function AnimationHandler.Play(self: AnimationHandler, nameRaw: any, animationIdRaw: any?): AnimationTrack?
	if typeof(nameRaw) ~= "string" then
		return nil
	end
	local track = self.tracks[nameRaw] or self:Load(nameRaw, animationIdRaw)
	if track ~= nil then
		self.finished[nameRaw] = false
		track:Play()
	end
	return track
end

function AnimationHandler.Stop(self: AnimationHandler, nameRaw: any, fadeTimeRaw: any?)
	if typeof(nameRaw) ~= "string" then
		return
	end
	local track = self.tracks[nameRaw]
	if track ~= nil then
		track:Stop(if typeof(fadeTimeRaw) == "number" then fadeTimeRaw else 0)
	end
	self.finished[nameRaw] = true
end

function AnimationHandler.IsPlaying(self: AnimationHandler, nameRaw: any): boolean
	if typeof(nameRaw) ~= "string" then
		return false
	end
	local track = self.tracks[nameRaw]
	return track ~= nil and track.IsPlaying
end

function AnimationHandler.IsFinished(self: AnimationHandler, nameRaw: any): boolean
	return not self:IsPlaying(nameRaw) or self.finished[nameRaw] == true
end

function AnimationHandler.PromiseFinished(self: AnimationHandler, nameRaw: any, markerNameRaw: any?): any?
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

function AnimationHandler.Destroy(self: AnimationHandler)
	self.maid:DoCleaning()
	table.clear(self.animations)
	table.clear(self.tracks)
	table.clear(self.finished)
	self.animator = nil
end

AnimationHandler.setAnimator = AnimationHandler.SetAnimator
AnimationHandler.load = AnimationHandler.Load
AnimationHandler.play = AnimationHandler.Play
AnimationHandler.stop = AnimationHandler.Stop
AnimationHandler.isPlaying = AnimationHandler.IsPlaying
AnimationHandler.isFinished = AnimationHandler.IsFinished
AnimationHandler.promiseFinished = AnimationHandler.PromiseFinished
AnimationHandler.destroy = AnimationHandler.Destroy

return AnimationHandler
