--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local SnackbarNotifications = require(gameRoot.Client.Features.notification.SnackbarNotifications)

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
	return SnackbarNotifications.showText(textRaw, optionsRaw)
end

function NotificationServiceClient.HideCurrent(_self: any, doNotAnimateRaw: any)
	return SnackbarNotifications.hideCurrent(doNotAnimateRaw == true)
end

function NotificationServiceClient.ClearQueue(_self: any, doNotAnimateRaw: any)
	return SnackbarNotifications.clearQueue(doNotAnimateRaw == true)
end

function NotificationServiceClient.ShowBuildActionRejected(_self: any, actionTypeRaw: any, reasonRaw: any)
	return SnackbarNotifications.showBuildActionRejected(actionTypeRaw, reasonRaw)
end

function NotificationServiceClient.ShowCraftResult(_self: any, resultRaw: any, craftingServiceRaw: any)
	return SnackbarNotifications.showCraftResult(resultRaw, craftingServiceRaw)
end

NotificationServiceClient.init = NotificationServiceClient.Init
NotificationServiceClient.notifyText = NotificationServiceClient.NotifyText
NotificationServiceClient.showText = NotificationServiceClient.NotifyText
NotificationServiceClient.hideCurrent = NotificationServiceClient.HideCurrent
NotificationServiceClient.clearQueue = NotificationServiceClient.ClearQueue
NotificationServiceClient.showBuildActionRejected = NotificationServiceClient.ShowBuildActionRejected
NotificationServiceClient.showCraftResult = NotificationServiceClient.ShowCraftResult

return NotificationServiceClient
