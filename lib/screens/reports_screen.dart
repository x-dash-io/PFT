import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/database_helper.dart';
import '../helpers/pdf_helper.dart';
import '../models/category.dart';
import '../models/transaction.dart' as model;
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<Map<String, dynamic>> _reportDataFuture;
  Map<String, dynamic> _cachedReportData = const {
    'transactions': <model.Transaction>[],
    'categoryMap': <int, Category>{},
  };
  final NumberFormat _compactFormatter = NumberFormat.compact();
  final NumberFormat _currencyFormatter =
      NumberFormat.currency(symbol: '', decimalDigits: 0);
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  String _selectedTimeFilter = 'month';
  String _currencySymbol = 'KSh';

  @override
  void initState() {
    super.initState();
    _reportDataFuture = _prepareReportData();
    _loadCurrencyPreference();
  }

  Future<void> _loadCurrencyPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currencySymbol = prefs.getString('currency') ?? 'KSh';
    });
  }

  Future<void> _refreshReports() async {
    setState(() {
      _reportDataFuture = _prepareReportData();
    });
    await _reportDataFuture;
  }

  Future<Map<String, dynamic>> _prepareReportData() async {
    if (_currentUser == null) {
      return {
        'transactions': <model.Transaction>[],
        'categoryMap': <int, Category>{},
      };
    }

    final dbHelper = DatabaseHelper();
    final transactions = await dbHelper.getTransactions(_currentUser.uid);
    final categories = await dbHelper.getCategories(_currentUser.uid);
    final categoryMap = <int, Category>{
      for (final category in categories)
        if (category.id != null) category.id!: category,
    };

    return {
      'transactions': transactions,
      'categoryMap': categoryMap,
    };
  }

  ({
    double income,
    double expenses,
    double netFlow,
    String tip,
    Color accentColor,
  }) _buildSummaryStats(
      List<model.Transaction> transactions, String timeFilter) {
    final periodTransactions =
        _filterTransactionsByPeriod(transactions, timeFilter);

    final income = periodTransactions
        .where((transaction) => transaction.type == 'income')
        .fold<double>(0, (sum, transaction) => sum + transaction.amount);
    final expenses = periodTransactions
        .where((transaction) => transaction.type == 'expense')
        .fold<double>(0, (sum, transaction) => sum + transaction.amount);
    final netFlow = income - expenses;

    final periodText = _periodPhrase(timeFilter);

    if (netFlow > 0) {
      return (
        income: income,
        expenses: expenses,
        netFlow: netFlow,
        tip:
            'Strong performance $periodText. You are operating with positive cash flow.',
        accentColor: AppColors.success,
      );
    }

    if (netFlow < 0) {
      return (
        income: income,
        expenses: expenses,
        netFlow: netFlow,
        tip:
            'Expenses exceeded income $periodText. Focus on your top spending categories.',
        accentColor: AppColors.error,
      );
    }

    return (
      income: income,
      expenses: expenses,
      netFlow: netFlow,
      tip:
          'Income matched expenses $periodText. Any extra income now will improve your cushion.',
      accentColor: AppColors.warning,
    );
  }

  List<_CashFlowPoint> _buildCashFlowSeries(
    List<model.Transaction> transactions,
    String filter,
  ) {
    final filtered = _filterTransactionsByPeriod(transactions, filter);
    final now = DateTime.now();
    final grouped = <DateTime, _CashFlowPoint>{};

    void ensureBucket(DateTime date) {
      final bucketDate = _bucketDateForFilter(date, filter);
      grouped.putIfAbsent(
        bucketDate,
        () => _CashFlowPoint(
          label: _bucketLabel(bucketDate, filter),
          bucketDate: bucketDate,
        ),
      );
    }

    switch (filter) {
      case 'week':
        final start = now.subtract(Duration(days: now.weekday - 1));
        for (int day = 0; day < 7; day++) {
          ensureBucket(DateTime(start.year, start.month, start.day + day));
        }
        break;
      case 'year':
        for (int month = 1; month <= now.month; month++) {
          ensureBucket(DateTime(now.year, month, 1));
        }
        break;
      case 'month':
      default:
        final start = DateTime(now.year, now.month, 1);
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        for (int day = 0; day < lastDay; day++) {
          ensureBucket(DateTime(start.year, start.month, start.day + day));
        }
        break;
    }

    for (final transaction in filtered) {
      DateTime parsed;
      try {
        parsed = DateTime.parse(transaction.date);
      } catch (_) {
        continue;
      }

      final bucketDate = _bucketDateForFilter(parsed, filter);
      final point = grouped.putIfAbsent(
        bucketDate,
        () => _CashFlowPoint(
          label: _bucketLabel(bucketDate, filter),
          bucketDate: bucketDate,
        ),
      );

      if (transaction.type == 'income') {
        point.income += transaction.amount;
      } else {
        point.expense += transaction.amount;
      }
    }

    final sorted = grouped.values.toList()
      ..sort((a, b) => a.bucketDate.compareTo(b.bucketDate));

    if (filter == 'month') {
      final today = DateTime(now.year, now.month, now.day);
      return sorted.where((point) => !point.bucketDate.isAfter(today)).toList();
    }

    return sorted;
  }

  DateTime _bucketDateForFilter(DateTime date, String filter) {
    switch (filter) {
      case 'week':
      case 'month':
        return DateTime(date.year, date.month, date.day);
      case 'year':
        return DateTime(date.year, date.month, 1);
      default:
        return DateTime(date.year, date.month, date.day);
    }
  }

  String _bucketLabel(DateTime date, String filter) {
    switch (filter) {
      case 'week':
        return DateFormat('E').format(date);
      case 'year':
        return DateFormat('MMM').format(date);
      case 'month':
      default:
        return DateFormat('d').format(date);
    }
  }

  List<model.Transaction> _filterTransactionsByPeriod(
    List<model.Transaction> transactions,
    String filter,
  ) {
    final now = DateTime.now();
    DateTime startDate;

    switch (filter) {
      case 'week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        break;
      case 'year':
        startDate = DateTime(now.year, 1, 1);
        break;
      case 'month':
      default:
        startDate = DateTime(now.year, now.month, 1);
        break;
    }

    return transactions.where((transaction) {
      try {
        return DateTime.parse(transaction.date)
            .isAfter(startDate.subtract(const Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }).toList();
  }

  Map<String, double> _prepareExpenseData(
    List<model.Transaction> transactions,
    Map<int, Category> categoryMap,
  ) {
    final expenseData = <String, double>{};
    for (final transaction
        in transactions.where((item) => item.type == 'expense')) {
      if (transaction.categoryId == null) {
        expenseData.update(
          'Uncategorized',
          (value) => value + transaction.amount,
          ifAbsent: () => transaction.amount,
        );
        continue;
      }

      final category = categoryMap[transaction.categoryId];
      final categoryName = category?.name ?? 'Uncategorized';
      expenseData.update(
        categoryName,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }
    return expenseData;
  }

  String _periodPhrase(String filter) {
    switch (filter) {
      case 'week':
        return 'this week';
      case 'year':
        return 'this year';
      case 'month':
      default:
        return 'this month';
    }
  }

  String _periodLabel(String filter) {
    switch (filter) {
      case 'week':
        return 'Weekly';
      case 'year':
        return 'Yearly';
      case 'month':
      default:
        return 'Monthly';
    }
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _formatAmount(double value, {bool compact = false}) {
    final formatted = compact
        ? _compactFormatter.format(value)
        : _currencyFormatter.format(value);
    return '$_currencySymbol $formatted';
  }

  Future<void> _exportReport(
    List<model.Transaction> periodTransactions,
    Map<int, Category> categoryMap,
  ) async {
    if (_currentUser == null) return;

    final dateText = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName = 'Ledgerlite_Report_$dateText.pdf';

    await PdfHelper.generateAndSharePdf(
      periodTransactions,
      _currentUser.displayName ?? 'User',
      fileName,
      categoryMap: categoryMap,
      timeFilter: _selectedTimeFilter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topGradientColor =
        (isDark ? AppColors.darkPrimary : AppColors.primary).withValues(
      alpha: isDark ? 0.18 : 0.08,
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              topGradientColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _reportDataFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                _cachedReportData = snapshot.data!;
              }

              final isWaiting =
                  snapshot.connectionState == ConnectionState.waiting;
              final reportData = snapshot.data ?? _cachedReportData;
              final transactions =
                  reportData['transactions'] as List<model.Transaction>? ??
                      <model.Transaction>[];
              final categoryMap =
                  reportData['categoryMap'] as Map<int, Category>? ??
                      <int, Category>{};

              if (snapshot.hasError) {
                if (transactions.isNotEmpty) {
                  return _buildReportsContent(
                    transactions: transactions,
                    categoryMap: categoryMap,
                  );
                }
                return _ErrorState(
                  message: 'Could not load report data',
                  details: snapshot.error.toString(),
                  onRetry: _refreshReports,
                );
              }

              if (transactions.isEmpty && isWaiting) {
                return _buildReportsLoadingSkeleton();
              }

              return Stack(
                children: [
                  _buildReportsContent(
                    transactions: transactions,
                    categoryMap: categoryMap,
                  ),
                  if (isWaiting)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildReportsLoadingSkeleton() {
    return RefreshIndicator(
      onRefresh: _refreshReports,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildLoadingBlock(height: 54, radius: 14),
          const SizedBox(height: 16),
          _buildLoadingBlock(height: 170, radius: 22),
          const SizedBox(height: 16),
          _buildLoadingBlock(height: 124, radius: 16),
          const SizedBox(height: 12),
          _buildLoadingBlock(height: 124, radius: 16),
          const SizedBox(height: 20),
          _buildLoadingBlock(height: 318, radius: 18),
          const SizedBox(height: 22),
          _buildLoadingBlock(height: 360, radius: 18),
          const SizedBox(height: 28),
          _buildLoadingBlock(height: 54, radius: 16),
        ],
      ),
    );
  }

  Widget _buildLoadingBlock({
    required double height,
    double? width,
    double radius = 14,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.darkCardBackground
        : Theme.of(context).colorScheme.surface;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
    );
  }

  Widget _buildReportsContent({
    required List<model.Transaction> transactions,
    required Map<int, Category> categoryMap,
  }) {
    if (transactions.isEmpty) {
      return _buildEmptyState();
    }

    final periodTransactions =
        _filterTransactionsByPeriod(transactions, _selectedTimeFilter);
    final summary = _buildSummaryStats(transactions, _selectedTimeFilter);
    final expenseData = _prepareExpenseData(periodTransactions, categoryMap);
    final cashFlowSeries =
        _buildCashFlowSeries(transactions, _selectedTimeFilter);

    final expenseTransactionCount = periodTransactions
        .where((transaction) => transaction.type == 'expense')
        .length;
    final averageExpense = expenseTransactionCount == 0
        ? 0.0
        : summary.expenses / expenseTransactionCount;

    final savingsRate = summary.income == 0
        ? 0.0
        : ((summary.netFlow / summary.income) * 100).clamp(-999.0, 999.0);

    return RefreshIndicator(
      onRefresh: _refreshReports,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildFilterControl(),
          const SizedBox(height: 16),
          _ReportHeroCard(
            periodLabel: _periodLabel(_selectedTimeFilter),
            value: _formatAmount(summary.netFlow),
            subtitle: summary.tip,
            transactionCount: periodTransactions.length,
            accentColor: summary.accentColor,
          ),
          const SizedBox(height: 16),
          _buildKpiGrid(
            income: summary.income,
            expenses: summary.expenses,
            transactionCount: periodTransactions.length,
            averageExpense: averageExpense,
            savingsRate: savingsRate,
          ),
          const SizedBox(height: 20),
          _buildCashFlowCard(cashFlowSeries),
          const SizedBox(height: 22),
          _buildExpenseBreakdown(expenseData, categoryMap),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _exportReport(periodTransactions, categoryMap),
              icon: const Icon(AppIcons.picture_as_pdf),
              label: Text(
                'Export ${_capitalize(_selectedTimeFilter)} PDF',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkNeutralLight : AppColors.neutralMedium;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Track performance and export your financial summary.',
                style: textTheme.bodyMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: _refreshReports,
          icon: const Icon(AppIcons.refresh),
          style: IconButton.styleFrom(
            foregroundColor: AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          ),
          tooltip: 'Refresh reports',
        ),
      ],
    );
  }

  Widget _buildFilterControl() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;
    final backgroundColor =
        isDark ? AppColors.darkCardBackground : AppColors.white;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment<String>(value: 'week', label: Text('Week')),
          ButtonSegment<String>(value: 'month', label: Text('Month')),
          ButtonSegment<String>(value: 'year', label: Text('Year')),
        ],
        selected: {_selectedTimeFilter},
        showSelectedIcon: false,
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide.none),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        onSelectionChanged: (selection) {
          setState(() {
            _selectedTimeFilter = selection.first;
          });
        },
      ),
    );
  }

  Widget _buildKpiGrid({
    required double income,
    required double expenses,
    required int transactionCount,
    required double averageExpense,
    required double savingsRate,
  }) {
    final savingsColor = savingsRate >= 0 ? AppColors.success : AppColors.error;
    final savingsPrefix = savingsRate >= 0 ? '+' : '';

    final cards = [
      _KpiCardData(
        label: 'Income',
        value: _formatAmount(income, compact: true),
        icon: AppIcons.arrow_downward,
        color: AppColors.success,
      ),
      _KpiCardData(
        label: 'Expenses',
        value: _formatAmount(expenses, compact: true),
        icon: AppIcons.arrow_upward,
        color: AppColors.error,
      ),
      _KpiCardData(
        label: 'Savings Rate',
        value: '$savingsPrefix${savingsRate.toStringAsFixed(1)}%',
        icon: AppIcons.analytics,
        color: savingsColor,
      ),
      _KpiCardData(
        label: 'Avg Expense',
        value: _formatAmount(averageExpense, compact: true),
        icon: AppIcons.money,
        color: AppColors.warning,
      ),
      _KpiCardData(
        label: 'Transactions',
        value: transactionCount.toString(),
        icon: AppIcons.receipt,
        color: AppColors.info,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860
            ? 3
            : constraints.maxWidth >= 540
                ? 2
                : 1;
        const spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: cardWidth,
                child: _KpiStatCard(data: card),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCashFlowCard(List<_CashFlowPoint> series) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkCardBackground : AppColors.white;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    final hasData =
        series.any((point) => point.income > 0 || point.expense > 0);
    final xStep = math.max(1, (series.length / 5).ceil());

    if (!hasData) {
      return _SectionCard(
        icon: AppIcons.insert_chart_outlined,
        title: 'Cash Flow Trend',
        subtitle:
            'Income and expenses for ${_periodPhrase(_selectedTimeFilter)}',
        child: SizedBox(
          height: 220,
          child: Center(
            child: Text(
              'No activity yet for this period.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      );
    }

    final maxMagnitude = series
        .map((point) => math.max(point.income, point.expense))
        .fold<double>(0, (current, value) => value > current ? value : current);
    final effectiveMaxMagnitude =
        maxMagnitude <= 0 ? 100.0 : (maxMagnitude * 1.18) + 80;
    final yInterval = math.max(effectiveMaxMagnitude / 4, 50.0);
    final maxY = effectiveMaxMagnitude;
    final peakIncome = series
        .map((point) => point.income)
        .fold<double>(0, (current, value) => value > current ? value : current);
    final peakExpense = series
        .map((point) => point.expense)
        .fold<double>(0, (current, value) => value > current ? value : current);

    final incomeSpots = [
      for (int index = 0; index < series.length; index++)
        FlSpot(index.toDouble(), series[index].income),
    ];
    final expenseSpots = [
      for (int index = 0; index < series.length; index++)
        FlSpot(index.toDouble(), series[index].expense),
    ];

    return _SectionCard(
      icon: AppIcons.insert_chart_outlined,
      title: 'Cash Flow Trend',
      subtitle: 'Income and expenses for ${_periodPhrase(_selectedTimeFilter)}',
      trailing: _PeriodPill(label: _periodLabel(_selectedTimeFilter)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LegendChip(
                label:
                    'Peak Income ${_formatAmount(peakIncome, compact: true)}',
                color: AppColors.success,
                icon: AppIcons.arrow_downward,
              ),
              _LegendChip(
                label:
                    'Peak Expense ${_formatAmount(peakExpense, compact: true)}',
                color: AppColors.error,
                icon: AppIcons.arrow_upward,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 328,
            padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                baselineY: 0,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => isDark
                        ? AppColors.darkNeutralDark
                        : AppColors.neutralDark,
                    tooltipRoundedRadius: 10,
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final isIncomeLine = spot.barIndex == 0;
                        final label = isIncomeLine ? 'Income' : 'Expense';
                        final amount = spot.y;
                        return LineTooltipItem(
                          '$label\n${_formatAmount(amount, compact: true)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: borderColor,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: xStep.toDouble(),
                      getTitlesWidget: (value, _) {
                        final index = value.toInt();
                        if (index < 0 || index >= series.length) {
                          return const SizedBox.shrink();
                        }
                        final shouldRender =
                            index % xStep == 0 || index == series.length - 1;
                        if (!shouldRender) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            series[index].label,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 58,
                      interval: yInterval,
                      getTitlesWidget: (value, _) {
                        if (value < 0) {
                          return const SizedBox.shrink();
                        }
                        final display = _compactFormatter.format(value);
                        return Text(
                          display,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: borderColor, width: 1.5),
                    bottom: BorderSide(color: borderColor, width: 1.5),
                    right: BorderSide.none,
                    top: BorderSide.none,
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: incomeSpots,
                    isCurved: true,
                    color: AppColors.success,
                    barWidth: 3.4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.success.withValues(alpha: 0.22),
                          AppColors.success.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                  LineChartBarData(
                    spots: expenseSpots,
                    isCurved: true,
                    color: AppColors.error,
                    barWidth: 3.4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.error.withValues(alpha: 0.2),
                          AppColors.error.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LegendChip(
                label: 'Income',
                color: AppColors.success,
                icon: AppIcons.arrow_downward,
              ),
              _LegendChip(
                label: 'Expenses',
                color: AppColors.error,
                icon: AppIcons.arrow_upward,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseBreakdown(
    Map<String, double> expenseData,
    Map<int, Category> categoryMap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    final totalExpenses =
        expenseData.values.fold<double>(0, (sum, amount) => sum + amount);

    if (totalExpenses == 0) {
      return _SectionCard(
        icon: AppIcons.category,
        title: 'Expense Breakdown',
        subtitle:
            'Category distribution for ${_periodPhrase(_selectedTimeFilter)}',
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              'No expense records available in this period.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      );
    }

    final sortedEntries = expenseData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    var pieEntries = sortedEntries;
    if (sortedEntries.length > 6) {
      final otherTotal = sortedEntries
          .skip(5)
          .fold<double>(0, (sum, entry) => sum + entry.value);
      pieEntries = [
        ...sortedEntries.take(5),
        MapEntry('Other', otherTotal),
      ];
    }

    final colorMap = <String, Color>{
      for (final entry in pieEntries)
        entry.key: _categoryColor(
          entry.key,
          categoryMap,
          isDark: isDark,
        ),
    };

    final topCategory = sortedEntries.first;
    final topCategoryShare = (topCategory.value / totalExpenses) * 100;

    return _SectionCard(
      icon: AppIcons.category,
      title: 'Expense Breakdown',
      subtitle:
          'Category distribution for ${_periodPhrase(_selectedTimeFilter)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  AppIcons.trending_down,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${topCategory.key} is your largest expense '
                    '(${topCategoryShare.toStringAsFixed(1)}%).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final useRowLayout = constraints.maxWidth >= 680;

              final chartRadius = useRowLayout ? 86.0 : 92.0;
              final chart = Container(
                height: useRowLayout ? 270 : 286,
                width: useRowLayout ? 286 : double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.72),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 50,
                    sectionsSpace: 3,
                    centerSpaceColor: Theme.of(context).colorScheme.surface,
                    sections: [
                      for (final entry in pieEntries)
                        PieChartSectionData(
                          color: colorMap[entry.key],
                          value: entry.value,
                          radius: chartRadius,
                          title:
                              '${((entry.value / totalExpenses) * 100).round()}%',
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              );

              final legend = Column(
                children: [
                  for (final entry in sortedEntries.take(6))
                    _CategoryBreakdownRow(
                      label: entry.key,
                      color: _categoryColor(entry.key, categoryMap,
                          isDark: isDark),
                      amount: _formatAmount(entry.value, compact: true),
                      percent:
                          '${((entry.value / totalExpenses) * 100).toStringAsFixed(1)}%',
                    ),
                ],
              );

              if (!useRowLayout) {
                return Column(
                  children: [
                    chart,
                    const SizedBox(height: 20),
                    legend,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chart,
                  const SizedBox(width: 24),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Color _categoryColor(
    String categoryName,
    Map<int, Category> categoryMap, {
    required bool isDark,
  }) {
    for (final category in categoryMap.values) {
      if (category.name.toLowerCase() == categoryName.toLowerCase() &&
          category.colorValue != null) {
        final resolved = Color(category.colorValue!);
        return resolved.withValues(alpha: isDark ? 0.95 : 0.90);
      }
    }

    const fallbackPalette = [
      AppColors.primary,
      AppColors.tertiary,
      AppColors.secondary,
      AppColors.success,
      AppColors.warning,
      AppColors.error,
      AppColors.info,
    ];

    final fallback =
        fallbackPalette[categoryName.hashCode.abs() % fallbackPalette.length];
    return fallback.withValues(alpha: isDark ? 0.95 : 0.85);
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;
    final background = isDark ? AppColors.darkCardBackground : AppColors.white;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  AppIcons.insert_chart_outlined,
                  size: 30,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No report data yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Add transactions to unlock insights, charts, and PDF exports.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportHeroCard extends StatelessWidget {
  final String periodLabel;
  final String value;
  final String subtitle;
  final int transactionCount;
  final Color accentColor;

  const _ReportHeroCard({
    required this.periodLabel,
    required this.value,
    required this.subtitle,
    required this.transactionCount,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            Color.lerp(accentColor, AppColors.primary, 0.5) ??
                AppColors.primary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  AppIcons.stacked_line_chart,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$periodLabel Net Flow',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroInfoPill(
                label: '$transactionCount transactions',
                icon: AppIcons.receipt,
              ),
              _HeroInfoPill(
                label: periodLabel,
                icon: AppIcons.calendar_today,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroInfoPill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _HeroInfoPill({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _KpiCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _KpiStatCard extends StatelessWidget {
  final _KpiCardData data;

  const _KpiStatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;
    final surfaceColor =
        isDark ? AppColors.darkCardBackground : AppColors.white;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, size: 16, color: data.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;
    final surfaceColor =
        isDark ? AppColors.darkCardBackground : AppColors.white;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  final String label;

  const _PeriodPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _LegendChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownRow extends StatelessWidget {
  final String label;
  final Color color;
  final String amount;
  final String percent;

  const _CategoryBreakdownRow({
    required this.label,
    required this.color,
    required this.amount,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            amount,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 10),
          Text(
            percent,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final String details;
  final Future<void> Function() onRetry;

  const _ErrorState({
    required this.message,
    required this.details,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.error_outline,
                color: AppColors.error, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              details,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashFlowPoint {
  final String label;
  final DateTime bucketDate;
  double income = 0;
  double expense = 0;

  _CashFlowPoint({
    required this.label,
    required this.bucketDate,
  });
}
