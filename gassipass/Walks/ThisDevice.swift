//
//  ThisDevice.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 04.10.2026.
//

import UIKit

/// The device that the app runs on, for the walks that it records. With
/// iCloud sync, the other devices of the user see a walk while this device
/// records it, and only this device may continue it.
enum ThisDevice {
    /// The ID of this device. It comes from `identifierForVendor`, because
    /// a backup that the user restores to a new phone does not copy it.
    /// Before the first unlock after a restart the system has no ID yet, and
    /// the app uses a new random ID, so that it continues no walk.
    static let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
}
