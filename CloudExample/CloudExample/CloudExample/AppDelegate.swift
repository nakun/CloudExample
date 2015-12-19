import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?
	private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier? = UIBackgroundTaskInvalid

	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		application.registerUserNotificationSettings(UIUserNotificationSettings(forTypes: [.Badge, .Sound, .Alert], categories: nil))
		application.registerForRemoteNotifications()

		application.cancelAllLocalNotifications()
		if application.currentUserNotificationSettings()!.types.intersect(.Badge) != [] {
			application.applicationIconBadgeNumber = 0
		}

	//	application.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum)

		if application.applicationState == .Background {
			backgroundTaskStart(application)
		}
		return true
	}

	func applicationWillResignActive(application: UIApplication) {
	}

	func applicationDidEnterBackground(application: UIApplication) {
		backgroundTaskStart(application)
		dispatch_async(dispatch_get_main_queue()) {
			self.backgroundTaskEnd(application)
		}
	}

	func applicationWillEnterForeground(application: UIApplication) {
		backgroundTaskEnd(application)
		dispatch_async(dispatch_get_main_queue()) {
			let controller = (self.window!.rootViewController as! UINavigationController).topViewController as! ViewController
			controller.foreground()
		}
	}

	func applicationDidBecomeActive(application: UIApplication) {
	}

	func applicationWillTerminate(application: UIApplication) {
	}

	func application(application: UIApplication, didRegisterUserNotificationSettings notificationSettings: UIUserNotificationSettings) {
	}

	func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: NSData) {
	}

	func application(application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSError) {
	}

	func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject], fetchCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
		backgroundTaskStart(application)
		let controller = (self.window!.rootViewController as! UINavigationController).topViewController as! ViewController
		controller.receiveChangedRecords()
		completionHandler(.NewData)
	}

	func application(application: UIApplication, didReceiveLocalNotification notification: UILocalNotification) {
	}

/*	func application(application: UIApplication, performFetchWithCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
		completionHandler(.NewData)
	}*/

	private func backgroundTaskStart(application: UIApplication) {
		if application.applicationState != .Background || backgroundTaskIdentifier != UIBackgroundTaskInvalid || application.backgroundRefreshStatus != .Available {
			return
		}
		backgroundTaskIdentifier = application.beginBackgroundTaskWithExpirationHandler( {
			self.backgroundTaskEnd(application)
		})
	}

	private func backgroundTaskEnd(application: UIApplication) {
		dispatch_async(dispatch_get_main_queue(), {
			if self.backgroundTaskIdentifier != UIBackgroundTaskInvalid {
				application.endBackgroundTask(self.backgroundTaskIdentifier!)
				self.backgroundTaskIdentifier = UIBackgroundTaskInvalid
			}
		})
	}
}

