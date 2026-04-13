import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/transaction_service.dart';
class WalletDetailPage extends StatefulWidget {
  final String walletId;
  final String walletName;
  const WalletDetailPage({
    super.key,
    required this.walletId,
    required this.walletName,
  });
  @override
  State<WalletDetailPage> createState() =>
      _WalletDetailPageState();
}
class _WalletDetailPageState
    extends State<WalletDetailPage> {
  String _filterType = 'All'; // All, Income, Expense
  void _showActionSheet(
      BuildContext context, Map<String, dynamic> tx) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(context, tx);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete,
                  color: colorScheme.error),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(
                  context,
                  tx['id'],
                  tx['wallet'],
                  tx['amount'],
                  tx['type'],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  // Calculate month start date
  DateTime _getMonthStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }
  // Get category label
  String _getCategoryLabel(String description) {
    final desc = description.toLowerCase();
    if (desc.contains('gpay') ||
        desc.contains('google pay')) {
      return 'UPI';
    } else if (desc.contains('bhim')) {
      return 'UPI';
    } else if (desc.contains('cashback')) {
      return 'Cashback';
    } else if (desc.contains('cash')) {
      return 'Cash';
    }
    return 'Transfer';
  }
  void _showEditDialog(
      BuildContext context, Map<String, dynamic> tx) {
    final amountController = TextEditingController(
        text: tx['amount'].toString());
    final descController =
        TextEditingController(text: tx['description']);
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Edit Transaction'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Amount'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                      labelText: 'Description'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final newAmount = double.tryParse(
                            amountController.text);
                        if (newAmount == null ||
                            newAmount <= 0) {
                          ScaffoldMessenger.of(
                                  dialogContext)
                              .showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Enter a valid amount.'),
                            ),
                          );
                          return;
                        }
                        setState(() => isSaving = true);
                        try {
                          await TransactionService
                              .updateTransaction(
                            transactionId: tx['id'],
                            walletId: tx['wallet'],
                            oldAmount: tx['amount'],
                            newAmount: newAmount,
                            description:
                                descController.text,
                            type: tx['type'],
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (e) {
                          debugPrint('Update error: $e');
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(
                                    dialogContext)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Failed to update. Please try again.',
                                ),
                              ),
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setState(
                                () => isSaving = false);
                          }
                        }
                      },
                child: Text(
                    isSaving ? 'Updating...' : 'Update'),
              ),
            ],
          ),
        );
      },
    );
  }
  void _confirmDelete(
    BuildContext context,
    String transactionId,
    String walletId,
    double amount,
    String type,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text(
            'Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await TransactionService.deleteTransaction(
                  transactionId: transactionId,
                  walletId: walletId,
                  amount: amount,
                  type: type,
                );
              } catch (e) {
                debugPrint('Delete error: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Failed to delete. Please try again.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in')),
      );
    }
    final walletRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('wallets')
        .doc(widget.walletId);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.walletName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          /// 🔹 BALANCE CARD WITH MONTHLY SUMMARY
          StreamBuilder<DocumentSnapshot>(
            stream: walletRef.snapshots(),
            builder: (context, walletSnap) {
              double balance = 0.0;
              if (walletSnap.hasData &&
                  walletSnap.data!.exists) {
                final data = walletSnap.data!.data()
                    as Map<String, dynamic>;
                balance = (data['balance'] ?? 0).toDouble();
              }
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('income')
                    .where('wallet', isEqualTo: widget.walletId)
                    .where('date',
                        isGreaterThanOrEqualTo:
                            Timestamp.fromDate(
                                _getMonthStart()))
                    .snapshots(),
                builder: (context, incomeSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('expenses')
                        .where('wallet',
                            isEqualTo: widget.walletId)
                        .where('date',
                            isGreaterThanOrEqualTo:
                                Timestamp.fromDate(
                                    _getMonthStart()))
                        .snapshots(),
                    builder: (context, expenseSnap) {
                      double monthIncome = 0.0;
                      double monthExpense = 0.0;
                      if (incomeSnap.hasData) {
                        for (var doc in incomeSnap.data!.docs) {
                          monthIncome += (doc['amount'] as num)
                              .toDouble();
                        }
                      }
                      if (expenseSnap.hasData) {
                        for (var doc in expenseSnap.data!.docs) {
                          monthExpense += (doc['amount'] as num)
                              .toDouble();
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary
                                    .withAlpha(220),
                              ],
                              begin:
                                  Alignment.topLeft,
                              end: Alignment
                                  .bottomRight,
                            ),
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets
                              .all(20),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                'Available Balance',
                                style: Theme.of(
                                  context,
                                )
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors
                                          .white
                                          .withAlpha(
                                              200),
                                      letterSpacing:
                                          0.5,
                                    ),
                              ),
                              const SizedBox(
                                  height: 8),
                              Text(
                                '₹${balance.toStringAsFixed(2)}',
                                style: Theme.of(
                                  context,
                                )
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight:
                                          FontWeight
                                              .bold,
                                      color:
                                          Colors.white,
                                    ),
                              ),
                              const SizedBox(
                                  height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment
                                        .spaceEvenly,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        'This Month In',
                                        style:
                                            TextStyle(
                                          color: Colors
                                              .white
                                              .withAlpha(
                                                  200),
                                          fontSize:
                                              12,
                                        ),
                                      ),
                                      const SizedBox(
                                          height: 4),
                                      Text(
                                        '+₹${monthIncome.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          color:
                                              Colors
                                                  .white,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        'This Month Out',
                                        style:
                                            TextStyle(
                                          color: Colors
                                              .white
                                              .withAlpha(
                                                  200),
                                          fontSize:
                                              12,
                                        ),
                                      ),
                                      const SizedBox(
                                          height: 4),
                                      Text(
                                        '-₹${monthExpense.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          color:
                                              Color(0xFFFF6B6B),
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          /// 🔹 FILTER TABS
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Income', 'Expense']
                    .map((filter) {
                  final isSelected =
                      _filterType == filter;
                  return Padding(
                    padding:
                        const EdgeInsets.only(
                            right: 8),
                    child: FilterChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(
                            () =>
                                _filterType =
                                    filter);
                      },
                      backgroundColor:
                          Colors.transparent,
                      side: BorderSide(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme
                                .outlineVariant,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme
                                .onSurfaceVariant,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          /// 🔹 TRANSACTIONS LIST BY DATE
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('income')
                  .where('wallet',
                      isEqualTo: widget.walletId)
                  .snapshots(),
              builder: (context, incomeSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('expenses')
                      .where('wallet',
                          isEqualTo:
                              widget.walletId)
                      .snapshots(),
                  builder: (context,
                      expenseSnap) {
                    if (!incomeSnap.hasData ||
                        !expenseSnap.hasData) {
                      return const Center(
                        child:
                            CircularProgressIndicator(),
                      );
                    }
                    final List<Map<
                        String,
                        dynamic>> items = [
                      ...incomeSnap.data!.docs
                          .map((d) => {
                                'id': d.id,
                                'wallet': d['wallet'],
                                'type': 'income',
                                'amount': (d[
                                        'amount'] as num)
                                    .toDouble(),
                                'description':
                                    d['description'] ??
                                        '',
                                'date': (d['date']
                                        as Timestamp)
                                    .toDate(),
                              }),
                      ...expenseSnap.data!.docs
                          .map((d) => {
                                'id': d.id,
                                'wallet': d['wallet'],
                                'type': 'expense',
                                'amount': (d[
                                        'amount'] as num)
                                    .toDouble(),
                                'description':
                                    d['description'] ??
                                        '',
                                'date': (d['date']
                                        as Timestamp)
                                    .toDate(),
                              }),
                    ];
                    // Filter by type
                    if (_filterType !=
                        'All') {
                      items.retainWhere((item) =>
                          item['type']
                              .toString()
                              .toLowerCase() ==
                          _filterType
                              .toLowerCase());
                    }
                    items.sort((a, b) =>
                        b['date']
                            .compareTo(
                                a['date']));
                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          children: [
                            Icon(
                              Icons
                                  .receipt_long_outlined,
                              size: 48,
                              color: colorScheme
                                  .outline,
                            ),
                            const SizedBox(
                                height: 12),
                            Text(
                              'No transactions yet',
                              style: TextStyle(
                                color: colorScheme
                                    .outline,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    // Group by date
                    final Map<String,
                        List<Map<
                            String,
                            dynamic>>> grouped =
                        {};
                    for (var item
                        in items) {
                      final dateKey =
                          DateFormat(
                                  'EEEE — MMM d, yyyy')
                              .format(item[
                                  'date']);
                      if (!grouped
                          .containsKey(
                              dateKey)) {
                        grouped[dateKey] =
                            [];
                      }
                      grouped[dateKey]!
                          .add(item);
                    }
                    return ListView(
                      padding:
                          const EdgeInsets
                              .symmetric(
                              horizontal: 16,
                              vertical: 8),
                      children: grouped
                          .entries
                          .map((entry) {
                        final dateGroup =
                            entry.key;
                        final txList =
                            entry.value;
                        return Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets
                                      .only(
                                      top: 16,
                                      bottom: 12),
                              child: Text(
                                dateGroup
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight
                                          .w600,
                                  color:
                                      colorScheme
                                          .outline,
                                  letterSpacing:
                                      0.5,
                                ),
                              ),
                            ),
                            ...txList.map(
                                (tx) {
                              final isIncome =
                                  tx['type'] ==
                                      'income';
                              return _buildTransactionCard(
                                context,
                                tx,
                                isIncome,
                              );
                            }),
                          ],
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildTransactionCard(
    BuildContext context,
    Map<String,
        dynamic> tx,
    bool isIncome,
  ) {
    final colorScheme =
        Theme.of(context).colorScheme;
    final category =
        _getCategoryLabel(
            tx['description']);
    return Container(
      margin: const EdgeInsets.only(
          bottom: 12),
      decoration: BoxDecoration(
        color: isIncome
            ? Colors.green
                .withAlpha(20)
            : Colors.red
                .withAlpha(20),
        border: Border.all(
          color: isIncome
              ? Colors.green
                  .withAlpha(100)
              : Colors.red
                  .withAlpha(100),
          width: 0.5,
        ),
        borderRadius:
            BorderRadius.circular(
                12),
      ),
      child: InkWell(
        onLongPress: () {
          _showActionSheet(
              context, tx);
        },
        borderRadius:
            BorderRadius.circular(
                12),
        child: Padding(
          padding:
              const EdgeInsets
                  .all(12),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets
                        .all(10),
                decoration:
                    BoxDecoration(
                  color: isIncome
                      ? Colors.green
                          .withAlpha(
                              50)
                      : Colors.red
                          .withAlpha(
                              50),
                  shape:
                      BoxShape
                          .circle,
                ),
                child: Icon(
                  isIncome
                      ? Icons
                          .arrow_downward
                      : Icons
                          .arrow_upward,
                  color: isIncome
                      ? Colors.green
                          .shade600
                      : Colors.red
                          .shade600,
                  size: 18,
                ),
              ),
              const SizedBox(
                  width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      tx['description'],
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight
                                    .w600,
                          ),
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                    ),
                    const SizedBox(
                        height: 4),
                    Text(
                      'Expense • $category',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .end,
                children: [
                  Text(
                    '${isIncome ? '+' : '-'}₹${tx['amount'].toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight:
                          FontWeight
                              .bold,
                      color: isIncome
                          ? Colors.green
                              .shade600
                          : Colors.red
                              .shade600,
                    ),
                  ),
                  const SizedBox(
                      height: 4),
                  Text(
                    'Bal ₹40,381',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme
                          .outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}