import FichaCore
import Foundation
import Testing

struct HomeFolderPathTests {
    @Test("a folder in the home folder starts with a tilde, as the group's Backups folder does in the sandbox")
    func aFolderInTheHomeFolderStartsWithATilde() {
        let backups = URL(
            filePath: "/Users/someone/Library/Group Containers/ABCDE12345.com.lucastkacz.ficha.dev/Ficha Dev/Backups/",
            directoryHint: .isDirectory)

        #expect(
            backups.path(abbreviatingHome: "/Users/someone")
                == "~/Library/Group Containers/ABCDE12345.com.lucastkacz.ficha.dev/Ficha Dev/Backups")
    }

    @Test("a folder outside the home folder keeps its whole path, even when its name starts as the home folder's")
    func aFolderOutsideTheHomeFolderKeepsItsWholePath() {
        let backups = URL(filePath: "/Users/someone else/Ficha/Backups/", directoryHint: .isDirectory)

        #expect(backups.path(abbreviatingHome: "/Users/someone") == "/Users/someone else/Ficha/Backups")
    }
}
