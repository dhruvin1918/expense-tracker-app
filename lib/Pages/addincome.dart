import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:practice/services/user_firestore_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Addincome extends StatefulWidget {
  const Addincome({super.key});

  @override
  State<Addincome> createState() => _AddincomeState();
}

class _AddincomeState extends State<Addincome> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String _selectedWallet = 'cash';
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
    _loadDefaults();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _presentDatePicker() async {
    final now = DateTime.now();
    final firstDate =
        DateTime(now.year - 5, now.month, now.day);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 7)),
    );

    if (pickedDate != null && mounted) {
      setState(() => _selectedDate = pickedDate);
    }
  }

  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedWallet =
          prefs.getString('default_income_wallet') ??
              'cash';
    });
  }

  Future<void> _saveDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'default_income_wallet', _selectedWallet);
  }

  Future<void> _undoIncome({
    required String userId,
    required double amount,
    required String wallet,
    required String incomeId,
    required String transactionId,
  }) async {
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId);
    final walletRef =
        userRef.collection('wallets').doc(wallet);
    final incomeRef =
        userRef.collection('income').doc(incomeId);
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
        {'balance': currentBalance - amount},
        SetOptions(merge: true),
      );
      transaction.delete(incomeRef);
      transaction.delete(transactionRef);
    });
  }

  void _saveIncome() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please sign in before adding income.')),
      );
      return;
    }

    try {
      setState(() => _isSaving = true);
      final amount = double.parse(_amountController.text);

      final walletRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('wallets')
          .doc(_selectedWallet);

      final incomeRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('income')
          .doc();

      final transactionRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('transactions')
          .doc();

      await FirebaseFirestore.instance
          .runTransaction((transaction) async {
        final walletSnap = await transaction.get(walletRef);
        final currentBalance =
            (walletSnap.data()?['balance'] ?? 0).toDouble();

        transaction.set(
          walletRef,
          {'balance': currentBalance + amount},
          SetOptions(merge: true),
        );

        transaction.set(incomeRef, {
          'amount': amount,
          'description': _descriptionController.text.trim(),
          'wallet': _selectedWallet,
          'date': Timestamp.fromDate(_selectedDate),
          'timestamp': FieldValue.serverTimestamp(),
        });

        transaction.set(transactionRef, {
          'type': 'income',
          'amount': amount,
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
          content: const Text('Income added successfully!'),
          backgroundColor: Colors.green.shade600,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              _undoIncome(
                userId: userDocumentIdFor(user),
                amount: amount,
                wallet: _selectedWallet,
                incomeId: incomeRef.id,
                transactionId: transactionRef.id,
              );
            },
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Income save error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Failed to save income. Please try again.'),
        ),
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
      backgroundColor: const Color(0xFF1FA36A),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 18),
                        ),
                      ),
                      const Expanded(
                        child: Text('Add Income',
                            textAlign: TextAlign.center,
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
                  Text('Enter amount',
                      style: TextStyle(
                          color: Colors.white
                              .withValues(alpha: 0.75),
                          fontSize: 13)),
                  const SizedBox(height: 8),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
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
                            fontWeight: FontWeight.w400),
                        hintText: '0.00',
                        hintStyle: TextStyle(
                            color: Colors.white
                                .withValues(alpha: 0.35),
                            fontSize: 52,
                            fontWeight: FontWeight.bold),
                        border: InputBorder.none,
                        errorStyle: const TextStyle(
                            color: Colors.white),
                      ),
                      validator: (value) {
                        if (value == null ||
                            double.tryParse(value) ==
                                null ||
                            double.parse(value) <= 0) {
                          return 'Enter valid amount';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: _quickAmounts
                        .map((amt) => GestureDetector(
                              onTap: () => setState(() =>
                                  _amountController.text =
                                      amt.toString()),
                              child: Container(
                                padding: const EdgeInsets
                                    .symmetric(
                                    horizontal: 14,
                                    vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withValues(
                                          alpha: 0.2),
                                  borderRadius:
                                      BorderRadius.circular(
                                          20),
                                  border: Border.all(
                                      color: Colors.white
                                          .withValues(
                                              alpha: 0.4)),
                                ),
                                child: Text('₹$amt',
                                    style: const TextStyle(
                                        color: Colors.white,
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
                    _FieldTile(
                      iconBg: const Color(0xFFE6F1FB),
                      iconColor: const Color(0xFF185FA5),
                      icon: Icons
                          .account_balance_wallet_outlined,
                      label: 'Wallet',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedWallet,
                          dropdownColor: Colors.white,
                          style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 15),
                          iconEnabledColor: Colors.black54,
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
                                child: Text('Credit Card',
                                    style: TextStyle(
                                        color: Colors
                                            .black87))),
                          ],
                          onChanged: (value) {
                            setState(() =>
                                _selectedWallet = value!);
                            _saveDefaults();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _presentDatePicker,
                      child: _FieldTile(
                        iconBg: const Color(0xFFEAF3DE),
                        iconColor: const Color(0xFF3B6D11),
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        trailing: const Icon(
                            Icons.chevron_right,
                            color: Colors.grey,
                            size: 20),
                        child: Text(
                          DateFormat('EEE, MMM d yyyy')
                              .format(_selectedDate),
                          style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FieldTile(
                      iconBg: const Color(0xFFF1EFE8),
                      iconColor: const Color(0xFF5F5E5A),
                      icon: Icons.notes_outlined,
                      label: 'Note (optional)',
                      child: TextField(
                        controller: _descriptionController,
                        maxLength: 100,
                        style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'Add a note...',
                          hintStyle: TextStyle(
                              color: Colors.black54),
                          border: InputBorder.none,
                          counterText: '',
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _isSaving ? null : _saveIncome,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF1FA36A),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(
                                  vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color:
                                            Colors.white),
                              )
                            : const Text('Save Income',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.w600)),
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
