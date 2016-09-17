//
//  PDFDocuments.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/7/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation
import CoreGraphics
#if os(iOS)
import UIKit
typealias PDFDocumentImageClass = UIImage
#elseif os(OSX)
import Cocoa
typealias PDFDocumentImageClass = NSImage
#endif

class PDFDocument {
    let reference: CGPDFDocument
    let data: Data?
    
    var pagesCount: Int {
        return reference.numberOfPages
    }
    
    var allowsCopying: Bool {
        return reference.allowsCopying
    }
    
    var allowsPrinting: Bool {
        return reference.allowsPrinting
    }
    
    var isEncrypted: Bool {
        return reference.isEncrypted
    }
    
    var isUnlocked: Bool {
        return reference.isUnlocked
    }
    
    var version: (major: Int, minor: Int) {
        var majorVersion: Int32 = 0;
        var minorVersion: Int32 = 0;
        reference.getVersion(majorVersion: &majorVersion, minorVersion: &minorVersion);
        return (Int(majorVersion), Int(minorVersion))
    }
    
    fileprivate func getKey(_ key: String, from dict: CGPDFDictionaryRef) -> String? {
        var cfValue: CGPDFStringRef? = nil
        if (CGPDFDictionaryGetString(dict, key, &cfValue)), let value = CGPDFStringCopyTextString(cfValue!) {
            return value as String
        }
        return nil
    }
    
    var pages: [PDFPage] = []
    var title: String?
    var author: String?
    var creator: String?
    var subject: String?
    var creationDate: Date?
    var modifiedDate: Date?
    
    dynamic func updateFields() {
        func convertDate(_ date: String) -> Date? {
            var dateStr = date
            if dateStr.hasPrefix("D:") {
                dateStr = date.substring(from: date.characters.index(date.startIndex, offsetBy: 2))
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMddHHmmssTZD"
            if let result = dateFormatter.date(from: dateStr) {
                return result
            }
            dateFormatter.dateFormat = "yyyyMMddHHmmss"
            if let result = dateFormatter.date(from: dateStr) {
                return result
            }
            return nil
        }
        
        let dict = reference.info
        self.title = self.getKey("Title", from: dict!)
        self.author = self.getKey("Author", from: dict!)
        self.creator = self.getKey("Creator", from: dict!)
        self.subject = self.getKey("Subject", from: dict!)
        
        if let creationDateString = self.getKey("CreationDate", from: dict!) {
            self.creationDate = convertDate(creationDateString)
        }
        
        if let modifiedDateString = self.getKey("ModDate", from: dict!) {
            self.modifiedDate = convertDate(modifiedDateString)
        }
        
        let pagesCount = self.pagesCount
        pages.removeAll(keepingCapacity: true)
        for i in 1...pagesCount {
            if let pageRef = reference.page(at: i) {
                let page = PDFPage(reference: pageRef)
                pages.append(page)
            }
        }
    }
    
    func write(url: URL) {
        var infoDict = [String: AnyObject]()
        infoDict[kCGPDFContextTitle as String] = self.title as NSString?
        infoDict[kCGPDFContextAuthor as String] = self.author as NSString?
        infoDict[kCGPDFContextCreator as String] = self.creator as NSString?
        infoDict[kCGPDFContextSubject as String] = self.subject as NSString?
        
        let anyPage = pages.last
        var rect = anyPage?.frame ?? CGRect.zero
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &rect, infoDict as CFDictionary?) else {
            return
        }
        
        for page in self.pages {
            page.draw(pdfContext: pdfContext)
        }
    }
    
    func write(path: String) {
        let url = URL(fileURLWithPath: path)
        self.write(url: url)
    }
    
    init (reference: CGPDFDocument) {
        self.reference = reference
        data = nil
        updateFields()
    }
    
    init? (data: Data) {
        let myPDFData: CFData = data as CFData;
        if let provider = CGDataProvider(data: myPDFData), let reference = CGPDFDocument(provider) {
            self.reference = reference
            self.data = data
            updateFields()
            return
        }
        return nil
    }
    
    init? (images: [UIImage]) {
        let pdfData = NSMutableData()
        guard let pdfConsumer = CGDataConsumer(data: pdfData), let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: nil, nil) else {
            return nil
        }
        
        for image in images where image.cgImage != nil {
            let pageWidth = image.size.width
            let pageHeight = image.size.height
            
            var pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight);
            pdfContext.beginPage(mediaBox: &pageRect);
            pdfContext.draw(image.cgImage!, in: pageRect)
            pdfContext.endPage();
        }
        
        pdfContext.closePDF()
        
        if pdfData.length == 0 {
            return nil
        }
        
        self.data = pdfData as Data
        if let provider = CGDataProvider(data: pdfData), let reference = CGPDFDocument(provider) {
            self.reference = reference
            updateFields()
            return
        }
        return nil
    }
    
    convenience init? (url: URL) {
        if let data = try? Data(contentsOf: url as URL) {
            self.init(data: data)
        } else {
            return nil
        }
    }
    
    convenience init? (path: String) {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            self.init(data: data)
        } else {
            return nil
        }
    }
    
    func unlock(_ password: String) -> Bool {
        return reference.unlockWithPassword((password as NSString).utf8String!)
    }
}

class PDFPage {
    let reference: CGPDFPage
    let pageNumber: Int
    let frame: CGRect
    
    init(reference: CGPDFPage) {
        self.reference = reference
        self.pageNumber = reference.pageNumber;
        self.frame = reference.getBoxRect(CGPDFBox.mediaBox);
    }
    
    var size: CGSize {
        return frame.size
    }
    
    func draw(pdfContext context: CGContext) {
        let size = frame.size
        var rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let boxData = NSData(bytes: &rect, length: MemoryLayout.size(ofValue: rect))
        let pageDict = [kCGPDFContextMediaBox as String : boxData]
        
        context.beginPDFPage(pageDict as CFDictionary?);
        context.drawPDFPage(reference);
        context.endPDFPage();
    }
    
    func draw(_ context: CGContext, atSize drawSize: CGSize) {
        // Flip coordinates
        _ = context.ctm;
        context.scaleBy(x: 1, y: -1);
        context.translateBy(x: 0, y: -drawSize.height);
        
        // get the rectangle of the cropped inside
        let mediaRect = reference.getBoxRect(CGPDFBox.cropBox);
        context.scaleBy(x: drawSize.width / mediaRect.size.width,
                          y: drawSize.height / mediaRect.size.height);
        context.translateBy(x: -mediaRect.origin.x, y: -mediaRect.origin.y);
        
        context.drawPDFPage(reference);
        context.endPDFPage();
    }
    
    func image(pixelsPerPoint ppp: Int = 1) -> PDFDocumentImageClass? {
        var size = frame.size
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        size.width  *= CGFloat(ppp)
        size.height *= CGFloat(ppp)
        
        UIGraphicsBeginImageContext(size)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        context.saveGState()
        let transform = reference.getDrawingTransform(CGPDFBox.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: CGFloat(ppp), y: CGFloat(-ppp))
        context.drawPDFPage(reference);
        
        context.restoreGState();
        
        let resultingImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return resultingImage;
    }
}
