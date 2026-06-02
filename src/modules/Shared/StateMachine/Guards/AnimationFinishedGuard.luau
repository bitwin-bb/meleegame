--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Utils = require(gameRoot.Shared.StateMachine.Utils)

local AnimationFinishedGuard = {}

function AnimationFinishedGuard.Evaluate(machine: any, animationNameRaw: any?): boolean
	local animation = Utils.Read(machine, "Animation", nil)
	local animationName = if typeof(animationNameRaw) == "string" and animationNameRaw ~= ""
		then animationNameRaw
		else nil
	local finished = Utils.CallFirst(animation, { "IsFinished", "isFinished" }, animationName)
	if typeof(finished) == "boolean" then
		return finished
	end

	local playing = Utils.CallFirst(animation, { "IsPlaying", "isPlaying" }, animationName)
	if typeof(playing) == "boolean" then
		return not playing
	end
	return true
end

function AnimationFinishedGuard.new(animationNameRaw: any?): (any) -> boolean
	return function(machine: any): boolean
		return AnimationFinishedGuard.Evaluate(machine, animationNameRaw)
	end
end

return AnimationFinishedGuard
