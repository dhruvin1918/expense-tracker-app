import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SetBudgetPage extends StatefulWidget {
  final List<String> categories;

  const SetBudgetPage(
      {super.key, required this.categories});

  @override
  State<SetBudgetPage> createState() =>
      _SetBudgetPageState();
}

class _SetBudgetPageState extends State<SetBudgetPage> {
  final _formKey = GlobalKey<FormState>();
  final _monthlyBudgetController = TextEditingController();
  final Map<String, TextEditingController>
      _budgetControllers = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    for (var category in widget.categories) {
      _budgetControllers[category] =
          TextEditingController();
    }
    _fetchExistingBudgets();
  }

  @override
  void dispose() {
    _monthlyBudgetController.dispose();
    _budgetControllers
        .forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  /// 🔹 Fetch existing budgets from Firestore
  void _fetchExistingBudgets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      if (data != null) {
        setState(() {
          _monthlyBudgetController.text =
              (data['monthlyBudget'] ?? '').toString();

          final categoryBudgets = data['categoryBudgets']
              as Map<String, dynamic>?;

          if (categoryBudgets != null) {
            categoryBudgets.forEach((category, amount) {
              if (_budgetControllers
                  .containsKey(category)) {
                _budgetControllers[category]!.text =
                    amount.toString();
              }
            });
          }
        });
      }
    }
  }

  /// 🔹 Save budgets to Firestore
  void _saveBudgets() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Please log in to save your budget.')),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final monthlyBudget =
          double.tryParse(_monthlyBudgetController.text) ??
              0.0;
      final categoryBudgets = <String, double>{};

      double totalCategory = 0.0;

      _budgetControllers.forEach((category, controller) {
        final amount =
            double.tryParse(controller.text) ?? 0.0;
        categoryBudgets[category] = amount;
        totalCategory += amount;
      });

      // ✅ Validation: categories should not exceed monthly
      if (totalCategory > monthlyBudget) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Category total (₹$totalCategory) exceeds Monthly Budget (₹$monthlyBudget)'),
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(
        {
          'monthlyBudget': monthlyBudget,
          'categoryBudgets': categoryBudgets,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Budgets saved successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Set Your Budget',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // 🔹 Monthly Budget
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20),
                      child: TextFormField(
                        controller:
                            _monthlyBudgetController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                            color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Monthly Total Budget',
                          labelStyle: TextStyle(
                              color: colorScheme.outline),
                          prefixText: '₹',
                          prefixStyle: TextStyle(
                              color: colorScheme.onSurface),
                          filled: true,
                          fillColor: colorScheme
                              .surfaceVariant
                              .withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colorScheme.outline,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colorScheme.error,
                              width: 1,
                            ),
                          ),
                          focusedErrorBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colorScheme.error,
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.isEmpty ||
                              double.tryParse(value) ==
                                  null ||
                              double.parse(value) <= 0) {
                            return 'Please enter a valid amount.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const Divider(),
                    Text(
                      'Category Budgets',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 🔹 Category Inputs
                    Expanded(
                      child: ListView.builder(
                        itemCount: widget.categories.length,
                        itemBuilder: (context, index) {
                          final category =
                              widget.categories[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                                bottom: 15),
                            child: TextFormField(
                              controller:
                                  _budgetControllers[
                                      category],
                              keyboardType:
                                  TextInputType.number,
                              style: TextStyle(
                                  color: colorScheme
                                      .onSurface),
                              decoration: InputDecoration(
                                labelText: category,
                                labelStyle: TextStyle(
                                    color: colorScheme
                                        .outline),
                                prefixText: '₹',
                                prefixStyle: TextStyle(
                                    color: colorScheme
                                        .onSurface),
                                filled: true,
                                fillColor: colorScheme
                                    .surfaceVariant
                                    .withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          10),
                                  borderSide: BorderSide(
                                    color:
                                        colorScheme.outline,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder:
                                    OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          10),
                                  borderSide: BorderSide(
                                    color:
                                        colorScheme.primary,
                                    width: 2,
                                  ),
                                ),
                                errorBorder:
                                    OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          10),
                                  borderSide: BorderSide(
                                    color:
                                        colorScheme.error,
                                    width: 1,
                                  ),
                                ),
                                focusedErrorBorder:
                                    OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          10),
                                  borderSide: BorderSide(
                                    color:
                                        colorScheme.error,
                                    width: 2,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value != null &&
                                    value.isNotEmpty &&
                                    double.tryParse(
                                            value) ==
                                        null) {
                                  return 'Enter valid number';
                                }
                                return null;
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    // 🔹 Save & Cancel
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saveBudgets,
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    colorScheme.primary,
                                foregroundColor:
                                    colorScheme.onPrimary,
                                padding: const EdgeInsets
                                    .symmetric(
                                    vertical: 15),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          10),
                                ),
                              ),
                              child: Text(
                                'Save Budget',
                                style: TextStyle(
                                  fontSize: 18,
                                  color:
                                      colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(context),
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor: colorScheme
                                    .surfaceVariant,
                                foregroundColor: colorScheme
                                    .onSurfaceVariant,
                                padding: const EdgeInsets
                                    .symmetric(
                                    vertical: 15),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          10),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
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
}
