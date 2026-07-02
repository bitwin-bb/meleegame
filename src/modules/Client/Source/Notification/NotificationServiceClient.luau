
local require = require(script.Parent.loader).load(script)

local SnackbarNotifications = require("FeatureSnackbarNotifications")

local NotificationServiceClient = {}

export type NotificationOptions = {
	clearQueue: boolean?,
	hideCurrent: boolean?,
	doNotAnimate: boolean?,
	duration: number?,
}

function NotificationServiceClient.Init(_self: any)
	return nil
end

function NotificationServiceClient.NotifyText(_self: any, textRaw: any, optionsRaw: NotificationOptions?): any
	return SnackbarNotifications.ShowText(textRaw, optionsRaw)
end

function NotificationServiceClient.HideCurrent(_self: any, doNotAnimateRaw: any)
	return SnackbarNotifications.HideCurrent(doNotAnimateRaw == true)
end

function NotificationServiceClient.ClearQueue(_self: any, doNotAnimateRaw: any)
	return SnackbarNotifications.ClearQueue(doNotAnimateRaw == true)
end

function NotificationServiceClient.ShowBuildActionRejected(_self: any, actionTypeRaw: any, reasonRaw: any)
	return SnackbarNotifications.ShowBuildActionRejected(actionTypeRaw, reasonRaw)
end

function NotificationServiceClient.ShowCraftResult(_self: any, resultRaw: any, craftingServiceRaw: any)
	return SnackbarNotifications.ShowCraftResult(resultRaw, craftingServiceRaw)
end
return NotificationServiceClient
