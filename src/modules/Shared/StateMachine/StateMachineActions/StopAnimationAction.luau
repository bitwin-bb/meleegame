
local require = require(script.Parent.loader).load(script)

local Utils = require("StateMachineUtils")

local StopAnimationAction = {}

function StopAnimationAction.Perform(machine: any, animationNameRaw: any?, fadeTimeRaw: any?)
	local animation = Utils.Read(machine, "Animation", nil)
	local animationName = if typeof(animationNameRaw) == "string" and animationNameRaw ~= ""
		then animationNameRaw
		else nil
	Utils.CallFirst(animation, { "Stop", "stop" }, animationName, fadeTimeRaw)
end

function StopAnimationAction.new(animationNameRaw: any?, fadeTimeRaw: any?): (any) -> ()
	return function(machine: any)
		StopAnimationAction.Perform(machine, animationNameRaw, fadeTimeRaw)
	end
end

return StopAnimationAction
