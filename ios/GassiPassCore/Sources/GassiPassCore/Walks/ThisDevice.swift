//
//  ThisDevice.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 04.10.2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The device that the app runs on. A walk notes the device that started
/// it, and the copy of the Core Data store ends the unfinished walk of
/// another device (`LocalStore.copyPrivateStore(from:into:at:deviceID:)`).
public enum ThisDevice {
    /// The ID of this device. It comes from `identifierForVendor`, because
    /// a backup that the user restores to a new phone does not copy it.
    /// Before the first unlock after a restart the system has no ID yet, and
    /// the app uses a new random ID.
    /// On a Mac, where only the tests run, it is a new random ID.
    #if canImport(UIKit)
    public static let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    #else
    public static let id = UUID().uuidString
    #endif
}
