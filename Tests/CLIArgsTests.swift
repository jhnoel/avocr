import XCTest
@testable import AVOCRLib

final class CLIArgsTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    func makeArgs(inputs: [String] = ["test.pdf"]) -> CLIArgs {
        var args = CLIArgs()
        args.inputs = inputs
        return args
    }
    
    // MARK: - Validation Tests
    
    func testValidateNoInputsInNonWorkerMode() throws {
        var args = CLIArgs()
        XCTAssertThrowsError(try args.validate()) { error in
            XCTAssertNotNil(error, "Expected an error when no inputs provided")
        }
    }
    
    func testValidateWithValidInput() throws {
        var args = makeArgs()
        XCTAssertNoThrow(try args.validate())
        XCTAssertEqual(args.inputs.count, 1)
        XCTAssertEqual(args.inputs[0], "test.pdf")
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultDPI() throws {
        let args = CLIArgs()
        XCTAssertEqual(args.dpi, 300)
    }
    
    func testDefaultFast() throws {
        let args = CLIArgs()
        XCTAssertFalse(args.fast)
    }
    
    func testDefaultFormat() throws {
        let args = CLIArgs()
        XCTAssertEqual(args.format, .text)
    }
    
    func testDefaultNoHeaders() throws {
        let args = CLIArgs()
        XCTAssertFalse(args.noHeaders)
    }
    
    func testDefaultNoCorrection() throws {
        let args = CLIArgs()
        XCTAssertFalse(args.noCorrection)
    }
    
    func testDefaultPerPage() throws {
        let args = CLIArgs()
        XCTAssertFalse(args.perPage)
    }
    
    func testDefaultIncludeHidden() throws {
        let args = CLIArgs()
        XCTAssertFalse(args.includeHidden)
    }
    
    func testDefaultUseExistingText() throws {
        let args = CLIArgs()
        XCTAssertTrue(args.useExistingText)
    }

    func testDefaultPrefetch() throws {
        let args = CLIArgs()
        XCTAssertEqual(args.prefetch, 2)
    }
    
    // MARK: - Flag Tests
    
    func testFastFlag() throws {
        var args = makeArgs()
        args.fast = true
        XCTAssertTrue(args.fast)
    }
    
    func testUseExistingTextFlag() throws {
        var args = makeArgs()
        args.useExistingText = true
        XCTAssertTrue(args.useExistingText)
    }
    
    func testNoHeadersFlag() throws {
        var args = makeArgs()
        args.noHeaders = true
        XCTAssertTrue(args.noHeaders)
    }
    
    func testNoCorrectionFlag() throws {
        var args = makeArgs()
        args.noCorrection = true
        XCTAssertTrue(args.noCorrection)
    }
    
    func testPerPageFlag() throws {
        var args = makeArgs()
        args.perPage = true
        XCTAssertTrue(args.perPage)
    }
    
    func testIncludeHiddenFlag() throws {
        var args = makeArgs()
        args.includeHidden = true
        XCTAssertTrue(args.includeHidden)
    }

    func testPrefetchOption() throws {
        var args = makeArgs()
        args.prefetch = 4
        XCTAssertEqual(args.prefetch, 4)
    }
    
    // MARK: - Option Tests
    
    func testDPIOption() throws {
        var args = makeArgs()
        args.dpi = 400
        XCTAssertEqual(args.dpi, 400)
    }
    
    func testFormatOption() throws {
        var args = makeArgs()
        args.format = .jsonl
        XCTAssertEqual(args.format, .jsonl)
    }
    
    func testLangOption() throws {
        var args = makeArgs()
        args.languageString = "en-US,fr-FR"
        let languages = args.languages
        XCTAssertEqual(languages.count, 2)
        XCTAssertTrue(languages.contains("en-US"))
        XCTAssertTrue(languages.contains("fr-FR"))
    }

    func testLanguagesTrimWhitespaceAndIgnoreEmptyComponents() throws {
        var args = makeArgs()
        args.languageString = " en-US, fr-FR, ,de-DE "
        XCTAssertEqual(args.languages, ["en-US", "fr-FR", "de-DE"])
    }
    
    func testOutputOption() throws {
        var args = makeArgs()
        args.output = "/tmp/output"
        XCTAssertEqual(args.output, "/tmp/output")
    }
    
    func testColumnsOption() throws {
        var args = makeArgs()
        args.columns = .fixed(2)
        if case .fixed(let count) = args.columns {
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("Expected fixed column mode")
        }
    }
    
    // MARK: - Language Parsing Tests
    
    func testLanguagesParsing() throws {
        var args = makeArgs()
        args.languageString = "en-US,fr-FR,de-DE"
        let languages = args.languages
        XCTAssertEqual(languages.count, 3)
        XCTAssertTrue(languages.contains("en-US"))
        XCTAssertTrue(languages.contains("fr-FR"))
        XCTAssertTrue(languages.contains("de-DE"))
    }
    
    func testLanguagesDefaultValue() throws {
        let args = CLIArgs()
        let languages = args.languages
        XCTAssertEqual(languages.count, 1)
        XCTAssertEqual(languages[0], "en-US")
    }
    
    // MARK: - Multiple Inputs
    
    func testMultipleInputs() throws {
        let args = makeArgs(inputs: ["file1.pdf", "file2.jpg", "file3.png"])
        XCTAssertEqual(args.inputs.count, 3)
        XCTAssertEqual(args.inputs[0], "file1.pdf")
        XCTAssertEqual(args.inputs[1], "file2.jpg")
        XCTAssertEqual(args.inputs[2], "file3.png")
    }
    
    // MARK: - Column Mode Tests
    
    func testColumnModeAuto() {
        let columnMode = ColumnMode(argument: "auto")
        XCTAssertNotNil(columnMode)
        if case .auto = columnMode! {
            // Success
        } else {
            XCTFail("Expected auto mode")
        }
    }
    
    func testColumnModeFixed() {
        let columnMode1 = ColumnMode(argument: "1")
        XCTAssertNotNil(columnMode1)
        if case .fixed(let count) = columnMode1! {
            XCTAssertEqual(count, 1)
        } else {
            XCTFail("Expected fixed mode with 1 column")
        }
        
        let columnMode2 = ColumnMode(argument: "2")
        XCTAssertNotNil(columnMode2)
        if case .fixed(let count) = columnMode2! {
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("Expected fixed mode with 2 columns")
        }
        
        let columnMode3 = ColumnMode(argument: "3")
        XCTAssertNotNil(columnMode3)
        if case .fixed(let count) = columnMode3! {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected fixed mode with 3 columns")
        }
    }
    
    func testColumnModeInvalid() {
        let invalidModes = ["0", "4", "5", "-1", "invalid"]
        
        for mode in invalidModes {
            let columnMode = ColumnMode(argument: mode)
            XCTAssertNil(columnMode, "\(mode) should be invalid")
        }
    }
    
    // MARK: - JobsValue Tests
    
    func testJobsValueParsing() {
        let jobs1 = JobsValue(argument: "4")
        XCTAssertNotNil(jobs1)
        XCTAssertEqual(jobs1?.value, 4)
        XCTAssertFalse(jobs1?.isMax ?? true)
        
        let jobsMax = JobsValue(argument: "max")
        XCTAssertNotNil(jobsMax)
        XCTAssertNil(jobsMax?.value)
        XCTAssertTrue(jobsMax?.isMax ?? false)
        
        let jobsInvalid = JobsValue(argument: "0")
        XCTAssertNil(jobsInvalid)
        
        let jobsNegative = JobsValue(argument: "-5")
        XCTAssertNil(jobsNegative)
        
        let jobsText = JobsValue(argument: "invalid")
        XCTAssertNil(jobsText)
    }
    
    // MARK: - PDF Text Mode Tests
    
    func testPDFTextModeDefault() throws {
        let args = CLIArgs()
        XCTAssertEqual(args.pdfTextMode, .auto)
    }

    func testPDFTextModeForceOCR() throws {
        var args = makeArgs()
        args.useExistingText = false
        XCTAssertEqual(args.pdfTextMode, .ocr)
    }
    
    // MARK: - Jobs/Workers Tests
    
    func testJobsDefaultValue() throws {
        let args = CLIArgs()
        let jobs = args.jobs
        let expectedJobs = max(1, ProcessInfo.processInfo.activeProcessorCount)
        XCTAssertEqual(jobs, expectedJobs)
    }
    
    func testMultiprocessFlag() throws {
        var args1 = makeArgs()
        args1.workers = JobsValue(argument: "1")
        XCTAssertFalse(args1.multiprocess)
        
        var args2 = makeArgs()
        args2.workers = JobsValue(argument: "4")
        XCTAssertTrue(args2.multiprocess)
    }
    
    // MARK: - Invalid Input Tests

    func testInvalidDPIThrows() {
        var args = makeArgs()
        args.dpi = 0
        XCTAssertThrowsError(try args.validate())
        args.dpi = -100
        XCTAssertThrowsError(try args.validate())
    }

    func testInvalidMinTextHeightThrows() {
        var args = makeArgs()
        args.minTextHeight = 0
        XCTAssertThrowsError(try args.validate())
        args.minTextHeight = 1.1
        XCTAssertThrowsError(try args.validate())
    }

    func testInvalidWorkersThrows() {
        XCTAssertNil(JobsValue(argument: "0"))
        XCTAssertNil(JobsValue(argument: "-1"))
    }

    func testInvalidFormatThrows() {
        XCTAssertNil(OutputFormat(argument: "xml"))
        XCTAssertNil(OutputFormat(argument: ""))
    }

    func testInvalidPrefetchThrows() {
        var args = makeArgs()
        args.prefetch = 0
        XCTAssertThrowsError(try args.validate())
        args.prefetch = -2
        XCTAssertThrowsError(try args.validate())
    }

    func testInvalidRetriesAndMaxErrorsThrow() {
        var args = makeArgs()
        args.retries = -1
        XCTAssertThrowsError(try args.validate())

        args = makeArgs()
        args.maxErrors = 0
        XCTAssertThrowsError(try args.validate())
    }

    func testEmbedTextLayerRejectsIncompatibleOutputModes() {
        var args = makeArgs()
        args.embedTextLayer = true
        args.stdout = true
        XCTAssertThrowsError(try args.validate())

        args = makeArgs()
        args.embedTextLayer = true
        args.format = .jsonl
        XCTAssertThrowsError(try args.validate())

        args = makeArgs()
        args.embedTextLayer = true
        args.perPage = true
        XCTAssertThrowsError(try args.validate())
    }

    func testROIMustFitWithinUnitRectangle() {
        var args = makeArgs()
        args.roiString = "0.8,0.1,0.3,0.2"
        XCTAssertThrowsError(try args.validate())

        args.roiString = "0.1,0.8,0.2,0.3"
        XCTAssertThrowsError(try args.validate())

        args.roiString = "0.1,0.1,0,0.2"
        XCTAssertThrowsError(try args.validate())
    }
}
