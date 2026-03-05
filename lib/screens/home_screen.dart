import 'package:flutter/material.dart';
import 'package:personal_finance_tracker/theme/app_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../helpers/database_helper.dart';
import '../helpers/dialog_helper.dart';
import '../helpers/notification_service.dart';
import '../models/bill.dart';
import '../models/transaction.dart' as model;
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import 'all_transactions_screen.dart';
import 'add_bill_screen.dart';
import 'edit_bill_screen.dart';
import 'transaction_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final dbHelper = DatabaseHelper();
  List<model.Transaction> _transactions = [];
  List<Bill> _bills = [];
  bool _isLoading = true;
  Set<int> _payingBills = {}; // Track which bills are being paid
  double _totalIncome = 0.0;
  double _totalExpenses = 0.0;
  double _balance = 0.0;
  String _currencySymbol = 'KSh';

  final User? _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _initHome();
  }

  Future<void> _initHome() async {
    if (!mounted) return;
    if (_currentUser != null) {
      _refreshData();
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    if (_currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadCurrencyPreference(),
        _loadBills(_currentUser!.uid),
        _loadTransactions(_currentUser!.uid),
      ]);
    } catch (e) {
      debugPrint("Error refreshing data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCurrencyPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currencySymbol = prefs.getString('currency') ?? 'KSh';
      });
    }
  }

  void _calculateSummary(List<model.Transaction> transactions) {
    _totalIncome = transactions
        .where((t) => t.type == 'income')
        .fold(0.0, (sum, t) => sum + t.amount);
    _totalExpenses = transactions
        .where((t) => t.type == 'expense')
        .fold(0.0, (sum, t) => sum + t.amount);
    _balance = _totalIncome - _totalExpenses;
  }

  Future<void> _loadTransactions(String userId) async {
    final allTransactions = await dbHelper.getTransactions(userId);
    if (mounted) {
      _calculateSummary(allTransactions);
      setState(() {
        _transactions = allTransactions;
      });
    }
  }

  Future<void> _loadBills(String userId) async {
    final bills = await dbHelper.getBills(userId);
    if (mounted) {
      setState(() {
        _bills = bills;
      });
    }
  }

  Future<void> _deleteTransaction(int id, String userId) async {
    await dbHelper.deleteTransaction(id, userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction Deleted')),
      );
    }
    _refreshData();
  }

  Future<void> _editBill(Bill bill) async {
    if (_currentUser == null) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => EditBillScreen(bill: bill),
      ),
    );

    if (result == true && mounted) {
      _refreshData();
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    if (_currentUser == null || bill.id == null) return;

    final bool? confirm = await DialogHelper.showConfirmDialog(
      context: context,
      title: 'Delete Bill',
      message:
          'Are you sure you want to delete "${bill.name}"? This action cannot be undone.',
      confirmText: 'Delete',
      confirmColor: AppColors.error,
    );

    if (confirm == true && mounted) {
      try {
        // Cancel notification
        final notificationService = NotificationService();
        await notificationService.cancelNotification(bill.id!);

        await dbHelper.deleteBill(bill.id!, _currentUser.uid);

        if (mounted) {
          SnackbarHelper.showSuccess(context, 'Bill deleted successfully!');
          _refreshData();
        }
      } catch (e) {
        if (mounted) {
          SnackbarHelper.showError(context, 'Failed to delete bill');
        }
      }
    }
  }

  ({IconData icon, Color color}) _getBillStyling(String billName) {
    final name = billName.toLowerCase();
    if (name.contains('rent'))
      return (icon: AppIcons.house_outlined, color: AppColors.warning);
    if (name.contains('netflix') || name.contains('movie'))
      return (icon: AppIcons.movie_outlined, color: AppColors.error);
    if (name.contains('wifi') || name.contains('internet'))
      return (icon: AppIcons.wifi, color: AppColors.info);
    if (name.contains('electricity') || name.contains('power'))
      return (icon: AppIcons.lightbulb_outline, color: AppColors.warning);
    if (name.contains('water'))
      return (icon: AppIcons.water_drop_outlined, color: AppColors.secondary);
    if (name.contains('loan') || name.contains('debt'))
      return (icon: AppIcons.credit_card_outlined, color: AppColors.tertiary);
    return (
      icon: AppIcons.receipt_long_outlined,
      color: AppColors.neutralMedium
    );
  }

  ({String text, Color color}) _getBillStatus(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final daysLeft = dueDay.difference(today).inDays;

    if (daysLeft < 0) {
      return (text: 'Overdue', color: AppColors.error);
    } else if (daysLeft == 0) {
      return (text: 'Due Today', color: AppColors.warning);
    } else if (daysLeft <= 7) {
      return (text: 'Due in $daysLeft days', color: AppColors.warning);
    } else {
      return (text: '$daysLeft days left', color: AppColors.neutralMedium);
    }
  }

  DateTime _calculateNextDueDate(Bill bill) {
    if (bill.recurrenceType == 'monthly') {
      return DateTime(
          bill.dueDate.year, bill.dueDate.month + 1, bill.dueDate.day);
    } else if (bill.recurrenceType == 'weekly') {
      return bill.dueDate.add(const Duration(days: 7));
    }
    return bill.dueDate;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        final currentUser = snapshot.data;

        return Scaffold(
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refreshData,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getGreeting(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: const Color(0xFF6B7280),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentUser?.displayName ?? 'User',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1A1A2E),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 12.0),
                                child: Column(
                                  children: [
                                    SummaryCard(
                                        title: 'Total Income',
                                        amount: _totalIncome,
                                        icon: AppIcons.trending_up,
                                        color: const Color(0xFF10B981),
                                        currencySymbol: _currencySymbol),
                                    const SizedBox(height: 12),
                                    SummaryCard(
                                        title: 'Total Expenses',
                                        amount: _totalExpenses,
                                        icon: AppIcons.trending_down,
                                        color: const Color(0xFFEF4444),
                                        currencySymbol: _currencySymbol),
                                    const SizedBox(height: 12),
                                    SummaryCard(
                                        title: 'Balance',
                                        amount: _balance,
                                        icon: AppIcons.account_balance,
                                        color: _balance >= 0
                                            ? const Color(0xFF1F6FEB)
                                            : const Color(0xFFFF9F1C),
                                        currencySymbol: _currencySymbol),
                                  ],
                                ),
                              ),
                              _buildUpcomingBillsSection(currentUser),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    24.0, 20.0, 24.0, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Recent Transactions',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1A1A2E),
                                              ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            if (currentUser == null) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (context) =>
                                                      const AllTransactionsScreen()),
                                            ).then((_) => _refreshData());
                                          },
                                          child: Text(
                                            'See All',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  color:
                                                      const Color(0xFF1F6FEB),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        )
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Row(
                                        children: [
                                          Icon(AppIcons.info_outline,
                                              size: 14,
                                              color: const Color(0xFF9CA3AF)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Swipe left to delete, or right to edit',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: const Color(0xFF9CA3AF),
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildTransactionList(currentUser),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (context) => const AddTransactionScreen()),
              );
              // Only refresh if a transaction was actually saved (result == true)
              if (result == true && currentUser != null && mounted) {
                await _refreshData();
              }
            },
            backgroundColor: const Color(0xFF1F6FEB),
            foregroundColor: Colors.white,
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            label: Text(
              'Add Transaction',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            icon: const Icon(AppIcons.add),
          ),
        );
      },
    );
  }

  Widget _buildUpcomingBillsSection(User? currentUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Upcoming Bills',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E),
                    ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const AddBillScreen()))
                      .then((_) {
                    if (currentUser != null) {
                      _refreshData();
                    }
                  });
                },
                child: Text(
                  'Add Bill',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF1F6FEB),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
        _bills.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: Center(child: Text('No upcoming bills.')),
              )
            : SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  itemCount: _bills.length,
                  itemBuilder: (context, index) {
                    final bill = _bills[index];
                    final styling = _getBillStyling(bill.name);
                    final status = _getBillStatus(bill.dueDate);

                    return SizedBox(
                      width: 178,
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                              color: status.color.withOpacity(0.2), width: 1.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10.0, vertical: 14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Icon(styling.icon,
                                      size: 24, color: styling.color),
                                  const Spacer(),
                                  if (bill.isRecurring)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(LucideIcons.repeat,
                                          size: 14,
                                          color: Colors.grey.shade600),
                                    ),
                                  PopupMenuButton<String>(
                                    icon: Icon(LucideIcons.moreVertical,
                                        size: 18, color: Colors.grey.shade600),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _editBill(bill);
                                      } else if (value == 'delete') {
                                        _deleteBill(bill);
                                      }
                                    },
                                    itemBuilder: (BuildContext context) => [
                                      const PopupMenuItem<String>(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(LucideIcons.pencil,
                                                size: 20,
                                                color: Color(0xFF4CAF50)),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(LucideIcons.trash2,
                                                size: 20, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        bill.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Flexible(
                                      child: Text(
                                        '$_currencySymbol${bill.amount.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Flexible(
                                      child: Text(
                                        status.text,
                                        style: TextStyle(
                                          color: status.color,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: _payingBills.contains(bill.id)
                                      ? null
                                      : () async {
                                          if (currentUser == null ||
                                              bill.id == null) return;

                                          setState(() {
                                            _payingBills.add(bill.id!);
                                          });

                                          try {
                                            final billTransaction =
                                                model.Transaction(
                                              type: 'expense',
                                              amount: bill.amount,
                                              description:
                                                  'Paid bill: ${bill.name}',
                                              date: DateTime.now()
                                                  .toIso8601String(),
                                              categoryId: await dbHelper
                                                  .getOrCreateCategory(
                                                      'Bills', currentUser.uid,
                                                      type: 'expense'),
                                            );
                                            await dbHelper.addTransaction(
                                                billTransaction,
                                                currentUser.uid);

                                            if (bill.isRecurring) {
                                              final nextDueDate =
                                                  _calculateNextDueDate(bill);
                                              final updatedBill = bill.copyWith(
                                                  dueDate: nextDueDate);

                                              // Update notification for new due date
                                              final notificationService =
                                                  NotificationService();
                                              if (bill.id != null) {
                                                await notificationService
                                                    .cancelNotification(
                                                        bill.id!);
                                                await notificationService
                                                    .scheduleBillNotification(
                                                        updatedBill);
                                              }

                                              await dbHelper.updateBill(
                                                  updatedBill, currentUser.uid);
                                              if (mounted) {
                                                SnackbarHelper.showSuccess(
                                                    context,
                                                    'Recurring bill "${bill.name}" paid. Next due date set.');
                                              }
                                            } else {
                                              // Cancel notification before deleting
                                              final notificationService =
                                                  NotificationService();
                                              if (bill.id != null) {
                                                await notificationService
                                                    .cancelNotification(
                                                        bill.id!);
                                              }

                                              await dbHelper.deleteBill(
                                                  bill.id!, currentUser.uid);
                                              if (mounted) {
                                                SnackbarHelper.showSuccess(
                                                    context,
                                                    'Bill "${bill.name}" marked as paid.');
                                              }
                                            }

                                            _refreshData();
                                          } catch (e) {
                                            if (mounted) {
                                              SnackbarHelper.showError(context,
                                                  'Failed to pay bill');
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() {
                                                _payingBills.remove(bill.id);
                                              });
                                            }
                                          }
                                        },
                                  icon: _payingBills.contains(bill.id)
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(LucideIcons.check, size: 18),
                                  label: _payingBills.contains(bill.id)
                                      ? const Text('Processing...',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600))
                                      : const Text('Pay Bill',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ],
    );
  }

  Widget _buildTransactionList(User? currentUser) {
    if (_transactions.isEmpty) {
      return Center(
        heightFactor: 5,
        child: Text(
          'No transactions yet. Add one!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF9CA3AF),
                fontFamily: 'Poppins',
              ),
        ),
      );
    }

    final currencyFormatter =
        NumberFormat.currency(locale: 'en_US', symbol: '');
    final recentTransactions = _transactions.take(10).toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recentTransactions.length,
      itemBuilder: (context, index) {
        final transaction = recentTransactions[index];
        final isIncome = transaction.type == 'income';
        final amountColor =
            isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
        final amountPrefix = isIncome ? '+' : '-';

        return Dismissible(
          key: ValueKey(transaction.id),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              // Swipe right for edit
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (context) =>
                        TransactionDetailScreen(transaction: transaction)),
              );
              if (result == true) {
                _refreshData();
              }
              return false; // Do not dismiss the item after swiping right
            } else {
              // Swipe left for delete
              return await DialogHelper.showConfirmDialog(
                context: context,
                title: 'Confirm Deletion',
                message: 'Are you sure you want to delete this transaction?',
                confirmText: 'Delete',
                confirmColor: const Color(0xFFEF4444),
              );
            }
          },
          onDismissed: (direction) {
            if (direction == DismissDirection.endToStart &&
                currentUser != null) {
              _deleteTransaction(transaction.id!, currentUser.uid);
            }
          },
          background: Container(
            color: const Color(0xFF1F6FEB),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const Icon(AppIcons.edit, color: Colors.white),
          ),
          secondaryBackground: Container(
            color: const Color(0xFFEF4444),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerRight,
            child: const Icon(AppIcons.delete, color: Colors.white),
          ),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: const Color(0xFFE5E7EB), width: 1),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: amountColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isIncome ? AppIcons.arrow_downward : AppIcons.arrow_upward,
                  color: amountColor,
                  size: 20,
                ),
              ),
              title: Text(
                transaction.description.isNotEmpty
                    ? transaction.description
                    : transaction.type.capitalize(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  transaction.date.split('T')[0],
                  style: TextStyle(
                    color: const Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              trailing: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.3,
                ),
                child: Text(
                  '$amountPrefix$_currencySymbol ${currencyFormatter.format(transaction.amount)}',
                  style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Poppins',
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;
  final String currencySymbol;

  const SummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter =
        NumberFormat.currency(locale: 'en_US', symbol: '');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.08),
              color.withOpacity(0.03),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$currencySymbol ${currencyFormatter.format(amount)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
