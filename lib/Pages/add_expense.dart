import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:practice/services/user_firestore_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Addexpense extends StatefulWidget {
  const Addexpense({super.key});

  @override
  State<Addexpense> createState() => _AddexpenseState();
}

class _AddexpenseState extends State<Addexpense> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategory;
  String _selectedWallet = 'cash';
  String? _preferredCategory;
  DateTime _selectedDate = DateTime.now();
  List<String> _categories = [];
  bool _isLoading = true;
  bool _isSaving = false;
  final List<int> _quickAmounts = [
    100,
    200,
    500,
    1000,
    2000
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDefaults();
      _fetchCategories();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _fetchCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('categories')
          .orderBy('timestamp')
          .get();

      if (mounted) {
        final names = snapshot.docs
            .map((d) => d['name'] as String)
            .toList();
        setState(() {
          _categories = names;
          if (_preferredCategory != null &&
              names.contains(_preferredCategory)) {
            _selectedCategory = _preferredCategory;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Category fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedWallet =
          prefs.getString('default_expense_wallet') ??
              'cash';
      _preferredCategory =
          prefs.getString('default_expense_category');
    });
  }

  Future<void> _saveDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'default_expense_wallet', _selectedWallet);
    if (_selectedCategory != null) {
      await prefs.setString(
          'default_expense_category', _selectedCategory!);
    }
  }

  Future<void> _undoExpense({
    required String userId,
    required double amount,
    required String wallet,
    required String expenseId,
    required String transactionId,
  }) async {
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId);
    final walletRef =
        userRef.collection('wallets').doc(wallet);
    final expenseRef =
        userRef.collection('expenses').doc(expenseId);
    final transactionRef = userRef
        .collection('transactions')
        .doc(transactionId);

    await FirebaseFirestore.instance
        .runTransaction((transaction) async {
      final walletSnap = await transaction.get(walletRef);
      final currentBalance = walletSnap.exists
          ? (walletSnap['balance'] ?? 0).toDouble()
          : 0.0;

      transaction.set(
        walletRef,
        {'balance': currentBalance + amount},
        SetOptions(merge: true),
      );
      transaction.delete(expenseRef);
      transaction.delete(transactionRef);
    });
  }

  void _presentDatePicker() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: now.add(const Duration(days: 7)),
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  void _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please sign in before adding expenses.')),
      );
      return;
    }

    try {
      setState(() => _isSaving = true);
      final expenseAmount =
          double.parse(_amountController.text);

      final walletRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('wallets')
          .doc(_selectedWallet);

      final expenseRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('expenses')
          .doc();

      final transactionRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('transactions')
          .doc();

      await FirebaseFirestore.instance
          .runTransaction((transaction) async {
        final walletSnap = await transaction.get(walletRef);

        final currentBalance = walletSnap.exists
            ? (walletSnap['balance'] ?? 0).toDouble()
            : 0.0;

        if (currentBalance < expenseAmount) {
          throw Exception('Insufficient balance');
        }

        transaction.set(
          walletRef,
          {
            'balance': currentBalance - expenseAmount,
          },
          SetOptions(merge: true),
        );

        transaction.set(expenseRef, {
          'amount': expenseAmount,
          'description': _descriptionController.text.trim(),
          'category': _selectedCategory,
          'wallet': _selectedWallet,
          'date': Timestamp.fromDate(_selectedDate),
          'timestamp': FieldValue.serverTimestamp(),
        });

        transaction.set(transactionRef, {
          'type': 'expense',
          'amount': expenseAmount,
          'category': _selectedCategory,
          'description': _descriptionController.text.trim(),
          'wallet': _selectedWallet,
          'date': Timestamp.fromDate(_selectedDate),
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      _saveDefaults();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Expense added successfully!'),
          backgroundColor: Colors.green.shade600,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              _undoExpense(
                userId: userDocumentIdFor(user),
                amount: expenseAmount,
                wallet: _selectedWallet,
                expenseId: expenseRef.id,
                transactionId: transactionRef.id,
              );
            },
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final message = e
              .toString()
              .toLowerCase()
              .contains('insufficient')
          ? 'Insufficient balance in selected wallet.'
          : 'Failed to save expense. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE24B4A),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Colors.white))
          : Column(
              children: [
                // -- Red header with amount --------------
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 8, 16, 24),
                    child: Column(
                      children: [
                        // Back button + title
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () =>
                                  Navigator.pop(context),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withValues(
                                          alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                    size: 18),
                              ),
                            ),
                            const Expanded(
                              child: Text('Add Expense',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight:
                                          FontWeight.w500)),
                            ),
                            const SizedBox(width: 36),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Big amount display
                        Text('Enter amount',
                            style: TextStyle(
                                color: Colors.white
                                    .withValues(
                                        alpha: 0.75),
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        Form(
                          key: _formKey,
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType:
                                TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter
                                  .allow(RegExp(
                                      r'^\d*\.?\d{0,2}')),
                            ],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                            decoration: InputDecoration(
                              prefixText: '₹ ',
                              prefixStyle: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 28,
                                  fontWeight:
                                      FontWeight.w400),
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                  color: Colors.white
                                      .withValues(
                                          alpha: 0.35),
                                  fontSize: 52,
                                  fontWeight:
                                      FontWeight.bold),
                              border: InputBorder.none,
                              errorStyle: const TextStyle(
                                  color: Colors.white),
                            ),
                            validator: (v) {
                              if (v == null ||
                                  double.tryParse(v) ==
                                      null ||
                                  double.parse(v) <= 0) {
                                return 'Enter a valid amount';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Quick amount chips
                        Wrap(
                          spacing: 8,
                          children: _quickAmounts
                              .map((amt) => GestureDetector(
                                    onTap: () => setState(() =>
                                        _amountController
                                                .text =
                                            amt.toString()),
                                    child: Container(
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                              horizontal:
                                                  14,
                                              vertical: 7),
                                      decoration:
                                          BoxDecoration(
                                        color: Colors.white
                                            .withValues(
                                                alpha: 0.2),
                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                                    20),
                                        border: Border.all(
                                            color: Colors
                                                .white
                                                .withValues(
                                                    alpha:
                                                        0.4)),
                                      ),
                                      child: Text('₹$amt',
                                          style: const TextStyle(
                                              color: Colors
                                                  .white,
                                              fontSize: 13,
                                              fontWeight:
                                                  FontWeight
                                                      .w500)),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                // -- White bottom sheet ------------------
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Category
                          if (_categories.isEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(
                                  bottom: 12),
                              padding:
                                  const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFFCEBEB),
                                borderRadius:
                                    BorderRadius.circular(
                                        12),
                              ),
                              child: Row(
                                children: const [
                                  Icon(
                                      Icons.warning_rounded,
                                      size: 16,
                                      color: Color(
                                          0xFFE24B4A)),
                                  SizedBox(width: 8),
                                  Text(
                                      'No categories yet. Add one first.',
                                      style: TextStyle(
                                          color: Color(
                                              0xFFA32D2D),
                                          fontSize: 13)),
                                ],
                              ),
                            ),

                          _FieldTile(
                            iconBg: const Color(0xFFFCEBEB),
                            iconColor:
                                const Color(0xFFE24B4A),
                            icon: Icons.category_outlined,
                            label: 'Category',
                            child:
                                DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCategory,
                                dropdownColor: Colors.white,
                                hint: const Text(
                                  'Select category',
                                  style: TextStyle(
                                      color:
                                          Colors.black54),
                                ),
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                ),
                                iconEnabledColor:
                                    Colors.black54,
                                isExpanded: true,
                                items: _categories
                                    .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c,
                                            style: const TextStyle(
                                                color: Colors
                                                    .black87))))
                                    .toList(),
                                onChanged: (v) {
                                  setState(() =>
                                      _selectedCategory =
                                          v);
                                  _saveDefaults();
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Wallet
                          _FieldTile(
                            iconBg: const Color(0xFFE6F1FB),
                            iconColor:
                                const Color(0xFF185FA5),
                            icon: Icons
                                .account_balance_wallet_outlined,
                            label: 'Pay from',
                            child:
                                DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedWallet,
                                dropdownColor: Colors.white,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                ),
                                iconEnabledColor:
                                    Colors.black54,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'cash',
                                      child: Text('Cash',
                                          style: TextStyle(
                                              color: Colors
                                                  .black87))),
                                  DropdownMenuItem(
                                      value: 'bank',
                                      child: Text('Bank',
                                          style: TextStyle(
                                              color: Colors
                                                  .black87))),
                                  DropdownMenuItem(
                                      value: 'credit',
                                      child: Text(
                                          'Credit Card',
                                          style: TextStyle(
                                              color: Colors
                                                  .black87))),
                                ],
                                onChanged: (v) {
                                  setState(() =>
                                      _selectedWallet = v!);
                                  _saveDefaults();
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Date
                          GestureDetector(
                            onTap: _presentDatePicker,
                            child: _FieldTile(
                              iconBg:
                                  const Color(0xFFEAF3DE),
                              iconColor:
                                  const Color(0xFF3B6D11),
                              icon: Icons
                                  .calendar_today_outlined,
                              label: 'Date',
                              trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                  size: 20),
                              child: Text(
                                DateFormat(
                                        'EEE, MMM d yyyy')
                                    .format(_selectedDate),
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Note
                          _FieldTile(
                            iconBg: const Color(0xFFF1EFE8),
                            iconColor:
                                const Color(0xFF5F5E5A),
                            icon: Icons.notes_outlined,
                            label: 'Note (optional)',
                            child: TextField(
                              controller:
                                  _descriptionController,
                              maxLength: 100,
                              decoration:
                                  const InputDecoration(
                                hintText: 'Add a note...',
                                hintStyle: TextStyle(
                                    color: Colors.black54),
                                border: InputBorder.none,
                                counterText: '',
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.zero,
                              ),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 15,
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Save button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSaving
                                  ? null
                                  : _saveExpense,
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFFE24B4A),
                                foregroundColor:
                                    Colors.white,
                                padding: const EdgeInsets
                                    .symmetric(
                                    vertical: 16),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          14),
                                ),
                                elevation: 0,
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child:
                                          CircularProgressIndicator(
                                              strokeWidth:
                                                  2,
                                              color: Colors
                                                  .white))
                                  : const Text(
                                      'Save Expense',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight
                                                  .w600)),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
  });

  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: const TextStyle(
                      color: Colors.black87),
                  child: child,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
