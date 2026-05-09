import Foundation

public struct WorkItem {
    public let id: Int
    public let path: String
    public let page: Int?
    
    public init(id: Int, path: String, page: Int?) {
        self.id = id
        self.path = path
        self.page = page
    }
}

public struct WorkPlan {
    public let items: [WorkItem]
    public let totalPages: Int
    
    public init(items: [WorkItem], totalPages: Int) {
        self.items = items
        self.totalPages = totalPages
    }
}

func buildWorkPlan(
    files: [URL],
    logger: Logger = NullLogger(),
    batchByDocument: Bool = false
) -> WorkPlan {
    var items: [WorkItem] = []
    var totalPages = 0
    var nextID = 0

    for file in files {
        if FileEnumerator.isImage(file) {
            items.append(WorkItem(id: nextID, path: file.path, page: nil))
            nextID += 1
            totalPages += 1
            continue
        }

        if FileEnumerator.isPDF(file) {
            // Use lightweight CGPDFDocument for page counting instead of full
            // PDFDocument which parses annotations, form fields, and fonts.
            guard let pageCount = PDFRenderer.pageCount(url: file) else {
                logger.warn("Cannot load PDF: \(file.path)")
                continue
            }
            for pageIndex in 0..<pageCount {
                items.append(WorkItem(id: nextID, path: file.path, page: pageIndex))
                nextID += 1
            }
            totalPages += pageCount
        }
    }

    let finalItems: [WorkItem]
    if batchByDocument {
        let sorted = items.sorted { lhs, rhs in
            if lhs.path == rhs.path {
                return (lhs.page ?? -1) < (rhs.page ?? -1)
            }
            return lhs.path < rhs.path
        }
        finalItems = sorted.enumerated().map { index, item in
            WorkItem(id: index, path: item.path, page: item.page)
        }
    } else {
        finalItems = items
    }

    return WorkPlan(items: finalItems, totalPages: totalPages)
}
