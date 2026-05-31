--!strict

local Utils = require(script:FindFirstAncestor("StateMachine").Utils)

local PlayAnimationAction = {}

function PlayAnimationAction.Perform(machine: any, animationNameRaw: any?, optionsRaw: any?)
	local animation = Utils.Read(machine, "Animation", nil)
	local animationName = if typeof(animationNameRaw) == "string" and animationNameRaw ~= ""
		then animationNameRaw
		else nil
	Utils.CallFirst(animation, { "Play", "play" }, animationName, optionsRaw)
end

function PlayAnimationAction.new(animationNameRaw: any?, optionsRaw: any?): (any) -> ()
	return function(machine: any)
		PlayAnimationAction.Perform(machine, animationNameRaw, optionsRaw)
	end
end

return PlayAnimationAction
