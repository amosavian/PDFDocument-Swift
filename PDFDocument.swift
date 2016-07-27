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
    let reference: CGPDFDocumentRef
    let data: NSData?
    
    var pagesCount: Int {
        return CGPDFDocumentGetNumberOfPages(reference)
    }
    
    var allowsCopying: Bool {
        return CGPDFDocumentAllowsCopying(reference)
    }
    
    var allowsPrinting: Bool {
        return CGPDFDocumentAllowsPrinting(reference)
    }
    
    var isEncrypted: Bool {
        return CGPDFDocumentIsEncrypted(reference)
    }
    
    var isUnlocked: Bool {
        return CGPDFDocumentIsUnlocked(reference)
    }
    
    var version: (major: Int, minor: Int) {
        var majorVersion: Int32 = 0;
        var minorVersion: Int32 = 0;
        CGPDFDocumentGetVersion(reference, &majorVersion, &minorVersion);
        return (Int(majorVersion), Int(minorVersion))
    }
    
    private func getKey(key: String, from dict: CGPDFDictionaryRef) -> String? {
        var cfValue: CGPDFStringRef = nil
        if (CGPDFDictionaryGetString(dict, key, &cfValue)), let value = CGPDFStringCopyTextString(cfValue) {
            return value as String
        }
        return nil
    }
    
    var pages: [PDFPage] = []
    var title: String?
    var author: String?
    var creator: String?
    var subject: String?
    var creationDate: NSDate?
    var modifiedDate: NSDate?
    
    dynamic func updateFields() {
        func convertDate(date: String) -> NSDate? {
            var dateStr = date
            if dateStr.hasPrefix("D:") {
                dateStr = date.substringFromIndex(date.startIndex.advancedBy(2))
            }
            let dateFormatter = NSDateFormatter()
            dateFormatter.dateFormat = "yyyyMMddHHmmssTZD"
            if let result = dateFormatter.dateFromString(dateStr) {
                return result
            }
            dateFormatter.dateFormat = "yyyyMMddHHmmss"
            if let result = dateFormatter.dateFromString(dateStr) {
                return result
            }
            return nil
        }
        
        let dict = CGPDFDocumentGetInfo(reference)
        self.title = self.getKey("Title", from: dict)
        self.author = self.getKey("Author", from: dict)
        self.creator = self.getKey("Creator", from: dict)
        self.subject = self.getKey("Subject", from: dict)
        
        if let creationDateString = self.getKey("CreationDate", from: dict) {
            self.creationDate = convertDate(creationDateString)
        }
        
        if let modifiedDateString = self.getKey("ModDate", from: dict) {
            self.modifiedDate = convertDate(modifiedDateString)
        }
        
        let pagesCount = self.pagesCount
        pages.removeAll(keepCapacity: true)
        for i in 1...pagesCount {
            if let pageRef = CGPDFDocumentGetPage(reference, i) {
                let page = PDFPage(reference: pageRef)
                pages.append(page)
            }
        }
    }
    
    func write(url url: NSURL) {
        var infoDict = [String: AnyObject]()
        infoDict[kCGPDFContextTitle as String] = self.title
        infoDict[kCGPDFContextAuthor as String] = self.author
        infoDict[kCGPDFContextCreator as String] = self.creator
        infoDict[kCGPDFContextSubject as String] = self.subject
        
        let anyPage = pages.last
        var rect = anyPage?.frame ?? CGRectZero
        guard let pdfContext = CGPDFContextCreateWithURL(url, &rect, infoDict) else {
            return
        }
        
        for page in self.pages {
            page.draw(pdfContext: pdfContext)
        }
    }
    
    func write(path path: String) {
        let url = NSURL(fileURLWithPath: path)
        self.write(url: url)
    }
    
    init (reference: CGPDFDocumentRef) {
        self.reference = reference
        data = nil
        updateFields()
    }
    
    init? (data: NSData) {
        let myPDFData: CFDataRef = data;
        if let provider = CGDataProviderCreateWithCFData(myPDFData), reference = CGPDFDocumentCreateWithProvider(provider) {
            self.reference = reference
            self.data = data
            updateFields()
            return
        }
        return nil
    }
    
    init? (images: [UIImage]) {
        let pdfData = NSMutableData()
        guard let pdfConsumer = CGDataConsumerCreateWithCFData(pdfData), let pdfContext = CGPDFContextCreate(pdfConsumer, nil, nil) else {
            return nil
        }
        
        for image in images where image.CGImage != nil {
            let pageWidth = image.size.width
            let pageHeight = image.size.height
            
            var pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight);
            CGContextBeginPage(pdfContext, &pageRect);
            CGContextDrawImage(pdfContext, pageRect, image.CGImage!);
            CGContextEndPage(pdfContext);
        }
        
        CGPDFContextClose(pdfContext)
        
        if pdfData.length == 0 {
            return nil
        }
        
        self.data = pdfData
        if let provider = CGDataProviderCreateWithCFData(pdfData), reference = CGPDFDocumentCreateWithProvider(provider) {
            self.reference = reference
            updateFields()
            return
        }
        return nil
    }
    
    convenience init? (url: NSURL) {
        if let data = NSData(contentsOfURL: url) {
            self.init(data: data)
        } else {
            return nil
        }
    }
    
    convenience init? (path: String) {
        if let data = NSData(contentsOfFile: path) {
            self.init(data: data)
        } else {
            return nil
        }
    }
    
    func unlock(password: String) -> Bool {
        return CGPDFDocumentUnlockWithPassword(reference, (password as NSString).UTF8String)
    }
}

class PDFPage {
    let reference: CGPDFPageRef
    let pageNumber: Int
    let frame: CGRect
    
    init(reference: CGPDFPageRef) {
        self.reference = reference
        self.pageNumber = CGPDFPageGetPageNumber(reference);
        self.frame = CGPDFPageGetBoxRect(reference, CGPDFBox.MediaBox);
    }
    
    var size: CGSize {
        return frame.size
    }
    
    func draw(pdfContext context: CGContextRef) {
        let size = frame.size
        var rect = CGRectMake(0, 0, size.width, size.height)
        let boxData = NSData(bytes: &rect, length: sizeofValue(rect))
        let pageDict = [kCGPDFContextMediaBox as String : boxData]
        
        CGPDFContextBeginPage(context, pageDict);
        CGContextDrawPDFPage(context, reference);
        CGPDFContextEndPage(context);
    }
    
    func draw(context context: CGContextRef, atSize drawSize: CGSize) {
        // Flip coordinates
        CGContextGetCTM(context);
        CGContextScaleCTM(context, 1, -1);
        CGContextTranslateCTM(context, 0, -drawSize.height);
        
        // get the rectangle of the cropped inside
        let mediaRect = CGPDFPageGetBoxRect(reference, CGPDFBox.CropBox);
        CGContextScaleCTM(context, drawSize.width / mediaRect.size.width,
                          drawSize.height / mediaRect.size.height);
        CGContextTranslateCTM(context, -mediaRect.origin.x, -mediaRect.origin.y);
        
        CGContextDrawPDFPage(context, reference);
        CGPDFContextEndPage(context);
    }
    
    func image(pixelsPerPoint ppp: Int = 1) -> PDFDocumentImageClass? {
        var size = frame.size
        let rect = CGRectMake(0, 0, size.width, size.height)
        size.width  *= CGFloat(ppp)
        size.height *= CGFloat(ppp)
        
        UIGraphicsBeginImageContext(size)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        CGContextSaveGState(context)
        let transform = CGPDFPageGetDrawingTransform(reference, CGPDFBox.MediaBox, rect, 0, true)
        CGContextConcatCTM(context, transform)
        
        CGContextTranslateCTM(context, 0, size.height)
        CGContextScaleCTM(context, CGFloat(ppp), CGFloat(-ppp))
        CGContextDrawPDFPage(context, reference);
        
        CGContextRestoreGState(context);
        
        let resultingImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return resultingImage;
    }
}