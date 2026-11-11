//
//  StartWalkChoice.swift
//  GassiPassCore
//

import Foundation

/// What "Start Walk" does when the walker taps it.
public enum StartWalkChoice: Equatable {
    /// Starts the walk with this dog, without the sheet that chooses the dogs.
    case startAtOnce(Dog)
    /// Opens the sheet that chooses the dogs, with these dogs already chosen.
    case chooseDogs(chosen: Set<UUID>)

    /// Retired dogs cannot join walks. When only one dog can join walks,
    /// the walk starts at once with that dog. If not, the sheet opens with
    /// the shown dog already chosen, unless it is a retired dog.
    public static func onTap(dogs: [Dog], shownDog: Dog?) -> Self {
        let joining = dogs.filter { !$0.isRetired }
        if joining.count == 1 {
            return .startAtOnce(joining[0])
        }
        let chosen = joining.filter { $0 == shownDog }.map(\.id)
        return .chooseDogs(chosen: Set(chosen))
    }
}
