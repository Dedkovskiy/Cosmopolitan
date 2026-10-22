import SwiftUI

extension Model {
    func launchCmd(_ exe: String) -> (String, [String]) {
        if let g = steamGames[exe], let r = exe.range(of: "/steamapps/") {
            let steam = String(exe[..<r.lowerBound]) + "/steam.exe"
            return (winPath(steam), extraArgs(steam) + ["-applaunch", g.id])
        }
        return (winPath(exe), extraArgs(exe))
    }
}
