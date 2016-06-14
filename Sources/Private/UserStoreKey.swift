import Foundation

internal enum UserStoreKey: String {

	// MARK: Bools

	case FirstStart = "webtrekk_firstStart"
	case OptedOut = "webtrekk_optedOut"
	case Sampled = "webtrekk_sampled"

	// MARK: Strings

	case Eid = "webtrekk_eid"
	case VersionNumber = "webtrekk_versionNumber"

}

extension NSUserDefaults {

	internal func boolForKey(defaultName: UserStoreKey) -> Bool {
		return self.boolForKey(defaultName.rawValue)
	}


	internal func objectForKey(defaultName: UserStoreKey) -> AnyObject? {
		return objectForKey(defaultName.rawValue)
	}


	internal func setBool(value: Bool, forKey key: UserStoreKey) {
		self.setBool(value, forKey: key.rawValue)
	}


	internal func stringForKey(defaultName: UserStoreKey) -> String? {
		return self.stringForKey(defaultName.rawValue)
	}
}