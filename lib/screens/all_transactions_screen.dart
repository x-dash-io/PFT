import 'package:flutter/material.dart';
import 'package:personal_finance_tracker/theme/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../helpers/database_helper.dart';
import '../helpers/date_picker_helper.dart';
import '../models/category.dart';
import '../models/transaction.dart' as model;
import 'transaction_detail_screen.dart';
import '../theme/app_theme.dart';
import '../theme/transaction_visuals.dart';

class AllTransactionsScreen extends StatefulWidget {
  const AllTransactionsScreen({super.key});

  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen> {
  final dbHelper = DatabaseHelper();
  List<model.Transaction> _allTransactions = [];
  List<model.Transaction> _filteredTransactions = [];
  List<Category> _allCategories = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // State variables for filter values
  int? _filterCategoryId;
  String? _filterType;
  DateTimeRange? _filterDateRange;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(_applyAllFilters);
  }

  Future<void> _loadInitialData() async {
    if (_currentUser == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    // Load both transactions and categories
    final transactions = await dbHelper.getTransactions(_currentUser.uid);
    final categories = await dbHelper.getCategories(_currentUser.uid);

    if (!mounted) return;
    setState(() {
      _allTransactions = transactions;
      _allCategories = categories;
      _isLoading = false;
    });
    _applyAllFilters();
  }

  /// Applies all active filters (search, category, type, date range) to the transaction list
  void _applyAllFilters() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      _filteredTransactions = _allTransactions.where((transaction) {
        // Search filter
        final descriptionMatch =
            transaction.description.toLowerCase().contains(query);
        final amountMatch = transaction.amount.toString().contains(query);
        final searchMatch = query.isEmpty || descriptionMatch || amountMatch;

        // Category filter
        final categoryMatch = _filterCategoryId == null ||
            transaction.categoryId == _filterCategoryId;

        // Type filter
        final typeMatch =
            _filterType == null || transaction.type == _filterType;

        // Date range filter
        final dateMatch = _filterDateRange == null ||
            (DateTime.parse(transaction.date)
                    .isAfter(_filterDateRange!.start) &&
                DateTime.parse(transaction.date).isBefore(
                    _filterDateRange!.end.add(const Duration(days: 1))));

        return searchMatch && categoryMatch && typeMatch && dateMatch;
      }).toList();
    });
  }

  String? _categoryNameFor(int? categoryId) {
    if (categoryId == null) return null;
    for (final category in _allCategories) {
      if (category.id == categoryId) return category.name;
    }
    return null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Displays the filter bottom sheet for transaction filtering
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        // Use StatefulBuilder to manage the state within the bottom sheet
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filter Transactions',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),

                  // Filter by Type
                  DropdownButtonFormField<String>(
                    initialValue: _filterType,
                    hint: const Text('Filter by Type'),
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'income', child: Text('Income')),
                      DropdownMenuItem(
                          value: 'expense', child: Text('Expense')),
                    ],
                    onChanged: (value) =>
                        setModalState(() => _filterType = value),
                  ),
                  const SizedBox(height: 16),

                  // Filter by Category
                  DropdownButtonFormField<int>(
                    initialValue: _filterCategoryId,
                    hint: const Text('Filter by Category'),
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                    items: _allCategories
                        .map((cat) => DropdownMenuItem(
                              value: cat.id,
                              child: Text(
                                cat.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setModalState(() => _filterCategoryId = value),
                  ),
                  const SizedBox(height: 16),

                  // Filter by Date Range
                  ListTile(
                    title: Text(
                      _filterDateRange == null
                          ? 'Filter by Date'
                          : '${DateFormat.yMd().format(_filterDateRange!.start)} - ${DateFormat.yMd().format(_filterDateRange!.end)}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    trailing: const Icon(AppIcons.calendar_today),
                    onTap: () async {
                      final picked =
                          await DatePickerHelper.showModernDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: _filterDateRange,
                      );
                      if (picked != null) {
                        setModalState(() => _filterDateRange = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            _filterCategoryId = null;
                            _filterType = null;
                            _filterDateRange = null;
                          });
                          // Also clear the main state
                          setState(() {
                            _filterCategoryId = null;
                            _filterType = null;
                            _filterDateRange = null;
                          });
                          _applyAllFilters();
                          Navigator.pop(context);
                        },
                        child: const Text('Reset'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          // Apply the filters to the main screen's state
                          setState(() {});
                          _applyAllFilters();
                          Navigator.pop(context);
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter =
        NumberFormat.currency(locale: 'en_US', symbol: 'KSh ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Transactions'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: 'Filter Transactions',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search by description or amount',
                prefixIcon: const Icon(AppIcons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          Expanded(
            child: _isLoading && _allTransactions.isEmpty
                ? _buildTransactionsLoadingList()
                : _filteredTransactions.isEmpty
                    ? Center(
                        child: Text(
                          _allTransactions.isEmpty
                              ? 'No transactions yet.'
                              : 'No transactions match your filters.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredTransactions.length,
                        itemBuilder: (context, index) {
                          final transaction = _filteredTransactions[index];
                          final isIncome = transaction.type == 'income';
                          final amountColor =
                              isIncome ? AppColors.success : AppColors.error;
                          final amountPrefix = isIncome ? '+' : '-';
                          final categoryName =
                              _categoryNameFor(transaction.categoryId);
                          final visual = resolveTransactionVisual(
                            type: transaction.type,
                            description: transaction.description,
                            categoryName: categoryName,
                          );
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;
                          final baseSurface =
                              Theme.of(context).colorScheme.surface;
                          final cardStart = Color.lerp(
                                baseSurface,
                                visual.accent,
                                isDark ? 0.2 : 0.08,
                              ) ??
                              baseSurface;
                          final cardEnd = Color.lerp(
                                baseSurface,
                                amountColor,
                                isDark ? 0.12 : 0.04,
                              ) ??
                              baseSurface;

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 6.0,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [cardStart, cardEnd],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: visual.accent
                                    .withValues(alpha: isDark ? 0.34 : 0.22),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: visual.accent
                                      .withValues(alpha: isDark ? 0.18 : 0.11),
                                  blurRadius: 11,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  final result =
                                      await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          TransactionDetailScreen(
                                        transaction: transaction,
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    _loadInitialData();
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(9),
                                        decoration: BoxDecoration(
                                          color: visual.accent
                                              .withValues(alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: visual.accent
                                                .withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Icon(
                                          visual.icon,
                                          color: visual.accent,
                                          size: 19,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              transaction.description.isEmpty
                                                  ? transaction.type
                                                      .capitalize()
                                                  : transaction.description,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              categoryName != null
                                                  ? '${transaction.date.split('T')[0]} • $categoryName'
                                                  : transaction.date
                                                      .split('T')[0],
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: (MediaQuery.sizeOf(context)
                                                      .width *
                                                  0.38)
                                              .clamp(110.0, 160.0)
                                              .toDouble(),
                                        ),
                                        child: Text(
                                          '$amountPrefix${currencyFormatter.format(transaction.amount)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                color: amountColor,
                                                fontWeight: FontWeight.w800,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.end,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsLoadingList() {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          height: 76,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        );
      },
    );
  }
}

extension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
