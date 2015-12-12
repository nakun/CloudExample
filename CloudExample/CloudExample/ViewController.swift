import UIKit
import CloudKit

extension CKRecord {
	var text: String	{	get {	return objectForKey("text") as! String	}	set {	setObject(newValue, forKey: "text")		}	}
	var date: NSDate	{	get {	return objectForKey("date") as! NSDate	}	set {	setObject(newValue, forKey: "date")		}	}
}

class ViewController: UITableViewController, UITextFieldDelegate {
	private var zoneID: CKRecordZoneID!
	private var records = [CKRecord]()
	private var previousClientChangeTokenData: NSData?
	private var launching = true
	private var fetching = false
	private var request = false
	private let container = CKContainer.defaultContainer()
	private let database = CKContainer.defaultContainer().privateCloudDatabase
	private let defaults = NSUserDefaults.standardUserDefaults()

	override func viewDidLoad() {
		super.viewDidLoad()

		if let encodedObjectData = defaults.objectForKey("serverChangeToken") as? NSData {
			previousServerChangeToken = NSKeyedUnarchiver.unarchiveObjectWithData(encodedObjectData) as? CKServerChangeToken
		}

		setupRecordZones() {
			self.setupSubscriptions() {
				self.fetchAll()
			}
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
	}
	
	private var previousServerChangeToken: CKServerChangeToken? {
		didSet {
			defaults.setObject(previousServerChangeToken == nil ? nil: NSKeyedArchiver.archivedDataWithRootObject(previousServerChangeToken!), forKey: "serverChangeToken")
			if !defaults.synchronize() {
				print("#\(__LINE__) failed synchronize" )
				abort()
			}
		}
	}

	private func setupRecordZones(completion: Void -> Void) {
		let operation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
		operation.fetchRecordZonesCompletionBlock = { recordZoneIDsByZoneID, error in
			if error != nil {
				print("#\(__LINE__) error : \(error)")
			}
			var saveRecordZones = [CKRecordZone]()
			var deleteRecordZoneIDs = [CKRecordZoneID]()
			var foundItem = false
			for recordZone in Array(recordZoneIDsByZoneID!.values) {
				if recordZone.zoneID == CKRecordZone.defaultRecordZone().zoneID {
				}
				else if recordZone.zoneID.zoneName == "Item" {
					self.zoneID = recordZone.zoneID
					foundItem = true
				}
				else {
					deleteRecordZoneIDs.append(recordZone.zoneID)
				}
			}
			if !foundItem {
				let recordZone = CKRecordZone(zoneName: "Item")
				saveRecordZones.append(recordZone)
				self.zoneID = recordZone.zoneID
			}
			if saveRecordZones.count != 0 || deleteRecordZoneIDs.count != 0 {
				let operation = CKModifyRecordZonesOperation(recordZonesToSave: saveRecordZones, recordZoneIDsToDelete: deleteRecordZoneIDs)
				operation.modifyRecordZonesCompletionBlock = { savedRecordZones, deletedRecordZoneIDs, error in
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

	private func setupSubscriptions(completion: Void -> Void) {
		let operation = CKFetchSubscriptionsOperation.fetchAllSubscriptionsOperation()
		operation.fetchSubscriptionCompletionBlock = { subscriptions, error in
			if error != nil {
				print("#\(__LINE__) error : \(error)")
			}
			var saveSubscriptions = [CKSubscription]()
			var deleteSubscriptionIDs = [String]()
			var foundItem = false
			for subscription in Array(subscriptions!.values) {
				if subscription.subscriptionType == .RecordZone && subscription.zoneID == self.zoneID {
					foundItem = true
				}
				else {
					deleteSubscriptionIDs.append(subscription.subscriptionID)
				}
			}
			if !foundItem {
				let subscription = CKSubscription(zoneID: self.zoneID, options: CKSubscriptionOptions(rawValue: 0))
				subscription.notificationInfo = CKNotificationInfo()
				subscription.notificationInfo!.alertBody = ""
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
			self.records.append(record)
		}
		operation.queryCompletionBlock = { cursor, error in
			if cursor != nil {
				self.fetchAll(cursor)
			}
			else if self.records.count != 0 {
				self.records.sortInPlace() { $0.date.compare($1.date) == .OrderedAscending }
				var indexPaths = [NSIndexPath]()
				for var i = 0; i < self.records.count; i++ {
					indexPaths.append(NSIndexPath(forRow: i, inSection: 0))
				}
				dispatch_async(dispatch_get_main_queue()) {
					self.tableView.beginUpdates()
						self.tableView.insertRowsAtIndexPaths(indexPaths, withRowAnimation: .Fade)
					self.tableView.endUpdates()
				}
			}
			self.launching = false
		}
		database.addOperation(operation)
	}

	func receiveRemoteNotification() {
		if launching {
			return
		}
		if fetching {
			request = true
		}
		fetching = true

		var changedRecords = [CKRecordID: CKRecord]()
		var deletedRecordIDs = Set<CKRecordID>()
		let operation = CKFetchRecordChangesOperation(recordZoneID: zoneID, previousServerChangeToken: previousServerChangeToken)
		operation.recordChangedBlock = { record in
			changedRecords[record.recordID] = record
		}
		operation.recordWithIDWasDeletedBlock = { recordID in
			deletedRecordIDs.insert(recordID)
			changedRecords.removeValueForKey(recordID)
		}
		operation.fetchRecordChangesCompletionBlock = { serverChangeToken, clientChangeTokenData, error in
			if error != nil {
				print("#\(__LINE__) error : \(error)")
			}
			self.previousServerChangeToken = serverChangeToken
			self.previousClientChangeTokenData = clientChangeTokenData

			var appendRecords = [CKRecord]()
			var deleteRecords = [CKRecord]()
			var appendIndexPaths = [NSIndexPath]()
			var deleteIndexPaths = [NSIndexPath]()
			var updateIndexPaths = [NSIndexPath]()
			for newRecord in changedRecords.values {
				var found = false
				for (i, record) in self.records.enumerate() {
					if newRecord.recordID.recordName == record.recordID.recordName {
					/*	if newRecord.recordChangeTag == record.recordChangeTag {
							print("#\(__LINE__) non update \(newRecord.text)")
							break
						}*/
						found = true
						if newRecord.text != record.text {
							print("#\(__LINE__) update \(record.text) -> \(newRecord.text)")
							self.records[i] = newRecord
							updateIndexPaths.append(NSIndexPath(forRow: i, inSection: 0))
						}
						break
					}
				}
				if !found {
					self.records.append(newRecord)
					appendRecords.append(newRecord)
					print("#\(__LINE__) append \(newRecord.text)")
				}
			}
			for recordID in deletedRecordIDs {
				for (i, record) in self.records.enumerate() {
					if record.recordID.recordName == recordID.recordName {
						print("#\(__LINE__) delete \(record.text)")
						deleteRecords.append(record)
						deleteIndexPaths.append(NSIndexPath(forRow: i, inSection: 0))
						break
					}
				}
			}
			for record in deleteRecords {
				self.records.removeAtIndex(self.records.indexOf(record)!)
			}
			self.records.sortInPlace() { $0.date.compare($1.date) == .OrderedAscending }
			for record in appendRecords {
				appendIndexPaths.append(NSIndexPath(forRow: self.records.indexOf(record)!, inSection: 0))
			}

			dispatch_async(dispatch_get_main_queue()) {
				self.tableView.beginUpdates()
				if updateIndexPaths.count != 0 {
					self.tableView.reloadRowsAtIndexPaths(updateIndexPaths, withRowAnimation: .Fade)
				}
				if deleteIndexPaths.count != 0 {
					self.tableView.deleteRowsAtIndexPaths(deleteIndexPaths, withRowAnimation: .Fade)
				}
				if appendIndexPaths.count != 0 {
					self.tableView.insertRowsAtIndexPaths(appendIndexPaths, withRowAnimation: .Fade)
				}
				self.tableView.endUpdates()
			}
			if operation.moreComing  {
				print("#\(__LINE__) moreComing")
				self.receiveRemoteNotification()
			}
			else {
				self.fetching = false

				if self.request {
					self.request = false
					print("#\(__LINE__) request coming")
					self.receiveRemoteNotification()
				}
			}
		}
		database.addOperation(operation)
	}

	// MARK: - UITextField Delegate

	func textFieldDidEndEditing(textField: UITextField) {
		var saveRecords = [CKRecord]()
		var deleteRecordIDs = [CKRecordID]()
		let indexPath = tableView.indexPathForCell(textField.superview!.superview! as! UITableViewCell)!
		if indexPath.row >= records.count {
			if textField.text != "" {
				let record = CKRecord(recordType: "Item", recordID: CKRecordID(recordName: NSUUID().UUIDString, zoneID: zoneID))
				record.date = NSDate()
				record.text = textField.text!
				records.append(record)
				saveRecords.append(record)

				tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: indexPath.row + 1, inSection: indexPath.section)], withRowAnimation: .Fade)
			}
		}
		else if textField.text == "" {
			deleteRecordIDs.append(records[indexPath.row].recordID)
			records.removeAtIndex(indexPath.row)

			tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
		}
		else {
			let record = records[indexPath.row]
			record.text = textField.text!
			saveRecords.append(record)
		}
		if saveRecords.count != 0 || deleteRecordIDs.count != 0 {
			let operation = CKModifyRecordsOperation(recordsToSave: saveRecords, recordIDsToDelete: deleteRecordIDs)
			operation.clientChangeTokenData = previousClientChangeTokenData
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
		return records.count + 1
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
		let field = cell.viewWithTag(1) as! UITextField
		field.delegate = self
		if indexPath.row < records.count {
			field.text = records[indexPath.row].text
		}
		else {
			field.text = ""
		}
		return cell
	}
}
