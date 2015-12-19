import UIKit
import CloudKit

class ViewController: UITableViewController, UITextFieldDelegate {
	struct Item {
		var uuid: String
		var date: NSDate
		var text:String
	}
	private var items = [Item]()
	private let container = CKContainer.defaultContainer()
	private let database = CKContainer.defaultContainer().publicCloudDatabase	// or privateCloudDatabase
	private let defaults = NSUserDefaults.standardUserDefaults()

	override func viewDidLoad() {
		super.viewDidLoad()

		self.setupSubscriptions() {
			self.fetchAll()
		}
		foreground()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
	}

	func foreground() {
		let operation = CKModifyBadgeOperation(badgeValue: 0)
		operation.modifyBadgeCompletionBlock = { (error) -> Void in
			if error != nil {
				print("#\(__LINE__) error resetting badge: \(error)")
			}
			else {
				UIApplication.sharedApplication().applicationIconBadgeNumber = 0
			}
		}
		CKContainer.defaultContainer().addOperation(operation)
	}

	private func setupSubscriptions(completion: Void -> Void) {
		let operation = CKFetchSubscriptionsOperation.fetchAllSubscriptionsOperation()
		operation.fetchSubscriptionCompletionBlock = { subscriptions, error in
			if error != nil {
				print("#\(__LINE__) error : \(error)")
			}
			var saveSubscriptions = [CKSubscription]()
			var deleteSubscriptionIDs = [String]()
			var foundItemDelete = false
			var foundItemUpdate = false
			for subscription in Array(subscriptions!.values) {
				if		subscription.subscriptionType == .Query && subscription.recordType == "Item" && subscription.subscriptionOptions == [.FiresOnRecordCreation, .FiresOnRecordUpdate] {
					foundItemUpdate = true
				}
				else if subscription.subscriptionType == .Query && subscription.recordType == "Item" && subscription.subscriptionOptions == .FiresOnRecordDeletion {
					foundItemDelete = true
				}
				else {
					deleteSubscriptionIDs.append(subscription.subscriptionID)
				}
			}
			if !foundItemUpdate {
				let subscription = CKSubscription(recordType: "Item", predicate: NSPredicate(value: true), options: [.FiresOnRecordCreation, .FiresOnRecordUpdate])
				subscription.notificationInfo = CKNotificationInfo()
				subscription.notificationInfo!.alertBody = "updated"
			//	subscription.notificationInfo!.alertLocalizationKey = "Update"		// Localizable.strings ex. "\"%1$@\" has been updated."
			//	subscription.notificationInfo!.alertLocalizationArgs = ["text"]
				subscription.notificationInfo!.soundName = "default"
				subscription.notificationInfo!.shouldBadge = true
				subscription.notificationInfo!.shouldSendContentAvailable = true
				saveSubscriptions.append(subscription)
			}
			if !foundItemDelete {
				let subscription = CKSubscription(recordType: "Item", predicate: NSPredicate(value: true), options: .FiresOnRecordDeletion)
				subscription.notificationInfo = CKNotificationInfo()
				subscription.notificationInfo!.alertBody = "deleted"
			//	subscription.notificationInfo!.alertLocalizationKey = "Delete"		// Localizable.strings ex. "\"%1$@\" has been deleted."
			//	subscription.notificationInfo!.alertLocalizationArgs = ["text"]
				subscription.notificationInfo!.soundName = "default"
				subscription.notificationInfo!.shouldSendContentAvailable = true
				saveSubscriptions.append(subscription)
			}
			if saveSubscriptions.count != 0 || deleteSubscriptionIDs.count != 0 {
				let operation = CKModifySubscriptionsOperation(subscriptionsToSave: saveSubscriptions, subscriptionIDsToDelete: deleteSubscriptionIDs)
				operation.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedSubscriptionIDs, error in
					if error != nil {
						print("#\(__LINE__) error : \(error)")
					}
					completion()
				}
				self.database.addOperation(operation)
			}
			else {
				completion()
			}
		}
		database.addOperation(operation)
	}

	func fetchAll(cursor: CKQueryCursor? = nil) {
		var operation: CKQueryOperation
		if cursor == nil {
			operation = CKQueryOperation(query: CKQuery(recordType: "Item", predicate: NSPredicate(value: true)))
		}
		else {
			operation = CKQueryOperation(cursor: cursor!)
		}
		operation.recordFetchedBlock = { record in
			self.items.append(Item(uuid: record.recordID.recordName, date: record.objectForKey("date") as! NSDate, text: record.objectForKey("text") as! String))
		}
		operation.queryCompletionBlock = { cursor, error in
			if cursor != nil {
				self.fetchAll(cursor)
			}
			else if self.items.count != 0 {
				self.items.sortInPlace() { $0.date.compare($1.date) == .OrderedAscending }
				var indexPaths = [NSIndexPath]()
				for (i, _) in self.items.enumerate() {
					indexPaths.append(NSIndexPath(forRow: i, inSection: 0))
				}
				dispatch_async(dispatch_get_main_queue()) {
					self.tableView.beginUpdates()
						self.tableView.insertRowsAtIndexPaths(indexPaths, withRowAnimation: .Fade)
					self.tableView.endUpdates()
				}
			}
		}
		database.addOperation(operation)
	}

	func receiveRemoteNotification(userInfo: [String : NSObject]) {
		let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
		if notification.notificationType == .Query {
			if let query = notification as? CKQueryNotification {
				switch query.queryNotificationReason {
				case .RecordCreated, .RecordUpdated:
					database.fetchRecordWithID(query.recordID!) { newRecord, error in
						if error != nil {
							print("#\(__LINE__) error : \(error)")
							return
						}
						switch newRecord!.recordType {
						case "Item":
							var found = false
							for (i, item) in self.items.enumerate() {
								if newRecord!.recordID.recordName == item.uuid {
									found = true
									if (newRecord!.objectForKey("text") as! String) != item.text {
										print("#\(__LINE__) update \(item.text) -> \(newRecord!.objectForKey("text") as! String)")
										self.items[i] = Item(uuid: newRecord!.recordID.recordName, date: newRecord!.objectForKey("date") as! NSDate, text: newRecord!.objectForKey("text") as! String)
										dispatch_async(dispatch_get_main_queue()) {
											self.tableView.reloadRowsAtIndexPaths([NSIndexPath(forRow: i, inSection: 0)], withRowAnimation: .Fade)
										}
									}
									break
								}
							}
							if !found {
								let item = Item(uuid: newRecord!.recordID.recordName, date: newRecord!.objectForKey("date") as! NSDate, text: newRecord!.objectForKey("text") as! String)
								self.items.append(item)
								self.items.sortInPlace() { $0.date.compare($1.date) == .OrderedAscending }
								print("#\(__LINE__) append \(newRecord!.objectForKey("text") as! String)")
								dispatch_async(dispatch_get_main_queue()) {
									self.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: self.items.indexOf({$0.uuid == item.uuid})!, inSection: 0)], withRowAnimation: .Fade)
								}
							}

						default:
							break
						}
					}

				case .RecordDeleted:
					for (i, item) in self.items.enumerate() {
						if query.recordID!.recordName == item.uuid {
							self.items.removeAtIndex(i)
							print("#\(__LINE__) delete \(item.text)")
							dispatch_async(dispatch_get_main_queue()) {
								self.tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: i, inSection: 0)], withRowAnimation: .Fade)
							}
							break
						}
					}
					break
				}
			}
		}
	}

	// MARK: - UITextField Delegate

	func textFieldDidEndEditing(textField: UITextField) {
		var saveRecords = [CKRecord]()
		var deleteRecordIDs = [CKRecordID]()
		let indexPath = tableView.indexPathForCell(textField.superview!.superview! as! UITableViewCell)!
		if indexPath.row >= items.count {
			if textField.text != "" {
				let record = CKRecord(recordType: "Item", recordID: CKRecordID(recordName: NSUUID().UUIDString))
				record.setObject(NSDate(), forKey: "date")
				record.setObject(textField.text, forKey: "text")
				items.append(Item(uuid: record.recordID.recordName, date: record.objectForKey("date") as! NSDate, text: textField.text!))
				saveRecords.append(record)

				tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: indexPath.row + 1, inSection: indexPath.section)], withRowAnimation: .Fade)
			}
		}
		else if textField.text == "" {
			deleteRecordIDs.append(CKRecordID(recordName: items[indexPath.row].uuid))
			items.removeAtIndex(indexPath.row)

			tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
		}
		else {
			let item = items[indexPath.row]
			if item.text != textField.text {
				let operation = CKFetchRecordsOperation(recordIDs: [CKRecordID(recordName: item.uuid)])
				operation.perRecordCompletionBlock = { record, recordID, error in
					if error != nil {
						print("#\(__LINE__) error : \(error)")
					}
					else {
						record!.setObject(textField.text, forKey: "text")
						saveRecords.append(record!)
					}
				}
				operation.fetchRecordsCompletionBlock = { records, error in
					if error != nil {
						print("#\(__LINE__) error : \(error)")
					}
					if saveRecords.count != 0 || deleteRecordIDs.count != 0 {
						let operation = CKModifyRecordsOperation(recordsToSave: saveRecords, recordIDsToDelete: deleteRecordIDs)
						operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
							if error != nil {
								print("#\(__LINE__) error : \(error)")
							}
						}
						self.database.addOperation(operation)
					}
				}
				database.addOperation(operation)
			}
			return
		}
		if saveRecords.count != 0 || deleteRecordIDs.count != 0 {
			let operation = CKModifyRecordsOperation(recordsToSave: saveRecords, recordIDsToDelete: deleteRecordIDs)
			operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
				if error != nil {
					print("#\(__LINE__) error : \(error)")
				}
			}
			database.addOperation(operation)
		}
	}

	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return false
	}

	// MARK: - Table View Delegate

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return items.count + 1
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
		let field = cell.viewWithTag(1) as! UITextField
		field.delegate = self
		if indexPath.row < items.count {
			field.text = items[indexPath.row].text
		}
		else {
			field.text = ""
		}
		return cell
	}
}
