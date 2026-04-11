import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';

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

  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions(
      String collection, DateTime startDate, DateTime endDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
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
          SnackBar(content: Text('Failed to fetch data from $collection: $e')),
        );
      }
      return [];
    }
  }

  void _fetchReportData() async {
    setState(() {
      _isLoading = true;
    });

    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = now;

    switch (_selectedReportType) {
      case 'Daily':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Weekly':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        break;
      case 'Monthly':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'Yearly':
        startDate = DateTime(now.year, 1, 1);
        break;
      case 'Custom':
        if (_customStartDate == null || _customEndDate == null) {
          setState(() => _isLoading = false);
          return;
        }
        startDate = _customStartDate!;
        endDate = _customEndDate!.add(const Duration(hours: 23, minutes: 59));
        break;
      default:
        startDate = now;
        break;
    }

    final incomeTransactions =
        await _fetchTransactions('income', startDate, endDate);
    final expenseTransactions =
        await _fetchTransactions('expenses', startDate, endDate);

    double totalIncome =
        incomeTransactions.fold(0.0, (sum, tx) => sum + tx['amount']);
    double totalExpense =
        expenseTransactions.fold(0.0, (sum, tx) => sum + tx['amount']);

    Map<String, double> categoryExpenses = {};
    Map<String, double> dateWiseSummary = {};

    for (var tx in expenseTransactions) {
      final category = tx['category'] ?? 'Uncategorized';
      final amount = tx['amount'];
      final date = DateFormat('dd-MM-yyyy').format(tx['date']);

      categoryExpenses.update(category, (value) => value + amount,
          ifAbsent: () => amount);
      dateWiseSummary.update(date, (value) => value + amount,
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

  Future<void> _selectCustomDate(BuildContext context, bool isStart) async {
    DateTime initialDate = DateTime.now();
    DateTime firstDate = DateTime(2000);
    DateTime lastDate = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _customStartDate = picked;
        } else {
          _customEndDate = picked;
        }
      });
      if (_customStartDate != null && _customEndDate != null) {
        _fetchReportData();
      }
    }
  }

  Future<void> _exportReport() async {
    if (_selectedReportFormat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a report format.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    var status = await Permission.storage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Storage permission is required to save the file.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      Directory directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final String filePath =
          '${directory.path}/FinancialReport.${_selectedReportFormat!.toLowerCase()}';

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
          SnackBar(
            content: Text('Failed to export report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generatePdfReport(String filePath) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Financial Report ($_selectedReportType)',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Summary',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Text('Total Income: ₹${_totalIncome.toStringAsFixed(2)}'),
              pw.Text('Total Expense: ₹${_totalExpense.toStringAsFixed(2)}'),
              pw.Text(
                  'Net Balance: ₹${(_totalIncome - _totalExpense).toStringAsFixed(2)}'),
              pw.SizedBox(height: 20),
              pw.Text('Expenses by Category',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              ..._categoryExpenses.entries.map((entry) =>
                  pw.Text('${entry.key}: ₹${entry.value.toStringAsFixed(2)}')),
              pw.SizedBox(height: 20),
              pw.Text('Date-wise Summary',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              ..._dateWiseSummary.entries.map((entry) =>
                  pw.Text('${entry.key}: ₹${entry.value.toStringAsFixed(2)}')),
            ],
          );
        },
      ),
    );

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
  }

  Future<void> _generateCsvReport(String filePath) async {
    List<List<dynamic>> rows = [];

    rows.add(['Financial Report (${_selectedReportType})']);
    rows.add(['Summary']);
    rows.add(['Total Income', 'Total Expense', 'Net Balance']);
    rows.add([
      '₹${_totalIncome.toStringAsFixed(2)}',
      '₹${_totalExpense.toStringAsFixed(2)}',
      '₹${(_totalIncome - _totalExpense).toStringAsFixed(2)}'
    ]);
    rows.add([]);

    rows.add(['Expenses by Category']);
    rows.add(['Category', 'Amount']);
    _categoryExpenses.forEach((category, amount) {
      rows.add([category, '₹${amount.toStringAsFixed(2)}']);
    });

    rows.add([]);
    rows.add(['Date-wise Summary']);
    rows.add(['Date', 'Total Expense']);
    _dateWiseSummary.forEach((date, amount) {
      rows.add([date, '₹${amount.toStringAsFixed(2)}']);
    });

    String csv = const ListToCsvConverter().convert(rows);
    final file = File(filePath);
    await file.writeAsString(csv);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Select Report Type',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedReportType,
                style: TextStyle(color: colorScheme.onSurface),
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
                  if (_selectedReportType != 'Custom') {
                    _fetchReportData();
                  }
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              if (_selectedReportType == 'Custom') ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _selectCustomDate(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                        child: Text(_customStartDate == null
                            ? 'Select Start Date'
                            : 'Start: ${_customStartDate!.toLocal().toString().split(' ')[0]}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _selectCustomDate(context, false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                        child: Text(_customEndDate == null
                            ? 'Select End Date'
                            : 'End: ${_customEndDate!.toLocal().toString().split(' ')[0]}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 20),
              Text('Select Format',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedReportFormat,
                style: TextStyle(color: colorScheme.onSurface),
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
                  fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 30),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Card(
                  color: colorScheme.surface,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Report Summary ($_selectedReportType)',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Divider(height: 20),
                        Text(
                          'Total Income: ₹${_totalIncome.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Total Expense: ₹${_totalExpense.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Net Balance: ₹${(_totalIncome - _totalExpense).toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary),
                        ),
                        const SizedBox(height: 20),
                        Text('Expenses by Category:',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        ..._categoryExpenses.entries.map((entry) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                '${entry.key}: ₹${entry.value.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            )),
                        const SizedBox(height: 20),
                        Text('Date-wise Summary:',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        ..._dateWiseSummary.entries.map((entry) => Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 8),
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    colorScheme.surfaceVariant.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${entry.key}: ₹${entry.value.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _exportReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Export',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
