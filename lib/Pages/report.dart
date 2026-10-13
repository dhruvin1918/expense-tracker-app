import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:practice/services/user_firestore_helper.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  String _selectedReportType = 'Monthly';
  final List<String> _reportTypes = [
    'Daily',
    'Weekly',
    'Monthly',
    'Yearly',
    'Custom'
  ];
  String? _selectedReportFormat;
  final List<String> _reportFormats = ['PDF', 'CSV'];

  double _totalIncome = 0.0;
  double _totalExpense = 0.0;
  Map<String, double> _categoryExpenses = {};
  Map<String, double> _dateWiseSummary = {};
  bool _isLoading = false;
  bool _isExporting = false;
  bool _showAllCategoryRows = false;
  bool _showAllDateRows = false;

  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions(
      String collection,
      DateTime startDate,
      DateTime endDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection(collection)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'amount': (data['amount'] as num).toDouble(),
          'category': data['category'] as String?,
          'description': data['description'] as String?,
          'date': (data['date'] as Timestamp).toDate(),
        };
      }).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Failed to load report data. Please try again.'),
          ),
        );
      }
      return [];
    }
  }

  void _fetchReportData() async {
    setState(() {
      _isLoading = true;
      _showAllCategoryRows = false;
      _showAllDateRows = false;
    });

    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = now;

    switch (_selectedReportType) {
      case 'Daily':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(
            now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Weekly':
        startDate =
            now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(
            startDate.year, startDate.month, startDate.day);
        break;
      case 'Monthly':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'Yearly':
        startDate = DateTime(now.year, 1, 1);
        break;
      case 'Custom':
        if (_customStartDate == null ||
            _customEndDate == null) {
          setState(() => _isLoading = false);
          return;
        }

        if (_customEndDate!.isBefore(_customStartDate!)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'End date must be after start date.'),
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        startDate = _customStartDate!;
        endDate = _customEndDate!
            .add(const Duration(hours: 23, minutes: 59));
        break;
      default:
        startDate = now;
        break;
    }

    final incomeTransactions = await _fetchTransactions(
        'income', startDate, endDate);
    final expenseTransactions = await _fetchTransactions(
        'expenses', startDate, endDate);

    double totalIncome = incomeTransactions.fold(0.0,
        (runningTotal, tx) => runningTotal + tx['amount']);
    double totalExpense = expenseTransactions.fold(0.0,
        (runningTotal, tx) => runningTotal + tx['amount']);

    Map<String, double> categoryExpenses = {};
    Map<String, double> dateWiseSummary = {};

    for (var tx in expenseTransactions) {
      final category = tx['category'] ?? 'Uncategorized';
      final amount = tx['amount'];
      final date =
          DateFormat('dd-MM-yyyy').format(tx['date']);

      categoryExpenses.update(
          category, (value) => value + amount,
          ifAbsent: () => amount);
      dateWiseSummary.update(
          date, (value) => value + amount,
          ifAbsent: () => amount);
    }

    if (mounted) {
      setState(() {
        _totalIncome = totalIncome;
        _totalExpense = totalExpense;
        _categoryExpenses = categoryExpenses;
        _dateWiseSummary = dateWiseSummary;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectCustomDate(
      BuildContext context, bool isStart) async {
    DateTime initialDate = DateTime.now();
    DateTime firstDate = DateTime(2000);
    DateTime lastDate = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _customStartDate = picked;
        } else {
          _customEndDate = picked;
        }
      });
      if (_customStartDate != null &&
          _customEndDate != null) {
        _fetchReportData();
      }
    }
  }

  Future<void> _exportReport() async {
    if (_isExporting) return;

    if (_selectedReportFormat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a report format.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      if (Platform.isAndroid) {
        final androidInfo =
            await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt < 33) {
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Storage permission is required to save the file.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }
      }

      Directory directory;
      if (Platform.isAndroid) {
        final androidInfo =
            await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt < 33) {
          directory =
              Directory('/storage/emulated/0/Download');
        } else {
          directory =
              await getApplicationDocumentsDirectory();
        }
      } else {
        directory =
            await getApplicationDocumentsDirectory();
      }

      final timestamp = DateFormat('yyyyMMdd_HHmm')
          .format(DateTime.now());
      final sanitizedType =
          _selectedReportType.toLowerCase();
      final extension =
          _selectedReportFormat!.toLowerCase();
      final String filePath =
          '${directory.path}/Report_${sanitizedType}_$timestamp.$extension';

      if (_selectedReportFormat == 'PDF') {
        await _generatePdfReport(filePath);
      } else if (_selectedReportFormat == 'CSV') {
        await _generateCsvReport(filePath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved to: $filePath'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () async {
                await OpenFilex.open(filePath);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Failed to export report. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _generatePdfReport(String filePath) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final generatedAt =
        DateFormat('dd MMM yyyy, hh:mm a').format(now);

    final range = _resolveDateRange(now);
    final startDate = range.$1;
    final endDate = range.$2;
    final dateRange =
        '${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}';

    final totalNet = _totalIncome - _totalExpense;
    String money(double value) =>
        'INR ${value.toStringAsFixed(2)}';

    final sortedCategoryEntries = _categoryExpenses.entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sortedDateEntries = _dateWiseSummary.entries
        .toList()
      ..sort((a, b) {
        final da = DateFormat('dd-MM-yyyy').parse(a.key);
        final db = DateFormat('dd-MM-yyyy').parse(b.key);
        return da.compareTo(db);
      });

    pw.MemoryImage? logo;
    try {
      final bytes =
          (await rootBundle.load('assets/images/logo.png'))
              .buffer
              .asUint8List();
      logo = pw.MemoryImage(bytes);
    } catch (_) {
      logo = null;
    }

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo700,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment:
                  pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Expense Tracker',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Financial Report',
                        style: pw.TextStyle(
                          fontSize: 20,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '$_selectedReportType  |  $dateRange',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (logo != null)
                  pw.Container(
                    width: 40,
                    height: 40,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius:
                          pw.BorderRadius.circular(20),
                    ),
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Image(logo),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Generated At: $generatedAt',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Summary',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryCard(
                  title: 'Income',
                  value: money(_totalIncome),
                  accent: PdfColors.green700,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryCard(
                  title: 'Expense',
                  value: money(_totalExpense),
                  accent: PdfColors.red700,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryCard(
                  title: 'Net',
                  value: money(totalNet),
                  accent: totalNet >= 0
                      ? PdfColors.blue700
                      : PdfColors.orange700,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Expenses by Category',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            context: context,
            border: pw.TableBorder.all(
              color: PdfColors.grey400,
              width: 0.5,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.indigo50,
            ),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(6),
            headers: const [
              'Category',
              'Amount',
              '% of Expense'
            ],
            data: sortedCategoryEntries.map((entry) {
              final percent = _totalExpense == 0
                  ? 0
                  : (entry.value / _totalExpense) * 100;
              return [
                entry.key,
                money(entry.value),
                '${percent.toStringAsFixed(1)}%'
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Date-wise Expense Summary',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            context: context,
            border: pw.TableBorder.all(
              color: PdfColors.grey400,
              width: 0.5,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.indigo50,
            ),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(6),
            headers: const ['Date', 'Total Expense'],
            data: sortedDateEntries
                .map((entry) =>
                    [entry.key, money(entry.value)])
                .toList(),
          ),
        ],
      ),
    );

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
  }

  pw.Widget _summaryCard({
    required String title,
    required String value,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
            color: PdfColors.grey400, width: 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            height: 3,
            color: accent,
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateCsvReport(String filePath) async {
    final now = DateTime.now();
    final generatedAt =
        DateFormat('dd MMM yyyy, hh:mm a').format(now);
    final range = _resolveDateRange(now);
    final startDate = range.$1;
    final endDate = range.$2;

    final dateRange =
        '${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}';

    final sortedCategoryEntries = _categoryExpenses.entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sortedDateEntries = _dateWiseSummary.entries
        .toList()
      ..sort((a, b) {
        final da = DateFormat('dd-MM-yyyy').parse(a.key);
        final db = DateFormat('dd-MM-yyyy').parse(b.key);
        return da.compareTo(db);
      });

    final List<List<dynamic>> rows = [];
    rows.add(['Financial Report']);
    rows.add(['Type', _selectedReportType]);
    rows.add(['Date Range', dateRange]);
    rows.add(['Generated At', generatedAt]);
    rows.add([]);

    rows.add(['Summary']);
    rows.add(['Metric', 'Amount']);
    rows.add([
      'Total Income',
      'INR ${_totalIncome.toStringAsFixed(2)}'
    ]);
    rows.add([
      'Total Expense',
      'INR ${_totalExpense.toStringAsFixed(2)}'
    ]);
    rows.add([
      'Net Balance',
      'INR ${(_totalIncome - _totalExpense).toStringAsFixed(2)}'
    ]);
    rows.add([]);

    rows.add(['Expenses by Category']);
    rows.add(['Category', 'Amount', '% of Expense']);
    for (final entry in sortedCategoryEntries) {
      final percent = _totalExpense == 0
          ? 0
          : (entry.value / _totalExpense) * 100;
      rows.add([
        entry.key,
        'INR ${entry.value.toStringAsFixed(2)}',
        '${percent.toStringAsFixed(1)}%'
      ]);
    }

    rows.add([]);
    rows.add(['Date-wise Expense Summary']);
    rows.add(['Date', 'Total Expense']);
    for (final entry in sortedDateEntries) {
      rows.add([
        entry.key,
        'INR ${entry.value.toStringAsFixed(2)}'
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final file = File(filePath);
    await file.writeAsString(csv);
  }

  (DateTime, DateTime) _resolveDateRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (_selectedReportType) {
      case 'Daily':
        return (
          today,
          DateTime(now.year, now.month, now.day, 23, 59, 59)
        );
      case 'Weekly':
        final weekStart =
            now.subtract(Duration(days: now.weekday - 1));
        return (
          DateTime(weekStart.year, weekStart.month,
              weekStart.day),
          now
        );
      case 'Monthly':
        return (DateTime(now.year, now.month, 1), now);
      case 'Yearly':
        return (DateTime(now.year, 1, 1), now);
      case 'Custom':
        final start = _customStartDate ?? today;
        final end = _customEndDate == null
            ? now
            : _customEndDate!.add(
                const Duration(hours: 23, minutes: 59));
        return (start, end);
      default:
        return (today, now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sortedCategoryEntries = _categoryExpenses.entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedDateEntries = _dateWiseSummary.entries
        .toList()
      ..sort((a, b) {
        final da = DateFormat('dd-MM-yyyy').parse(a.key);
        final db = DateFormat('dd-MM-yyyy').parse(b.key);
        return da.compareTo(db);
      });

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Export Your Report',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionCard(
                context: context,
                title: 'Filters',
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('Select Report Type',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedReportType,
                      style: TextStyle(
                          color: colorScheme.onSurface),
                      dropdownColor: colorScheme.surface,
                      items: _reportTypes
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedReportType = value!;
                        });
                        if (_selectedReportType !=
                            'Custom') {
                          _fetchReportData();
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.outline,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.outline,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8),
                      ),
                    ),
                    if (_selectedReportType ==
                        'Custom') ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _selectCustomDate(
                                      context, true),
                              icon: const Icon(
                                  Icons.calendar_today),
                              label: Text(
                                  _customStartDate == null
                                      ? 'Start Date'
                                      : DateFormat.yMd().format(
                                          _customStartDate!),
                                  overflow: TextOverflow
                                      .ellipsis),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _selectCustomDate(
                                      context, false),
                              icon: const Icon(Icons.event),
                              label: Text(
                                  _customEndDate == null
                                      ? 'End Date'
                                      : DateFormat.yMd()
                                          .format(
                                              _customEndDate!),
                                  overflow: TextOverflow
                                      .ellipsis),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('Select Format',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedReportFormat,
                      style: TextStyle(
                          color: colorScheme.onSurface),
                      dropdownColor: colorScheme.surface,
                      items: _reportFormats
                          .map((format) => DropdownMenuItem(
                                value: format,
                                child: Text(format),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedReportFormat = value;
                        });
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.outline,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.outline,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Padding(
                  padding:
                      EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                      child: CircularProgressIndicator()),
                )
              else
                _buildSectionCard(
                  context: context,
                  title:
                      'Report Summary ($_selectedReportType)',
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns =
                                constraints.maxWidth >= 560
                                    ? 3
                                    : constraints
                                                .maxWidth >=
                                            360
                                        ? 2
                                        : 1;
                            final tileWidth = (constraints
                                        .maxWidth -
                                    ((columns - 1) * 8)) /
                                columns;

                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                SizedBox(
                                  width: tileWidth,
                                  child: _metricTile(
                                    context: context,
                                    title: 'Income',
                                    value:
                                        '₹${_totalIncome.toStringAsFixed(2)}',
                                    color: Colors
                                        .green.shade700,
                                    icon: Icons.trending_up,
                                  ),
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _metricTile(
                                    context: context,
                                    title: 'Expense',
                                    value:
                                        '₹${_totalExpense.toStringAsFixed(2)}',
                                    color:
                                        colorScheme.error,
                                    icon:
                                        Icons.trending_down,
                                  ),
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _metricTile(
                                    context: context,
                                    title: 'Net Balance',
                                    value:
                                        '₹${(_totalIncome - _totalExpense).toStringAsFixed(2)}',
                                    color: (_totalIncome -
                                                _totalExpense) >=
                                            0
                                        ? colorScheme
                                            .primary
                                        : colorScheme.error,
                                    icon: Icons
                                        .account_balance_wallet,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        if (_totalIncome == 0 &&
                            _totalExpense == 0)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 12),
                            child: Text(
                              'No transactions found for this period.',
                              style: TextStyle(
                                  color:
                                      colorScheme.outline),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              _buildSectionCard(
                context: context,
                title: 'Expenses by Category',
                child: sortedCategoryEntries.isEmpty
                    ? Padding(
                        padding:
                            const EdgeInsets.only(top: 6),
                        child: Text(
                          'No category expenses for this period.',
                          style: TextStyle(
                            color: colorScheme.outline,
                          ),
                        ),
                      )
                    : _buildCollapsibleAmountList(
                        context: context,
                        entries: sortedCategoryEntries,
                        showAll: _showAllCategoryRows,
                        onToggle: () {
                          setState(() {
                            _showAllCategoryRows =
                                !_showAllCategoryRows;
                          });
                        },
                      ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                context: context,
                title: 'Date-wise Summary',
                child: sortedDateEntries.isEmpty
                    ? Padding(
                        padding:
                            const EdgeInsets.only(top: 6),
                        child: Text(
                          'No date-wise expenses for this period.',
                          style: TextStyle(
                            color: colorScheme.outline,
                          ),
                        ),
                      )
                    : _buildCollapsibleAmountList(
                        context: context,
                        entries: sortedDateEntries,
                        showAll: _showAllDateRows,
                        onToggle: () {
                          setState(() {
                            _showAllDateRows =
                                !_showAllDateRows;
                          });
                        },
                      ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed:
                    _isExporting ? null : _exportReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                      vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isExporting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(
                            colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Icon(
                              Icons.file_download_outlined),
                          const SizedBox(width: 8),
                          Text(
                            'Export',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color:
                                      colorScheme.onPrimary,
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(
                        fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsibleAmountList({
    required BuildContext context,
    required List<MapEntry<String, double>> entries,
    required bool showAll,
    required VoidCallback onToggle,
  }) {
    const previewCount = 5;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleEntries = showAll
        ? entries
        : entries.take(previewCount).toList();
    final hiddenCount =
        entries.length - visibleEntries.length;

    return Column(
      children: [
        ...visibleEntries.map((entry) => Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(entry.key,
                        style: theme.textTheme.bodyMedium),
                  ),
                  Text(
                    '₹${entry.value.toStringAsFixed(2)}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(
                            fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )),
        if (entries.length > previewCount)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onToggle,
              icon: Icon(showAll
                  ? Icons.expand_less
                  : Icons.expand_more),
              label: Text(showAll
                  ? 'Show less'
                  : 'Show $hiddenCount more'),
            ),
          ),
      ],
    );
  }

  Widget _metricTile({
    required BuildContext context,
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 16, color: colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
