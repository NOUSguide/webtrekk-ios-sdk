//The MIT License (MIT)
//
//Copyright (c) 2016 Webtrekk GmbH
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the
//"Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish,
//distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject
//to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//  Created by arsen.vartbaronov on 08/02/17.
//
//

import Foundation


//these function should be global due to requriements to NSSetUncaughtExceptionHandler
fileprivate func exceptionHandler(exception: NSException){
    
    defer {
        // init old handler
        if let oldHandler = ExceptionTrackerImpl.previousExceptionHandler {
            oldHandler(exception)
        }
    }

    //Save exception to file
    WebtrekkTracking.defaultLogger.logDebug("Webtrekk catched exception: \(exception), callStack: \(exception.callStackSymbols), reason: \(exception.reason), name: \(exception.name), user info: \(dump(exception.userInfo)), return address: \(exception.callStackReturnAddresses)")
    
    ExceptionSaveAndSendHelper.default.saveToFile(name: exception.name.rawValue, stack: exception.callStackSymbols, reason: exception.reason, userInfo: exception.userInfo as NSDictionary?, stackReturnAddress: exception.callStackReturnAddresses)
}

//these function should be global due to requriements to signal handler API
fileprivate func signalHandler(signalNum: Int32){
    
    let signalsMap: [Int32: String] = [4:"SIGILL", 5: "SIGTRAP", 6:"SIGABRT", 8:"SIGFPE", 10:"SIGBUS", 11:"SIGSEGV", 13:"SIGPIPE"]
    //Save exception to file
    defer {
        if let oldSignal = ExceptionTrackerImpl.previousSignalHandlers[signalNum] {
            //just call original one it should exit
            oldSignal(signalNum)
        }
        exit(signalNum)
    }
    
    //Save exception to file
    WebtrekkTracking.defaultLogger.logDebug("Webtrekk catched signal: \(signalsMap[signalNum] ?? "undefined") with dump: \(Thread.callStackSymbols)")
    
    // remove first two items as this is handler function items.
    let stack = Array(Thread.callStackSymbols.suffix(from: 2))
    
    ExceptionSaveAndSendHelper.default.saveToFile(name: "Signal: \(signalsMap[signalNum] ?? String("undefined"))", stack: stack, reason: nil, userInfo: nil, stackReturnAddress: nil)
}

class ExceptionTrackerImpl: ExceptionTracker {
    
    // use var to make it lazy initialized.
    static var previousExceptionHandler: ExceptionHandler
    private static var initialized = false
    fileprivate static var previousSignalHandlers = [Int32: SignalHanlder]()
    private let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE, SIGTRAP]
    private var errorLogLevel: ErrorLogLevel = .disable
    
    typealias SignalHanlder = (@convention(c) (Int32) -> Swift.Void)
    typealias ExceptionHandler = (@convention(c) (NSException) -> Swift.Void)?
    
    fileprivate enum ErrorLogLevel: Int {
        case disable, fatal, catched, info
    }
    
    //here should be defined exceptionTrackingMode
    func initializeExceptionTracking(config: TrackerConfiguration){
        
        // init only once
        guard !ExceptionTrackerImpl.initialized else {
            return
        }
        
        if let errorLogLevel = config.errorLogLevel, (0...3).contains(errorLogLevel)  {
            self.errorLogLevel = ErrorLogLevel(rawValue:errorLogLevel)!
        }
        
        guard satisfyToLevel(level: .fatal) else {
            // don't do anything for disable level
            return
        }
        
        installUncaughtExceptionHandler()
        
        ExceptionTrackerImpl.initialized = true
    }
    
    func sendSavedException(){
        
        guard satisfyToLevel(level: .fatal) else {
            // don't do anything for disable level
            return
        }
        
        ExceptionSaveAndSendHelper.default.loadAndSend(logLevel: self.errorLogLevel)
    }
    
    deinit{
        guard ExceptionTrackerImpl.initialized else {
            return
        }
        
        NSSetUncaughtExceptionHandler(ExceptionTrackerImpl.previousExceptionHandler)
        ExceptionTrackerImpl.previousExceptionHandler = nil
        ExceptionTrackerImpl.initialized = false
    }
    
    private func installUncaughtExceptionHandler(){
        
        // save previous exception handler
        ExceptionTrackerImpl.previousExceptionHandler = NSGetUncaughtExceptionHandler()
        // set Webtrekk one
        NSSetUncaughtExceptionHandler(exceptionHandler)
        
        // setup processing for signals. Save old processing as well
        for signalNum in signals {
            
            // set Webtrekk signal handler and get previoius one
            let oldSignal = signal(signalNum, signalHandler)
            
            // save previoius signal handler
            if oldSignal != nil {
                ExceptionTrackerImpl.previousSignalHandlers[signalNum] = oldSignal
            }
        }
        
        WebtrekkTracking.defaultLogger.logDebug("exception tracking has been initialized")
    }
    
    func trackInfo(_ name: String, message: String){
        guard checkIfInitialized() else {
            return
        }

        guard satisfyToLevel(level: .info) else {
            WebtrekkTracking.defaultLogger.logDebug("Error tracking level isn't correspond to info/warning level. No tracking will be done.")
            return
        }
        
        ExceptionSaveAndSendHelper.default.track(logLevel: self.errorLogLevel, name: name,message: message)
    }
    
    func trackException(_ exception: NSException){
        
        guard checkIfInitialized() else {
            return
        }

        guard satisfyToLevel(level: .catched) else {
            WebtrekkTracking.defaultLogger.logDebug("Error tracking level isn't correspond to caught/exception level. No tracking will be done.")
            return
        }
        
        ExceptionSaveAndSendHelper.default.track(logLevel: self.errorLogLevel, name: exception.name.rawValue, stack: exception.callStackSymbols, message: exception.reason, userInfo: exception.userInfo as NSDictionary?, stackReturnAddress: exception.callStackReturnAddresses)
    }
    
    func trackError(_ error: Error){
        
        guard checkIfInitialized() else {
            return
        }
        guard satisfyToLevel(level: .catched) else {
            WebtrekkTracking.defaultLogger.logDebug("Error tracking level isn't correspond to caught/exception level. No tracking will be done.")
            return
        }
        
        ExceptionSaveAndSendHelper.default.track(logLevel: self.errorLogLevel, name: "Error", message: error.localizedDescription)
    }
    
    func trackNSError(_ error: NSError){
        
        guard checkIfInitialized() else {
            return
        }
        
        guard satisfyToLevel(level: .catched) else {
            WebtrekkTracking.defaultLogger.logDebug("Error tracking level isn't correspond to caught/exception level. No tracking will be done.")
            return
        }
        
        ExceptionSaveAndSendHelper.default.track(logLevel: self.errorLogLevel, name: "NSError",
                                                 message: "code:\(error.code), domain:\(error.domain)", userInfo: error.userInfo as NSDictionary?)
    }
    
    private func checkIfInitialized() -> Bool {
        if !ExceptionTrackerImpl.initialized {
            logError("Webtrekk exception tracking isn't initialited")
        }
        return ExceptionTrackerImpl.initialized
    }
    

    private func satisfyToLevel(level: ErrorLogLevel) -> Bool{
        return self.errorLogLevel.rawValue >= level.rawValue
    }
}

fileprivate class ExceptionSaveAndSendHelper{
    
    private var applicationSupportDir: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    private let exceptionFileName = "webtrekk_exception"
    private let maxParameterLength = 255
    
    // set it var to make it lazy
    fileprivate static var `default` = ExceptionSaveAndSendHelper()
    
    
    private func normalizeStack(stack: [String]?) -> NSString{
        let returnStack = stack?.joined(separator: "|").replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression, range: nil)
        return normalizeField(field: returnStack, fieldName: "stack")
    }
    
    private func normalizeUserInfo(userInfo: NSDictionary?) -> NSString {
        let userInfo = userInfo?.flatMap(){key, value in
            return "\(key):\(value);"
            }.joined()
        
        return normalizeField(field: userInfo, fieldName: "user info")
    }
    
    private func normalizeUserReturnAddress(returnAddress: [NSNumber]?) -> NSString {
        let returnValue = returnAddress?.flatMap({$0.stringValue}).joined(separator: " ")
        
        return normalizeField(field: returnValue, fieldName: "stack return address") ?? ""
    }
    
    // make string not more then 255 length
    private func normalizeField(field: String?, fieldName: String) -> NSString {
        
        guard let fieldUtf8 = field?.utf8, !fieldUtf8.isEmpty else{
            return ""
        }
        
        guard fieldUtf8.count <= 255 else {
            WebtrekkTracking.defaultLogger.logWarning("Field \(fieldName) is more then 255 length during excception tracking. Normalize it by cutting to 255 length.")
            return String(fieldUtf8.prefix(maxParameterLength)) as? NSString ?? ""
        }
        
        return field as? NSString ?? ""
    }
    
    
    fileprivate func saveToFile(name: String, stack: [String], reason: String?, userInfo: NSDictionary?, stackReturnAddress: [NSNumber]?){
        saveToFile(name: normalizeField(field: name, fieldName: "name"), stack: normalizeStack(stack: stack), reason: normalizeField(field: reason, fieldName: "reason"), userInfo: normalizeUserInfo(userInfo: userInfo), stackReturnAddress: normalizeUserReturnAddress(returnAddress: stackReturnAddress))
    }
    
    private func saveToFile(name: NSString, stack: NSString, reason: NSString, userInfo: NSString, stackReturnAddress: NSString){
        
        // get url
        guard let url = newFileURL else {
            return
        }
        
        let array : NSArray = [name, stack, reason, userInfo, stackReturnAddress]
        
        //construct string
        let result = array.write(to: url, atomically: true)
    }
    
    private var newFileURL : URL?{
        
        var url : URL
        var i: Int = 0
        
        repeat {
            let urlValue = applicationSupportDir?.appendingPathComponent(exceptionFileName+"\(i)"+".xml")
            
            if urlValue == nil {
                WebtrekkTracking.defaultLogger.logError("Can't define path for saving exception. Exception tracking for fatal exception won't work")
                return nil
            } else {
                url = urlValue!
            }
            i = i + 1
        } while FileManager.default.fileExists(atPath: url.path)
        return url
    }
    
    private var existedFileURL : URL? {
        
        guard let supportDir = applicationSupportDir?.path else {
            WebtrekkTracking.defaultLogger.logError("can't define path for reading exception. Exception tracking for fatal exception won't work")
            return nil
        }
        
        let enumerator = FileManager.default.enumerator(atPath: supportDir)
        var minimumNumber: Int? = nil
        var fileName: String? = nil
        
        //find file with nimimumID
        enumerator?.forEach(){value in
            if let strValue = value as? String, strValue.contains(exceptionFileName){
                if let range = strValue.range(of: "\\d", options: .regularExpression),
                    let number = Int(strValue.substring(with: range)){

                    if minimumNumber == nil || minimumNumber! > number {
                        minimumNumber = number
                        fileName = strValue
                    }
                }
            }
        }
        
        guard let _ = fileName else {
            return nil
        }
        
        return applicationSupportDir?.appendingPathComponent(fileName!)
    }
    
    // send exception that is saved on NAND
    fileprivate func loadAndSend(logLevel: ExceptionTrackerImpl.ErrorLogLevel){
        
        while let url = self.existedFileURL {
            
            defer {
                // delete file
                do {
                    try FileManager.default.removeItem(atPath: url.path)
                }catch let error{
                    WebtrekkTracking.defaultLogger.logError("Serious problem with saved exception file deletion: \(error). Information about exception can be sent several times")
                }
            }
            
            guard let array = NSArray(contentsOf: url) as? [NSString] else {
                continue
            }
            WebtrekkTracking.defaultLogger.logDebug("exception with data \(array) from file \(url) will be sent")
            // send action
            
            track(logLevel: logLevel, name: array[0], stack: array[1], message: array[2], userInfo: array[3], stackReturnAddress: array[4])
        }
    }
    
    fileprivate func track(logLevel: ExceptionTrackerImpl.ErrorLogLevel, name: String, stack: [String]? = nil, message: String? = nil, userInfo: NSDictionary? = nil, stackReturnAddress: [NSNumber]? = nil){
        track(logLevel: logLevel, name: normalizeField(field: name, fieldName: "name"), stack: normalizeStack(stack: stack), message: normalizeField(field: message, fieldName: "message/reason"), userInfo: normalizeUserInfo(userInfo: userInfo), stackReturnAddress: normalizeUserReturnAddress(returnAddress: stackReturnAddress))
    }
    
    // common function for tracking exception field message can be as message and reason
    private func track(logLevel: ExceptionTrackerImpl.ErrorLogLevel, name: NSString? = nil, stack: NSString? = nil, message: NSString? = nil, userInfo: NSString? = nil, stackReturnAddress: NSString? = nil){
        
        guard let webtrekk = WebtrekkTracking.instance() as? DefaultTracker else {
            WebtrekkTracking.defaultLogger.logDebug("Can't convert to DefaultTracker for sending event")
            return
        }
        
        guard logLevel.rawValue > ExceptionTrackerImpl.ErrorLogLevel.disable.rawValue else {
            WebtrekkTracking.defaultLogger.logDebug("Error level is disabled. Won't do any call")
            return
        }
        
        //define details
        
        var details: [Int: TrackingValue] = [:]
        
        details[910] = .constant(String(logLevel.rawValue))
        
        if let name = name  as? String, !name.isEmpty {
            details[911] = .constant(name)
        }
        if let message = message as? String, !message.isEmpty {
            details[912] = .constant(message)
        }
        if let stack = stack as? String, !stack.isEmpty  {
            details[913] = .constant(stack)
        }
        if let userInfo = userInfo as? String, !userInfo.isEmpty  {
            details[916] = .constant(userInfo)
        }
        if let stackReturnAddress = stackReturnAddress as? String, !stackReturnAddress.isEmpty  {
            details[917] = .constant(stackReturnAddress)
        }
        let action = ActionEvent(actionProperties: ActionProperties(name: "webtrekk_ignore", details: details) , pageProperties: PageProperties(name: nil))
        
        webtrekk.enqueueRequestForEvent(action, type: .exceptionTracking)
    }
}
