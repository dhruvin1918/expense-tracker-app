import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:practice/Pages/add_expense.dart';
import 'package:practice/Pages/addincome.dart';
import 'package:practice/Pages/setbudget.dart';
import 'package:practice/Pages/wallet_detail_page.dart';
import 'package:practice/Toggle/switchbutton.dart';
import 'package:practice/services/user_firestore_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyHomePage extends StatefulWidget {
  final String userName;

  const MyHomePage({super.key, required this.userName});

  @override
  State<MyHomePage> createState() => _HomePageState();
}

class _HomePageState extends State<MyHomePage> {
  double _todayTotalExpense = 0.0;
  double _todayTotalIncome = 0.0;
  double _totalBalance = 0.0;

  double _cashBalance = 0.0;
  double _bankBalance = 0.0;
  double _creditBalance = 0.0;
  double _monthlyTotalExpense = 0.0;
  Map<String, double> _categoryExpenses = {};
  int _lastBudgetAlertLevel = 0;
  final Map<String, int> _lastCategoryAlertLevel = {};

  bool _dataLoadedOnce = false;
  bool _isInitialLoading = true;

  String get displayName {
    if (widget.userName.isNotEmpty) {
      return widget.userName;
    }
    return 'User';
  }

  Future<void> _refreshData(User user,
      {bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() => _isInitialLoading = true);
    }

    try {
      final results = await Future.wait([
        _fetchTodayExpenses(user),
        _fetchTodayIncome(user),
        _calculateTotalBalance(user),
        _fetchWalletBalances(user),
        _fetchMonthlyExpenses(user),
        _fetchMonthlyExpensesByCategory(user),
      ]);

      final wallets = results[3] as Map<String, double>;
      final categoryExpenses =
          results[5] as Map<String, double>;

      if (mounted) {
        setState(() {
          _todayTotalExpense = results[0] as double;
          _todayTotalIncome = results[1] as double;
          _totalBalance = results[2] as double;
          _cashBalance = wallets['cash'] ?? 0;
          _bankBalance = wallets['bank'] ?? 0;
          _creditBalance = wallets['credit'] ?? 0;
          _monthlyTotalExpense = results[4] as double;
          _categoryExpenses = categoryExpenses;
        });
      }

      await _checkBudgetAlert(user);
    } catch (e) {
      debugPrint('Dashboard refresh error: $e');
    } finally {
      if (showLoader && mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  Future<double> _fetchTodayExpenses(User user) async {
    final now = DateTime.now();
    final todayStart =
        DateTime(now.year, now.month, now.day);
    final todayEnd =
        DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: todayStart)
          .where('date', isLessThanOrEqualTo: todayEnd)
          .get();

      double total = 0.0;
      for (var doc in querySnapshot.docs) {
        total += (doc['amount'] as num).toDouble();
      }

      return total;
    } catch (e) {
      debugPrint('Expense fetch error: $e');
      return 0;
    }
  }

  Future<double> _fetchTodayIncome(User user) async {
    final now = DateTime.now();
    final todayStart =
        DateTime(now.year, now.month, now.day);
    final todayEnd =
        DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('income')
          .where('date', isGreaterThanOrEqualTo: todayStart)
          .where('date', isLessThanOrEqualTo: todayEnd)
          .get();

      double total = 0.0;
      for (var doc in querySnapshot.docs) {
        total += (doc['amount'] as num).toDouble();
      }

      return total;
    } catch (e) {
      debugPrint('Income fetch error: $e');
      return 0;
    }
  }

  Future<double> _calculateTotalBalance(User user) async {
    // TODO: Replace with summary document read for scalability.
    // Suggested path: users/{uid}/summary/balance.
    try {
      final incomeSnapshot = await FirebaseFirestore
          .instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('income')
          .get();

      final expenseSnapshot = await FirebaseFirestore
          .instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('expenses')
          .get();

      double totalIncome = 0.0;
      double totalExpense = 0.0;

      for (var doc in incomeSnapshot.docs) {
        totalIncome += (doc['amount'] as num).toDouble();
      }

      for (var doc in expenseSnapshot.docs) {
        totalExpense += (doc['amount'] as num).toDouble();
      }

      return totalIncome - totalExpense;
    } catch (e) {
      debugPrint('Balance calc error: $e');
      return 0;
    }
  }

  Future<Map<String, double>> _fetchWalletBalances(
      User user) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('wallets')
          .get();

      final wallets = <String, double>{};

      for (var doc in snapshot.docs) {
        wallets[doc.id] =
            (doc['balance'] as num?)?.toDouble() ?? 0;
      }

      return wallets;
    } catch (e) {
      debugPrint('Wallet fetch error: $e');
      return <String, double>{};
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Future<double> _fetchMonthlyExpenses(User user) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: monthStart)
          .get();

      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += (doc['amount'] as num?)?.toDouble() ?? 0.0;
      }
      return total;
    } catch (e) {
      debugPrint('Monthly expense fetch error: $e');
      return 0.0;
    }
  }

  Future<Map<String, double>>
      _fetchMonthlyExpensesByCategory(User user) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: monthStart)
          .get();

      final Map<String, double> categoryExpenses = {};
      for (var doc in snapshot.docs) {
        final category =
            doc['category'] as String? ?? 'Uncategorized';
        final amount =
            (doc['amount'] as num?)?.toDouble() ?? 0.0;
        categoryExpenses[category] =
            (categoryExpenses[category] ?? 0) + amount;
      }
      return categoryExpenses;
    } catch (e) {
      debugPrint('Category expense fetch error: $e');
      return {};
    }
  }

  Future<void> _checkBudgetAlert(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final alertEnabled =
        prefs.getBool('budgetAlertEnabled') ?? false;
    if (!alertEnabled) {
      _lastBudgetAlertLevel = 0;
      _lastCategoryAlertLevel.clear();
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userDocumentIdFor(user))
        .get();

    final monthlyBudget =
        _toDouble(userDoc.data()?['monthlyBudget']);
    final categoryBudgets =
        (userDoc.data()?['categoryBudgets']
                as Map<String, dynamic>?) ??
            {};

    if (monthlyBudget > 0) {
      final pct =
          (_monthlyTotalExpense / monthlyBudget) * 100;
      int level = 0;
      if (_monthlyTotalExpense >= monthlyBudget) {
        level = 100;
      } else if (pct >= 80) {
        level = 80;
      }

      if (level != 0 &&
          level != _lastBudgetAlertLevel &&
          mounted) {
        _lastBudgetAlertLevel = level;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              level == 100
                  ? '⚠️ Monthly budget exceeded.'
                  : '📊 Monthly budget reached ${pct.toStringAsFixed(0)}%.',
            ),
            backgroundColor: level == 100
                ? Colors.red.shade600
                : Colors.orange.shade600,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }

    if (categoryBudgets.isEmpty) return;
    final spentByCategory =
        await _fetchMonthlyExpensesByCategory(user);
    for (final entry in categoryBudgets.entries) {
      final category = entry.key;
      final limit = _toDouble(entry.value);
      if (limit <= 0) continue;

      final spent = spentByCategory[category] ?? 0.0;
      int level = 0;
      if (spent >= limit) {
        level = 100;
      } else if (spent >= limit * 0.8) {
        level = 80;
      }

      final prev = _lastCategoryAlertLevel[category] ?? 0;
      if (level != 0 && level != prev && mounted) {
        _lastCategoryAlertLevel[category] = level;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              level == 100
                  ? '⚠️ $category budget exceeded.'
                  : '📊 $category budget reached ${((spent / limit) * 100).toStringAsFixed(0)}%.',
            ),
            backgroundColor: level == 100
                ? Colors.red.shade600
                : Colors.orange.shade600,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Please sign in to access your expense data.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // run Firestore only AFTER auth, only once
    if (!_dataLoadedOnce) {
      _dataLoadedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshData(user, showLoader: true);
      });
    }

    if (_isInitialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('categories')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final List<String> userCategories = snapshot.hasData
            ? snapshot.data!.docs
                .map((doc) => doc['name'] as String)
                .toList()
            : [];

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: RefreshIndicator(
            onRefresh: () => _refreshData(user),
            child: SingleChildScrollView(
              physics:
                  const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: theme.brightness ==
                                  Brightness.dark
                              ? [
                                  colorScheme
                                      .primaryContainer,
                                  colorScheme
                                      .surfaceContainerHighest,
                                ]
                              : [
                                  colorScheme.primary,
                                  colorScheme.secondary,
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius:
                            BorderRadius.circular(22),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back',
                              style: theme
                                  .textTheme.titleMedium
                                  ?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$displayName 👋',
                              style: theme
                                  .textTheme.headlineSmall
                                  ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Today net: ₹${(_todayTotalIncome - _todayTotalExpense).toStringAsFixed(2)}',
                              style: theme
                                  .textTheme.bodyLarge
                                  ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Balance',
                              style: theme
                                  .textTheme.titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₹${_totalBalance.toStringAsFixed(2)}',
                              style: theme
                                  .textTheme.headlineSmall
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _totalBalance >= 0
                                    ? Colors.green
                                    : colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .spaceBetween,
                              children: [
                                WalletItem(
                                  walletId: 'cash',
                                  walletName: 'Cash',
                                  amount: _cashBalance,
                                  color:
                                      colorScheme.primary,
                                  onRefresh: () =>
                                      _refreshData(user),
                                ),
                                WalletItem(
                                  walletId: 'bank',
                                  walletName: 'Bank',
                                  amount: _bankBalance,
                                  color:
                                      colorScheme.secondary,
                                  onRefresh: () =>
                                      _refreshData(user),
                                ),
                                WalletItem(
                                  walletId: 'credit',
                                  walletName: 'Credit',
                                  amount: _creditBalance,
                                  color:
                                      colorScheme.tertiary,
                                  onRefresh: () =>
                                      _refreshData(user),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Quick Actions',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  colorScheme.primary,
                              foregroundColor:
                                  colorScheme.onPrimary,
                              padding: const EdgeInsets
                                  .symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12),
                              ),
                              elevation: 1,
                            ),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const Addexpense()),
                              );
                              _refreshData(user);
                            },
                            icon: const Icon(Icons
                                .remove_circle_outline),
                            label:
                                const Text('Add Expense'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  colorScheme.secondary,
                              foregroundColor:
                                  colorScheme.onSecondary,
                              padding: const EdgeInsets
                                  .symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12),
                              ),
                              elevation: 1,
                            ),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const Addincome()),
                              );
                              _refreshData(user);
                            },
                            icon: const Icon(
                                Icons.add_circle_outline),
                            label: const Text('Add Income'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text("Today's Summary",
                                style: theme
                                    .textTheme.titleMedium
                                    ?.copyWith(
                                  fontWeight:
                                      FontWeight.w700,
                                )),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  color:
                                      Colors.green.shade600,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Income: ₹${_todayTotalIncome.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: Colors
                                        .green.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.arrow_downward,
                                  color: colorScheme.error,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Expense: ₹${_todayTotalExpense.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color:
                                        colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            16, 14, 16, 16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Budget Alert',
                                    style: theme.textTheme
                                        .titleMedium
                                        ?.copyWith(
                                      fontWeight:
                                          FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Switchbutton(),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton
                                    .styleFrom(
                                  backgroundColor:
                                      colorScheme.primary,
                                  foregroundColor:
                                      colorScheme.onPrimary,
                                  padding: const EdgeInsets
                                      .symmetric(
                                      vertical: 14),
                                  shape:
                                      RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius
                                            .circular(12),
                                  ),
                                  elevation: 1,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SetBudgetPage(
                                        categories:
                                            userCategories,
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment
                                          .center,
                                  children: [
                                    const Icon(Icons.tune),
                                    const SizedBox(
                                        width: 8),
                                    Text(
                                      'Set Budget',
                                      style: theme.textTheme
                                          .labelLarge
                                          ?.copyWith(
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(userDocumentIdFor(user))
                        .snapshots(),
                    builder: (context, budgetSnapshot) {
                      if (!budgetSnapshot.hasData) {
                        return const SizedBox();
                      }

                      final monthlyBudget = _toDouble(
                          budgetSnapshot
                              .data?['monthlyBudget']);
                      final categoryBudgets =
                          (budgetSnapshot.data?[
                                      'categoryBudgets']
                                  as Map<String,
                                      dynamic>?) ??
                              {};

                      if (monthlyBudget <= 0 &&
                          categoryBudgets.isEmpty) {
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16),
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  Icon(
                                      Icons
                                          .savings_outlined,
                                      size: 40,
                                      color: colorScheme
                                          .outline),
                                  const SizedBox(
                                      height: 12),
                                  Text(
                                    'No budget set yet',
                                    style: theme.textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight:
                                                FontWeight
                                                    .w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tap "Set Budget" above to start\ntracking your spending limits.',
                                    textAlign:
                                        TextAlign.center,
                                    style: theme
                                        .textTheme.bodySmall
                                        ?.copyWith(
                                            color: colorScheme
                                                .outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                        Icons
                                            .pie_chart_outline_rounded,
                                        color: colorScheme
                                            .primary,
                                        size: 20),
                                    const SizedBox(
                                        width: 8),
                                    Text(
                                      'Budget Status',
                                      style: theme.textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight:
                                                  FontWeight
                                                      .w700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (monthlyBudget > 0) ...[
                                  _BudgetRow(
                                    label: 'Monthly Total',
                                    spent:
                                        _monthlyTotalExpense,
                                    limit: monthlyBudget,
                                    colorScheme:
                                        colorScheme,
                                    theme: theme,
                                    isMonthly: true,
                                  ),
                                  if (categoryBudgets
                                      .isNotEmpty)
                                    const Divider(
                                        height: 24),
                                ],
                                if (categoryBudgets
                                    .isNotEmpty)
                                  Builder(
                                    builder: (context) {
                                      final spent =
                                          _categoryExpenses;
                                      final entries =
                                          categoryBudgets
                                              .entries
                                              .where((e) =>
                                                  _toDouble(
                                                      e.value) >
                                                  0)
                                              .toList();

                                      if (entries.isEmpty) {
                                        return const SizedBox();
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                          Text(
                                            'By Category',
                                            style: theme
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                              fontWeight:
                                                  FontWeight
                                                      .w600,
                                              color: colorScheme
                                                  .outline,
                                            ),
                                          ),
                                          const SizedBox(
                                              height: 12),
                                          ...entries
                                              .map((entry) {
                                            final category =
                                                entry.key;
                                            final limit =
                                                _toDouble(entry
                                                    .value);
                                            final categorySpent =
                                                spent[category] ??
                                                    0;

                                            return Padding(
                                              padding:
                                                  const EdgeInsets
                                                      .only(
                                                      bottom:
                                                          14),
                                              child:
                                                  _BudgetRow(
                                                label:
                                                    category,
                                                spent:
                                                    categorySpent,
                                                limit:
                                                    limit,
                                                colorScheme:
                                                    colorScheme,
                                                theme:
                                                    theme,
                                              ),
                                            );
                                          }),
                                        ],
                                      );
                                    },
                                  ),
                                if (monthlyBudget > 0) ...[
                                  const Divider(height: 20),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .spaceBetween,
                                    children: [
                                      _SummaryChip(
                                        label: 'Spent',
                                        value:
                                            '₹${_monthlyTotalExpense.toStringAsFixed(0)}',
                                        color: colorScheme
                                            .error,
                                        theme: theme,
                                      ),
                                      _SummaryChip(
                                        label: 'Remaining',
                                        value:
                                            '₹${(monthlyBudget - _monthlyTotalExpense).clamp(0, monthlyBudget).toStringAsFixed(0)}',
                                        color: Colors
                                            .green.shade600,
                                        theme: theme,
                                      ),
                                      _SummaryChip(
                                        label: 'Budget',
                                        value:
                                            '₹${monthlyBudget.toStringAsFixed(0)}',
                                        color: colorScheme
                                            .primary,
                                        theme: theme,
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_totalBalance == 0 &&
                      _todayTotalIncome == 0 &&
                      _todayTotalExpense == 0)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No transactions yet. Add your first income or expense!',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class WalletItem extends StatelessWidget {
  const WalletItem({
    super.key,
    required this.walletId,
    required this.walletName,
    required this.amount,
    required this.color,
    required this.onRefresh,
  });

  final String walletId;
  final String walletName;
  final double amount;
  final Color color;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    IconData icon;

    switch (walletId.toLowerCase()) {
      case 'cash':
        icon = Icons.money;
        break;
      case 'bank':
        icon = Icons.account_balance;
        break;
      case 'credit':
        icon = Icons.credit_card;
        break;
      default:
        icon = Icons.wallet;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WalletDetailPage(
              walletId: walletId,
              walletName: walletName,
            ),
          ),
        );

        await onRefresh();
      },
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            walletName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.label,
    required this.spent,
    required this.limit,
    required this.colorScheme,
    required this.theme,
    this.isMonthly = false,
  });

  final String label;
  final double spent;
  final double limit;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final bool isMonthly;

  @override
  Widget build(BuildContext context) {
    final progress = (spent / limit).clamp(0.0, 1.0);
    final percent = (progress * 100);
    final isOver = spent >= limit;
    final isWarning = percent >= 80 && !isOver;
    final remaining = (limit - spent).clamp(0.0, limit);

    Color barColor = colorScheme.primary;
    if (isOver) barColor = colorScheme.error;
    if (isWarning) barColor = Colors.orange.shade600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (isOver)
                  Icon(Icons.warning_rounded,
                      size: 15, color: colorScheme.error),
                if (isWarning)
                  Icon(Icons.info_outline_rounded,
                      size: 15,
                      color: Colors.orange.shade600),
                if (isOver || isWarning)
                  const SizedBox(width: 4),
                Text(
                  label,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isMonthly
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color:
                        isOver ? colorScheme.error : null,
                  ),
                ),
              ],
            ),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: isMonthly ? 10 : 7,
            backgroundColor:
                colorScheme.surfaceContainerHighest,
            color: barColor,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '₹${spent.toStringAsFixed(0)} spent',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.outline),
            ),
            Text(
              isOver
                  ? '₹${(spent - limit).toStringAsFixed(0)} over!'
                  : '₹${remaining.toStringAsFixed(0)} left',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isOver
                    ? colorScheme.error
                    : Colors.green.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
  });

  final String label;
  final String value;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
