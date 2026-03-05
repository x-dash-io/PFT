import 'dart:math' as math;

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
  final Set<int> _payingBills = <int>{};
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
      debugPrint('Error refreshing data: $e');
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
        const SnackBar(content: Text('Transaction deleted')),
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
    if (name.contains('rent')) {
      return (icon: AppIcons.house_outlined, color: AppColors.warning);
    }
    if (name.contains('netflix') || name.contains('movie')) {
      return (icon: AppIcons.movie_outlined, color: AppColors.error);
    }
    if (name.contains('wifi') || name.contains('internet')) {
      return (icon: AppIcons.wifi, color: AppColors.info);
    }
    if (name.contains('electricity') || name.contains('power')) {
      return (icon: AppIcons.lightbulb_outline, color: AppColors.warning);
    }
    if (name.contains('water')) {
      return (icon: AppIcons.water_drop_outlined, color: AppColors.secondary);
    }
    if (name.contains('loan') || name.contains('debt')) {
      return (icon: AppIcons.credit_card_outlined, color: AppColors.tertiary);
    }
    return (
      icon: AppIcons.receipt_long_outlined,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  ({String text, Color color}) _getBillStatus(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final daysLeft = dueDay.difference(today).inDays;

    if (daysLeft < 0) {
      return (text: 'Overdue', color: AppColors.error);
    }
    if (daysLeft == 0) {
      return (text: 'Due today', color: AppColors.warning);
    }
    if (daysLeft <= 7) {
      return (text: 'Due in $daysLeft days', color: AppColors.warning);
    }
    return (
      text: '$daysLeft days left',
      color: Theme.of(context).colorScheme.onSurfaceVariant
    );
  }

  DateTime _calculateNextDueDate(Bill bill) {
    if (bill.recurrenceType == 'monthly') {
      return DateTime(
        bill.dueDate.year,
        bill.dueDate.month + 1,
        bill.dueDate.day,
      );
    }
    if (bill.recurrenceType == 'weekly') {
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
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.06),
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
            child: SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refreshData,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                        children: [
                          _buildHeader(currentUser),
                          const SizedBox(height: 18),
                          _buildSummaryCards(),
                          const SizedBox(height: 22),
                          _buildUpcomingBillsSection(currentUser),
                          const SizedBox(height: 22),
                          _buildTransactionHeader(currentUser),
                          const SizedBox(height: 8),
                          _buildTransactionList(currentUser),
                        ],
                      ),
                    ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddTransactionScreen(),
                ),
              );
              if (result == true && currentUser != null && mounted) {
                await _refreshData();
              }
            },
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            label: Text(
              'Add Transaction',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            icon: const Icon(AppIcons.add),
          ),
        );
      },
    );
  }

  Widget _buildHeader(User? currentUser) {
    final amountText =
        NumberFormat.currency(locale: 'en_US', symbol: '').format(_balance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getGreeting(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentUser?.displayName ?? 'User',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: _refreshData,
              icon: const Icon(AppIcons.refresh),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              ),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.tertiary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Balance',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.90),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$_currencySymbol $amountText',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _HeroStatChip(
                      label: 'Income',
                      value:
                          '$_currencySymbol ${NumberFormat.compact().format(_totalIncome)}',
                      icon: AppIcons.arrow_downward,
                      iconColor: const Color(0xFFB2F5EA),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeroStatChip(
                      label: 'Expenses',
                      value:
                          '$_currencySymbol ${NumberFormat.compact().format(_totalExpenses)}',
                      icon: AppIcons.arrow_upward,
                      iconColor: const Color(0xFFFECACA),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        SummaryCard(
          title: 'Total Income',
          amount: _totalIncome,
          icon: AppIcons.trending_up,
          color: AppColors.success,
          currencySymbol: _currencySymbol,
        ),
        const SizedBox(height: 10),
        SummaryCard(
          title: 'Total Expenses',
          amount: _totalExpenses,
          icon: AppIcons.trending_down,
          color: AppColors.error,
          currencySymbol: _currencySymbol,
        ),
        const SizedBox(height: 10),
        SummaryCard(
          title: 'Available',
          amount: _balance,
          icon: AppIcons.account_balance,
          color: _balance >= 0 ? AppColors.primary : AppColors.warning,
          currencySymbol: _currencySymbol,
        ),
      ],
    );
  }

  Widget _buildTransactionHeader(User? currentUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Transactions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            TextButton(
              onPressed: () {
                if (currentUser == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllTransactionsScreen(),
                  ),
                ).then((_) => _refreshData());
              },
              child: Text(
                'See all',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              AppIcons.info_outline,
              size: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Swipe right to edit, left to delete',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpcomingBillsSection(User? currentUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Upcoming Bills',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AddBillScreen()),
                ).then((_) {
                  if (currentUser != null) {
                    _refreshData();
                  }
                });
              },
              child: Text(
                'Add Bill',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        if (_bills.isEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Text(
              'No upcoming bills. Tap "Add Bill" to create reminders.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          )
        else
          SizedBox(
            height: 246,
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8),
              scrollDirection: Axis.horizontal,
              itemCount: _bills.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final bill = _bills[index];
                final styling = _getBillStyling(bill.name);
                final status = _getBillStatus(bill.dueDate);
                final cardWidth = (MediaQuery.sizeOf(context).width * 0.74)
                    .clamp(250.0, 330.0);
                final isPaying =
                    bill.id != null && _payingBills.contains(bill.id!);

                return SizedBox(
                  width: cardWidth,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: status.color.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .shadow
                              .withValues(alpha: 0.14),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: styling.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(styling.icon,
                                  size: 18, color: styling.color),
                            ),
                            const Spacer(),
                            if (bill.isRecurring)
                              Icon(
                                LucideIcons.repeat,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: Icon(
                                LucideIcons.moreVertical,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
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
                              itemBuilder: (BuildContext context) => const [
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.pencil,
                                        size: 18,
                                        color: AppColors.primary,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.trash2,
                                        size: 18,
                                        color: AppColors.error,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          bill.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '$_currencySymbol ${NumberFormat('#,##0').format(bill.amount)}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: status.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            status.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: status.color,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: isPaying
                                ? null
                                : () async {
                                    if (currentUser == null ||
                                        bill.id == null) {
                                      return;
                                    }

                                    setState(() {
                                      _payingBills.add(bill.id!);
                                    });

                                    try {
                                      final billTransaction = model.Transaction(
                                        type: 'expense',
                                        amount: bill.amount,
                                        description: 'Paid bill: ${bill.name}',
                                        date: DateTime.now().toIso8601String(),
                                        categoryId:
                                            await dbHelper.getOrCreateCategory(
                                          'Bills',
                                          currentUser.uid,
                                          type: 'expense',
                                        ),
                                      );
                                      await dbHelper.addTransaction(
                                          billTransaction, currentUser.uid);

                                      if (bill.isRecurring) {
                                        final nextDueDate =
                                            _calculateNextDueDate(bill);
                                        final updatedBill =
                                            bill.copyWith(dueDate: nextDueDate);

                                        final notificationService =
                                            NotificationService();
                                        await notificationService
                                            .cancelNotification(bill.id!);
                                        await notificationService
                                            .scheduleBillNotification(
                                                updatedBill);

                                        await dbHelper.updateBill(
                                            updatedBill, currentUser.uid);
                                        if (mounted) {
                                          SnackbarHelper.showSuccess(
                                            context,
                                            'Recurring bill "${bill.name}" paid. Next due date set.',
                                          );
                                        }
                                      } else {
                                        final notificationService =
                                            NotificationService();
                                        await notificationService
                                            .cancelNotification(bill.id!);

                                        await dbHelper.deleteBill(
                                            bill.id!, currentUser.uid);
                                        if (mounted) {
                                          SnackbarHelper.showSuccess(
                                            context,
                                            'Bill "${bill.name}" marked as paid.',
                                          );
                                        }
                                      }

                                      _refreshData();
                                    } catch (e) {
                                      if (mounted) {
                                        SnackbarHelper.showError(
                                          context,
                                          'Failed to pay bill',
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _payingBills.remove(bill.id!);
                                        });
                                      }
                                    }
                                  },
                            icon: isPaying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(LucideIcons.check, size: 18),
                            label: Text(
                              isPaying ? 'Processing...' : 'Pay Bill',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                      ],
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
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(
          'No transactions yet. Add one to see activity.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
    }

    final currencyFormatter =
        NumberFormat.currency(locale: 'en_US', symbol: '');
    final recentTransactions = _transactions.take(10).toList();

    return Column(
      children: recentTransactions.map((transaction) {
        final isIncome = transaction.type == 'income';
        final amountColor = isIncome ? AppColors.success : AppColors.error;
        final amountPrefix = isIncome ? '+' : '-';

        return Dismissible(
          key: ValueKey(transaction.id),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (context) =>
                      TransactionDetailScreen(transaction: transaction),
                ),
              );
              if (result == true) {
                _refreshData();
              }
              return false;
            }
            return DialogHelper.showConfirmDialog(
              context: context,
              title: 'Confirm Deletion',
              message: 'Are you sure you want to delete this transaction?',
              confirmText: 'Delete',
              confirmColor: AppColors.error,
            );
          },
          onDismissed: (direction) {
            if (direction == DismissDirection.endToStart &&
                currentUser != null) {
              _deleteTransaction(transaction.id!, currentUser.uid);
            }
          },
          background: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const Icon(AppIcons.edit, color: Colors.white),
          ),
          secondaryBackground: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerRight,
            child: const Icon(AppIcons.delete, color: Colors.white),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: amountColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isIncome ? AppIcons.arrow_downward : AppIcons.arrow_upward,
                    color: amountColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.description.isNotEmpty
                            ? transaction.description
                            : transaction.type.capitalize(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        transaction.date.split('T')[0],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        math.min(MediaQuery.sizeOf(context).width * 0.34, 148),
                  ),
                  child: Text(
                    '$amountPrefix$_currencySymbol ${currencyFormatter.format(transaction.amount)}',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$currencySymbol ${currencyFormatter.format(amount)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _HeroStatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
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
