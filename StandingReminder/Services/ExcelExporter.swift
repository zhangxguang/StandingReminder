import Foundation

enum ExcelExportError: LocalizedError {
    case archiveTooLarge
    case invalidFileName

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge:
            return "导出的数据量超过 Excel 文件格式限制。"
        case .invalidFileName:
            return "无法创建 Excel 文件中的内部文件名。"
        }
    }
}

struct ExcelExporter {
    static func export(sessions: [WorkSession], snapshotDate: Date = .now) throws -> Data {
        let sortedSessions = sessions.sorted { lhs, rhs in
            if lhs.startAt == rhs.startAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startAt < rhs.startAt
        }

        let files = [
            XLSXFile(name: "[Content_Types].xml", contents: contentTypesXML),
            XLSXFile(name: "_rels/.rels", contents: rootRelationshipsXML),
            XLSXFile(name: "xl/workbook.xml", contents: workbookXML),
            XLSXFile(name: "xl/_rels/workbook.xml.rels", contents: workbookRelationshipsXML),
            XLSXFile(name: "xl/styles.xml", contents: stylesXML),
            XLSXFile(
                name: "xl/worksheets/sheet1.xml",
                contents: worksheetXML(sessions: sortedSessions, snapshotDate: snapshotDate)
            )
        ]

        return try ZIPArchive.make(files: files)
    }

    private static func worksheetXML(sessions: [WorkSession], snapshotDate: Date) -> String {
        var rows = [
            rowXML(
                index: 1,
                cells: [
                    inlineStringCell(reference: "A1", value: "开始时间", style: 1),
                    inlineStringCell(reference: "B1", value: "结束时间", style: 1),
                    inlineStringCell(reference: "C1", value: "状态", style: 1),
                    inlineStringCell(reference: "D1", value: "持续时间（分钟）", style: 1),
                    inlineStringCell(reference: "E1", value: "记录来源", style: 1)
                ],
                height: 24
            )
        ]

        for (offset, session) in sessions.enumerated() {
            let rowIndex = offset + 2
            let durationEnd = session.endAt ?? max(snapshotDate, session.startAt)
            let durationMinutes = max(0, durationEnd.timeIntervalSince(session.startAt) / 60)
            var cells = [
                numberCell(
                    reference: "A\(rowIndex)",
                    value: excelSerialDate(session.startAt),
                    style: 2
                )
            ]

            if let endAt = session.endAt {
                cells.append(
                    numberCell(
                        reference: "B\(rowIndex)",
                        value: excelSerialDate(endAt),
                        style: 2
                    )
                )
            }

            cells.append(contentsOf: [
                inlineStringCell(reference: "C\(rowIndex)", value: session.state.title),
                numberCell(reference: "D\(rowIndex)", value: durationMinutes, style: 3),
                inlineStringCell(
                    reference: "E\(rowIndex)",
                    value: session.isSystemGeneratedRest ? "系统自动" : "手动"
                )
            ])
            rows.append(rowXML(index: rowIndex, cells: cells))
        }

        let finalRow = max(1, sessions.count + 1)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <dimension ref="A1:E\(finalRow)"/>
          <sheetViews>
            <sheetView workbookViewId="0">
              <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
            </sheetView>
          </sheetViews>
          <sheetFormatPr defaultRowHeight="18"/>
          <cols>
            <col min="1" max="2" width="21" customWidth="1"/>
            <col min="3" max="3" width="14" customWidth="1"/>
            <col min="4" max="4" width="20" customWidth="1"/>
            <col min="5" max="5" width="14" customWidth="1"/>
          </cols>
          <sheetData>
        \(rows.joined(separator: "\n"))
          </sheetData>
          <autoFilter ref="A1:E\(finalRow)"/>
        </worksheet>
        """
    }

    private static func rowXML(index: Int, cells: [String], height: Int? = nil) -> String {
        let heightAttributes = height.map { " ht=\"\($0)\" customHeight=\"1\"" } ?? ""
        return "    <row r=\"\(index)\"\(heightAttributes)>\(cells.joined())</row>"
    }

    private static func inlineStringCell(reference: String, value: String, style: Int = 0) -> String {
        let styleAttribute = style == 0 ? "" : " s=\"\(style)\""
        return "<c r=\"\(reference)\" t=\"inlineStr\"\(styleAttribute)><is><t xml:space=\"preserve\">\(xmlEscaped(value))</t></is></c>"
    }

    private static func numberCell(reference: String, value: Double, style: Int) -> String {
        "<c r=\"\(reference)\" s=\"\(style)\"><v>\(String(format: "%.10f", locale: Locale(identifier: "en_US_POSIX"), value))</v></c>"
    }

    private static func excelSerialDate(_ date: Date) -> Double {
        let localOffset = TimeZone.current.secondsFromGMT(for: date)
        return (date.timeIntervalSince1970 + Double(localOffset)) / 86_400 + 25_569
    }

    private static func xmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="工作状态" sheetId="1" r:id="rId1"/>
      </sheets>
    </workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <numFmts count="1">
        <numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm:ss"/>
      </numFmts>
      <fonts count="2">
        <font><sz val="11"/><name val="PingFang SC"/><family val="2"/></font>
        <font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="PingFang SC"/><family val="2"/></font>
      </fonts>
      <fills count="3">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF17365D"/><bgColor indexed="64"/></patternFill></fill>
      </fills>
      <borders count="1">
        <border><left/><right/><top/><bottom/><diagonal/></border>
      </borders>
      <cellStyleXfs count="1">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
      </cellStyleXfs>
      <cellXfs count="4">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
      </cellXfs>
      <cellStyles count="1">
        <cellStyle name="Normal" xfId="0" builtinId="0"/>
      </cellStyles>
    </styleSheet>
    """
}

private struct XLSXFile {
    let name: String
    let data: Data

    init(name: String, contents: String) {
        self.name = name
        self.data = Data(contents.utf8)
    }
}

private enum ZIPArchive {
    private struct CentralDirectoryEntry {
        let file: XLSXFile
        let fileNameData: Data
        let crc32: UInt32
        let offset: UInt32
    }

    static func make(files: [XLSXFile]) throws -> Data {
        var archive = Data()
        var entries: [CentralDirectoryEntry] = []

        for file in files {
            guard let fileNameData = file.name.data(using: .utf8) else {
                throw ExcelExportError.invalidFileName
            }
            guard
                archive.count <= Int(UInt32.max),
                file.data.count <= Int(UInt32.max),
                fileNameData.count <= Int(UInt16.max)
            else {
                throw ExcelExportError.archiveTooLarge
            }

            let crc32 = CRC32.checksum(file.data)
            let offset = UInt32(archive.count)
            archive.appendLittleEndian(UInt32(0x04034B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(crc32)
            archive.appendLittleEndian(UInt32(file.data.count))
            archive.appendLittleEndian(UInt32(file.data.count))
            archive.appendLittleEndian(UInt16(fileNameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(fileNameData)
            archive.append(file.data)

            entries.append(
                CentralDirectoryEntry(
                    file: file,
                    fileNameData: fileNameData,
                    crc32: crc32,
                    offset: offset
                )
            )
        }

        guard archive.count <= Int(UInt32.max), entries.count <= Int(UInt16.max) else {
            throw ExcelExportError.archiveTooLarge
        }
        let centralDirectoryOffset = UInt32(archive.count)

        for entry in entries {
            archive.appendLittleEndian(UInt32(0x02014B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(entry.crc32)
            archive.appendLittleEndian(UInt32(entry.file.data.count))
            archive.appendLittleEndian(UInt32(entry.file.data.count))
            archive.appendLittleEndian(UInt16(entry.fileNameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt32(0))
            archive.appendLittleEndian(entry.offset)
            archive.append(entry.fileNameData)
        }

        guard archive.count <= Int(UInt32.max) else {
            throw ExcelExportError.archiveTooLarge
        }
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        archive.appendLittleEndian(UInt32(0x06054B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(centralDirectorySize)
        archive.appendLittleEndian(centralDirectoryOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var checksum = UInt32.max
        for byte in data {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(checksum & 1))
                checksum = (checksum >> 1) ^ (0xEDB88320 & mask)
            }
        }
        return checksum ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
