import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';

/// Parsed tabular record extracted from CSV, XLSX, or TXT.
class TabularRow {
  final int rowIndex;
  final String? roll;
  final String? name;
  final String? attendance;
  final String? date;
  final Map<String, dynamic> rawColumns;

  const TabularRow({
    required this.rowIndex,
    this.roll,
    this.name,
    this.attendance,
    this.date,
    this.rawColumns = const {},
  });
}

/// Result of deterministic tabular parsing.
class TabularParseResult {
  final String sourceType;
  final int totalRows;
  final List<TabularRow> rows;
  final List<String> detectedHeaders;

  const TabularParseResult({
    required this.sourceType,
    required this.totalRows,
    required this.rows,
    required this.detectedHeaders,
  });
}

/// Deterministic tabular parser for CSV, XLSX, and TXT files.
class TabularParser {
  const TabularParser._();

  /// Parses CSV string or bytes.
  static Result<TabularParseResult, Failure> parseCsv(String csvContent) {
    try {
      final normalizedCsv = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final converter = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
        allowInvalid: true,
      );
      final rawRows = converter.convert(normalizedCsv);
      if (rawRows.isEmpty) {
        return const Success(TabularParseResult(
          sourceType: 'csv',
          totalRows: 0,
          rows: [],
          detectedHeaders: [],
        ));
      }

      return _processMatrix(rawRows, 'csv');
    } catch (e) {
      return Err(ImportFailure('Failed to parse CSV: $e'));
    }
  }

  /// Parses Excel (.xlsx) file bytes.
  static Result<TabularParseResult, Failure> parseXlsx(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        return const Success(TabularParseResult(
          sourceType: 'xlsx',
          totalRows: 0,
          rows: [],
          detectedHeaders: [],
        ));
      }

      // Pick the first non-empty sheet
      Sheet? targetSheet;
      for (final table in excel.tables.values) {
        if (table.rows.isNotEmpty) {
          targetSheet = table;
          break;
        }
      }

      if (targetSheet == null || targetSheet.rows.isEmpty) {
        return const Success(TabularParseResult(
          sourceType: 'xlsx',
          totalRows: 0,
          rows: [],
          detectedHeaders: [],
        ));
      }

      final rawRows = <List<dynamic>>[];
      for (final row in targetSheet.rows) {
        final rowValues = row.map((cell) => cell?.value?.toString() ?? '').toList();
        rawRows.add(rowValues);
      }

      return _processMatrix(rawRows, 'xlsx');
    } catch (e) {
      return Err(ImportFailure('Failed to parse XLSX: $e'));
    }
  }

  /// Processes generic 2D table into TabularRows with automatic column identification.
  static Result<TabularParseResult, Failure> _processMatrix(List<List<dynamic>> matrix, String sourceType) {
    if (matrix.isEmpty) {
      return Success(TabularParseResult(
        sourceType: sourceType,
        totalRows: 0,
        rows: [],
        detectedHeaders: [],
      ));
    }

    // 1. Detect header row index
    int headerRowIdx = 0;
    int rollColIdx = -1;
    int nameColIdx = -1;
    int statusColIdx = -1;
    int dateColIdx = -1;

    for (int r = 0; r < matrix.length && r < 5; r++) {
      final row = matrix[r].map((e) => e?.toString().trim().toLowerCase() ?? '').toList();
      for (int c = 0; c < row.length; c++) {
        final val = row[c];
        if (rollColIdx == -1 && _isRollHeader(val)) rollColIdx = c;
        if (nameColIdx == -1 && _isNameHeader(val)) nameColIdx = c;
        if (statusColIdx == -1 && _isStatusHeader(val)) statusColIdx = c;
        if (dateColIdx == -1 && _isDateHeader(val)) dateColIdx = c;
      }

      if (rollColIdx != -1 || nameColIdx != -1) {
        headerRowIdx = r;
        break;
      }
    }

    final bool hasExplicitHeader = (rollColIdx != -1 || nameColIdx != -1);
    final List<String> headerRow;
    final int startDataRow;

    if (hasExplicitHeader) {
      headerRow = matrix[headerRowIdx].map((e) => e?.toString().trim() ?? '').toList();
      startDataRow = headerRowIdx + 1;
    } else {
      headerRow = [];
      startDataRow = 0;
      // Positional guessing on first data row
      if (matrix.isNotEmpty) {
        final firstRow = matrix[0];
        if (firstRow.isNotEmpty) {
          final val0 = firstRow[0]?.toString().trim() ?? '';
          if (RegExp(r'\d').hasMatch(val0)) {
            rollColIdx = 0;
            if (firstRow.length > 1) nameColIdx = 1;
            if (firstRow.length > 2) statusColIdx = 2;
          } else {
            nameColIdx = 0;
            if (firstRow.length > 1) {
              final val1 = firstRow[1]?.toString().trim() ?? '';
              if (RegExp(r'\d').hasMatch(val1)) {
                rollColIdx = 1;
                if (firstRow.length > 2) statusColIdx = 2;
              } else {
                statusColIdx = 1;
              }
            }
          }
        }
      }
    }

    final parsedRows = <TabularRow>[];
    int logicalRowIndex = 1;

    for (int r = startDataRow; r < matrix.length; r++) {
      final row = matrix[r];
      // Skip blank rows
      if (row.every((cell) => cell == null || cell.toString().trim().isEmpty)) {
        continue;
      }

      final roll = rollColIdx >= 0 && rollColIdx < row.length ? row[rollColIdx]?.toString().trim() : null;
      final name = nameColIdx >= 0 && nameColIdx < row.length ? row[nameColIdx]?.toString().trim() : null;
      final status = statusColIdx >= 0 && statusColIdx < row.length ? row[statusColIdx]?.toString().trim() : null;
      final date = dateColIdx >= 0 && dateColIdx < row.length ? row[dateColIdx]?.toString().trim() : null;

      final rawMap = <String, dynamic>{};
      for (int c = 0; c < row.length; c++) {
        final colName = c < headerRow.length && headerRow[c].isNotEmpty ? headerRow[c] : 'col_$c';
        rawMap[colName] = row[c];
      }

      parsedRows.add(TabularRow(
        rowIndex: logicalRowIndex++,
        roll: roll,
        name: name,
        attendance: status,
        date: date,
        rawColumns: rawMap,
      ));
    }

    return Success(TabularParseResult(
      sourceType: sourceType,
      totalRows: parsedRows.length,
      rows: parsedRows,
      detectedHeaders: headerRow,
    ));
  }

  static bool _isRollHeader(String val) {
    return val.contains('roll') || val.contains('reg') || val == 'id' || val == 'student_id' || val == 'urn';
  }

  static bool _isNameHeader(String val) {
    return val.contains('name') || val == 'student' || val == 'student_name' || val == 'full_name';
  }

  static bool _isStatusHeader(String val) {
    return val.contains('status') || val.contains('attend') || val == 'mark' || val == 'presence' || val == 'p/a';
  }

  static bool _isDateHeader(String val) {
    return val.contains('date') || val == 'session';
  }
}
