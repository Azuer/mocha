//
//  UnixArchiveReader.swift
//  mocha
//
//  Created by white on 2021/6/15.
//

import Foundation
import SwiftUI

struct UnixArchiveFileHeader {
    
    // unix archive file header format ref:
    // https://en.wikipedia.org/wiki/Ar_(Unix)
    
    let fileID: String
    var modificationTS: String?
    var ownerID: String?
    var groupID: String?
    var fileMode: String? // Octal number
    let extFileIDLengthInt: Int // non-zero when fileID is prefixed with #1/
    let contentSize: Int // size of the content file
    
    init(with dataShifter: inout DataShifter) {
        let fileIDData = dataShifter.shift(.rawNumber(16))
        guard let fileID = fileIDData.utf8String else { fatalError() /* Very unlikely */}
        
        self.modificationTS = dataShifter.shift(.rawNumber(12)).utf8String
        self.ownerID = dataShifter.shift(.rawNumber(6)).utf8String
        self.groupID = dataShifter.shift(.rawNumber(6)).utf8String
        self.fileMode = dataShifter.shift(.quadWords).utf8String
        guard let contentSizeString = dataShifter.shift(.rawNumber(10)).utf8String else { fatalError() /* Very unlikely */ }
        guard let contentSize = Int(contentSizeString.spaceRemoved) else { fatalError() /* Very unlikely */ }
        self.contentSize = contentSize
        
        // unix archive header always ends with 0x60 0x0A
        guard dataShifter.shift(.word).utf8String == "`\n" else { fatalError() /* Very unlikely */ }
        
        // BSD ar stores filenames right-padded with ASCII spaces.
        // This causes issues with spaces inside filenames.
        // 4.4BSD ar stores extended filenames by placing the string "#1/" followed by the file name length in the file name field,
        // and storing the real filename in front of the data section.
        if fileID.hasPrefix("#1/") {
            guard let extFileIDLength = fileIDData.select(from: 3, length: 13).utf8String else { fatalError() /* Very unlikely */ }
            guard let extFileIDLengthInt = Int(extFileIDLength.spaceRemoved) else { fatalError() /* Very unlikely */ }
            // fetch more data from the ar file dataShifter
            guard let extendedFileID = dataShifter.shift(.rawNumber(extFileIDLengthInt)).utf8String else { fatalError() /* Very unlikely */ }
            self.fileID = extendedFileID.spaceRemoved
            self.extFileIDLengthInt = extFileIDLengthInt
        } else {
            self.fileID = fileID.spaceRemoved
            self.extFileIDLengthInt = 0
        }
    }
}

struct UnixArchive {
    
    let fileHeaders: [UnixArchiveFileHeader]
    let machos: [Macho]
    
    init(with fileData: Data) {
        var fileHeaders: [UnixArchiveFileHeader] = []
        var machos: [Macho] = []
        
        var dataShifter = DataShifter(fileData)
        dataShifter.skip(.quadWords) // throw away magic
        
        while dataShifter.shiftable {
            let fileHeader = UnixArchiveFileHeader(with: &dataShifter)
            
            // ref: http://mirror.informatimago.com/next/developer.apple.com/documentation/DeveloperTools/Conceptual/MachORuntime/8rt_file_format/chapter_10_section_33.html
            // The first member in a static archive library is always the symbol table describing the contents of the rest of the member files.
            // This member is always called either __.SYMDEF or __.SYMDEF SORTED.
            // So we are dropping the first element
            if fileHeader.fileID.hasPrefix("__.SYMDEF") {
                dataShifter.skip(.rawNumber(fileHeader.contentSize - fileHeader.extFileIDLengthInt))
                continue
            }
            
            fileHeaders.append(fileHeader)
            
            let machoData = fileData.select(from: dataShifter.shifted,
                                            length: fileHeader.contentSize - fileHeader.extFileIDLengthInt)
            machos.append(Macho(with: machoData, machoFileName: fileHeader.fileID))
            dataShifter.skip(.rawNumber(fileHeader.contentSize - fileHeader.extFileIDLengthInt))
        }
        
        self.fileHeaders = fileHeaders
        self.machos = machos
    }
}
