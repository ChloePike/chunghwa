import CoreData
import OSLog

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "ChungHwa")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        let log = Logger(subsystem: "org.clash.ChungHwa", category: "storage")
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                log.error("CoreData load failed: \(error, privacy: .public)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
