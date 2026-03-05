/// PDF helper utility for generating and sharing PDF reports
///
/// Creates enterprise-style financial reports with branded typography,
/// Lucide iconography, summary analytics, and structured data tables.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/category.dart';
import '../models/transaction.dart' as model;
import '../theme/app_icons.dart';

class PdfHelper {
  static final PdfColor _primary = PdfColor.fromHex('#1F6FEB');
  static final PdfColor _primarySoft = PdfColor.fromHex('#EAF2FF');
  static final PdfColor _ink = PdfColor.fromHex('#111827');
  static final PdfColor _muted = PdfColor.fromHex('#6B7280');
  static final PdfColor _border = PdfColor.fromHex('#DCE3EE');
  static final PdfColor _surface = PdfColor.fromHex('#F8FAFC');
  static final PdfColor _success = PdfColor.fromHex('#10B981');
  static final PdfColor _successSoft = PdfColor.fromHex('#E7F9F2');
  static final PdfColor _danger = PdfColor.fromHex('#EF4444');
  static final PdfColor _dangerSoft = PdfColor.fromHex('#FDECEC');
  static final PdfColor _warning = PdfColor.fromHex('#FF9F1C');
  static final PdfColor _warningSoft = PdfColor.fromHex('#FFF4E6');

  /// Generates and shares a PDF report for the given transactions and user.
  static Future<void> generateAndSharePdf(
    List<model.Transaction> transactions,
    String userName,
    String fileName, {
    Map<int, Category>? categoryMap,
    String timeFilter = 'month',
  }) async {
    final pdf = pw.Document();
    final fonts = await _loadFonts();
    final sortedTransactions = List<model.Transaction>.from(transactions)
      ..sort(
          (a, b) => _parseDateSafe(b.date).compareTo(_parseDateSafe(a.date)));
    final metrics = _computeMetrics(sortedTransactions, categoryMap);
    final periodLabel = _periodLabel(timeFilter);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(30, 24, 30, 26),
          theme: pw.ThemeData.withFont(
            base: fonts.regular,
            bold: fonts.bold,
            icons: fonts.icons,
            fontFallback: [fonts.icons],
          ),
        ),
        header: (context) => _buildPageHeader(periodLabel, fonts),
        footer: (context) =>
            _buildPageFooter(context.pageNumber, context.pagesCount, fonts),
        build: (context) => [
          _buildHeroSection(userName, periodLabel, metrics, fonts),
          pw.SizedBox(height: 14),
          _buildKpiSection(metrics, fonts),
          pw.SizedBox(height: 14),
          _buildExecutiveInsights(metrics, fonts),
          pw.SizedBox(height: 14),
          _buildCategoryBreakdown(metrics, fonts),
          pw.SizedBox(height: 14),
          _buildTransactionTable(sortedTransactions, categoryMap, fonts),
          pw.SizedBox(height: 14),
          _buildGovernanceNotes(metrics, fonts),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
  }

  static Future<_PdfFonts> _loadFonts() async {
    final lucideBytes =
        await rootBundle.load('packages/lucide_icons/assets/lucide.ttf');
    final icons = pw.Font.ttf(lucideBytes);

    try {
      final regular = await PdfGoogleFonts.manropeRegular();
      final semiBold = await PdfGoogleFonts.manropeSemiBold();
      final bold = await PdfGoogleFonts.manropeBold();
      return _PdfFonts(
        regular: regular,
        semiBold: semiBold,
        bold: bold,
        icons: icons,
      );
    } catch (_) {
      return _PdfFonts(
        regular: pw.Font.helvetica(),
        semiBold: pw.Font.helveticaBold(),
        bold: pw.Font.helveticaBold(),
        icons: icons,
      );
    }
  }

  static pw.Widget _buildPageHeader(String periodLabel, _PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            children: [
              _icon(AppIcons.account_balance_wallet.codePoint, fonts,
                  color: _primary, size: 13),
              pw.SizedBox(width: 6),
              pw.Text(
                'Ledgerlite Enterprise Financial Report',
                style: pw.TextStyle(
                  font: fonts.semiBold,
                  fontSize: 10,
                  color: _ink,
                ),
              ),
            ],
          ),
          pw.Text(
            periodLabel,
            style:
                pw.TextStyle(font: fonts.semiBold, fontSize: 9, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter(
    int pageNumber,
    int totalPages,
    _PdfFonts fonts,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Confidential: Internal financial analytics for account owner',
            style:
                pw.TextStyle(font: fonts.regular, fontSize: 8, color: _muted),
          ),
          pw.Text(
            'Page $pageNumber/$totalPages',
            style:
                pw.TextStyle(font: fonts.semiBold, fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildHeroSection(
    String userName,
    String periodLabel,
    _ReportMetrics metrics,
    _PdfFonts fonts,
  ) {
    final coverageText = metrics.dateFrom == null
        ? 'No transaction coverage available'
        : '${DateFormat('dd MMM yyyy').format(metrics.dateFrom!)} - ${DateFormat('dd MMM yyyy').format(metrics.dateTo!)}';

    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: _primarySoft,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    _icon(AppIcons.analytics.codePoint, fonts,
                        color: _primary, size: 16),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      'Executive Financial Snapshot',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 18,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Prepared for $userName',
                  style: pw.TextStyle(
                      font: fonts.semiBold, fontSize: 11, color: _ink),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '$periodLabel • Coverage: $coverageText',
                  style: pw.TextStyle(
                      font: fonts.regular, fontSize: 9, color: _muted),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Generated on ${DateFormat('dd MMM yyyy • hh:mm a').format(DateTime.now())}',
                  style: pw.TextStyle(
                      font: fonts.regular, fontSize: 9, color: _muted),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Container(
            width: 132,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: _border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Health Score',
                  style: pw.TextStyle(
                      font: fonts.semiBold, fontSize: 9, color: _muted),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${metrics.healthScore}/100',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 18,
                    color: _scoreColor(metrics.healthScore),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  metrics.healthLabel,
                  style: pw.TextStyle(
                    font: fonts.semiBold,
                    fontSize: 10,
                    color: _scoreColor(metrics.healthScore),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildKpiSection(_ReportMetrics metrics, _PdfFonts fonts) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(
            'Performance KPIs', AppIcons.stacked_line_chart.codePoint, fonts),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            _kpiCard(
              title: 'Total Income',
              value: 'KSh ${_formatCompact(metrics.totalIncome)}',
              subtitle: '${metrics.incomeCount} income entries',
              iconCodePoint: AppIcons.arrow_downward.codePoint,
              textColor: _success,
              tileColor: _successSoft,
              fonts: fonts,
            ),
            pw.SizedBox(width: 10),
            _kpiCard(
              title: 'Total Expenses',
              value: 'KSh ${_formatCompact(metrics.totalExpenses)}',
              subtitle: '${metrics.expenseCount} expense entries',
              iconCodePoint: AppIcons.arrow_upward.codePoint,
              textColor: _danger,
              tileColor: _dangerSoft,
              fonts: fonts,
            ),
            pw.SizedBox(width: 10),
            _kpiCard(
              title: 'Net Position',
              value: 'KSh ${_formatCompact(metrics.balance)}',
              subtitle: metrics.balance >= 0
                  ? 'Positive net cashflow'
                  : 'Deficit detected',
              iconCodePoint: AppIcons.account_balance.codePoint,
              textColor: metrics.balance >= 0 ? _primary : _warning,
              tileColor: metrics.balance >= 0 ? _primarySoft : _warningSoft,
              fonts: fonts,
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            _kpiCard(
              title: 'Savings Rate',
              value: '${metrics.savingsRate.toStringAsFixed(1)}%',
              subtitle: 'Net / Income',
              iconCodePoint: AppIcons.trending_up.codePoint,
              textColor: _scoreColor(metrics.healthScore),
              tileColor: _surface,
              fonts: fonts,
            ),
            pw.SizedBox(width: 10),
            _kpiCard(
              title: 'Avg Ticket',
              value: 'KSh ${_formatCompact(metrics.averageTransaction)}',
              subtitle: 'Average per transaction',
              iconCodePoint: AppIcons.receipt_long_outlined.codePoint,
              textColor: _primary,
              tileColor: _surface,
              fonts: fonts,
            ),
            pw.SizedBox(width: 10),
            _kpiCard(
              title: 'Transactions',
              value: '${metrics.transactionCount}',
              subtitle: 'Total recorded entries',
              iconCodePoint: AppIcons.filter_list.codePoint,
              textColor: _primary,
              tileColor: _surface,
              fonts: fonts,
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required int iconCodePoint,
    required PdfColor textColor,
    required PdfColor tileColor,
    required _PdfFonts fonts,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: _border),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: pw.BoxDecoration(
                color: tileColor,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: _icon(iconCodePoint, fonts, color: textColor, size: 11),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              title,
              style: pw.TextStyle(
                  font: fonts.semiBold, fontSize: 9, color: _muted),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                  font: fonts.bold, fontSize: 13, color: textColor),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle,
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 8.2, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildExecutiveInsights(
    _ReportMetrics metrics,
    _PdfFonts fonts,
  ) {
    final recommendations = _buildRecommendations(metrics);

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Enterprise Insights',
              AppIcons.insights_outlined.codePoint, fonts),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 120,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _border),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Burn Rate',
                      style: pw.TextStyle(
                          font: fonts.semiBold, fontSize: 9, color: _muted),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${metrics.burnRate.toStringAsFixed(1)}%',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 16,
                        color: metrics.burnRate <= 80 ? _success : _danger,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      metrics.burnRate <= 100
                          ? 'within income'
                          : 'above income',
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 8.5, color: _muted),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: recommendations
                      .map((item) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 6),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                _icon(AppIcons.check_circle.codePoint, fonts,
                                    color: _primary, size: 10),
                                pw.SizedBox(width: 6),
                                pw.Expanded(
                                  child: pw.Text(
                                    item,
                                    style: pw.TextStyle(
                                      font: fonts.regular,
                                      fontSize: 9.4,
                                      color: _ink,
                                      lineSpacing: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCategoryBreakdown(
    _ReportMetrics metrics,
    _PdfFonts fonts,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(
            'Category Performance', AppIcons.analytics.codePoint, fonts),
        pw.SizedBox(height: 10),
        _buildCategoryTable(
          title: 'Expense Categories',
          iconCodePoint: AppIcons.trending_down.codePoint,
          entries: metrics.expenseByCategory.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)),
          total: metrics.totalExpenses,
          accent: _danger,
          fonts: fonts,
        ),
        pw.SizedBox(height: 10),
        _buildCategoryTable(
          title: 'Income Categories',
          iconCodePoint: AppIcons.trending_up.codePoint,
          entries: metrics.incomeByCategory.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)),
          total: metrics.totalIncome,
          accent: _success,
          fonts: fonts,
        ),
      ],
    );
  }

  static pw.Widget _buildCategoryTable({
    required String title,
    required int iconCodePoint,
    required List<MapEntry<String, double>> entries,
    required double total,
    required PdfColor accent,
    required _PdfFonts fonts,
  }) {
    final topEntries = entries.take(8).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              _icon(iconCodePoint, fonts, color: accent, size: 12),
              pw.SizedBox(width: 6),
              pw.Text(
                title,
                style: pw.TextStyle(
                    font: fonts.semiBold, fontSize: 11, color: _ink),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          if (topEntries.isEmpty)
            pw.Text(
              'No data available for this section.',
              style:
                  pw.TextStyle(font: fonts.regular, fontSize: 9, color: _muted),
            )
          else
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: _border, width: 0.7),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.5),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(0.9),
                3: const pw.FlexColumnWidth(1.4),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: _surface),
                  children: [
                    _tableText('Category', fonts,
                        isHeader: true, align: pw.Alignment.centerLeft),
                    _tableText('Amount', fonts,
                        isHeader: true, align: pw.Alignment.centerRight),
                    _tableText('Share', fonts,
                        isHeader: true, align: pw.Alignment.centerRight),
                    _tableText('Distribution', fonts,
                        isHeader: true, align: pw.Alignment.centerLeft),
                  ],
                ),
                ...topEntries.map((entry) {
                  final percentage =
                      total > 0 ? (entry.value / total * 100) : 0.0;
                  const barMaxWidth = 90.0;
                  return pw.TableRow(
                    children: [
                      _tableText(_ellipsize(entry.key, 24), fonts),
                      _tableText('KSh ${_formatCompact(entry.value)}', fonts,
                          align: pw.Alignment.centerRight),
                      _tableText('${percentage.toStringAsFixed(1)}%', fonts,
                          align: pw.Alignment.centerRight),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 9),
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          width: barMaxWidth,
                          height: 6,
                          decoration: pw.BoxDecoration(
                            color: _surface,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(color: _border, width: 0.4),
                          ),
                          child: pw.Align(
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Container(
                              width: barMaxWidth * (percentage / 100),
                              height: 6,
                              decoration: pw.BoxDecoration(
                                color: accent,
                                borderRadius: pw.BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildTransactionTable(
    List<model.Transaction> transactions,
    Map<int, Category>? categoryMap,
    _PdfFonts fonts,
  ) {
    final rows = transactions.map((tx) {
      final date = DateFormat('dd MMM yyyy').format(_parseDateSafe(tx.date));
      final description = _ellipsize(_resolveDescription(tx, categoryMap), 36);
      final category = _ellipsize(_resolveCategoryName(tx, categoryMap), 20);
      final type = tx.type == 'income' ? 'Income' : 'Expense';
      final sign = tx.type == 'income' ? '+' : '-';
      final amount = '$sign KSh ${_formatCurrency(tx.amount)}';
      return [date, description, category, type, amount];
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Transaction Ledger',
            AppIcons.receipt_long_outlined.codePoint, fonts),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(9),
            border: pw.Border.all(color: _border),
          ),
          child: pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Description',
              'Category',
              'Type',
              'Amount'
            ],
            data: rows,
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _border, width: 0.6),
              verticalInside: pw.BorderSide(color: _border, width: 0.6),
              top: pw.BorderSide(color: _border, width: 0.8),
              right: pw.BorderSide(color: _border, width: 0.8),
              left: pw.BorderSide(color: _border, width: 0.8),
              bottom: pw.BorderSide(color: _border, width: 0.8),
            ),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            headerPadding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            headerDecoration: pw.BoxDecoration(color: _primary),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: pw.BoxDecoration(color: _surface),
            headerStyle: pw.TextStyle(
              font: fonts.semiBold,
              fontSize: 9,
              color: PdfColors.white,
            ),
            cellStyle:
                pw.TextStyle(font: fonts.regular, fontSize: 8.8, color: _ink),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(2.6),
              2: const pw.FlexColumnWidth(1.7),
              3: const pw.FlexColumnWidth(1.1),
              4: const pw.FlexColumnWidth(1.4),
            },
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
            },
            headerAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
            },
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildGovernanceNotes(
    _ReportMetrics metrics,
    _PdfFonts fonts,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle(
              'Governance & Notes', AppIcons.security.codePoint, fonts),
          pw.SizedBox(height: 8),
          _noteRow(
            iconCodePoint: AppIcons.info_outline.codePoint,
            text:
                'Largest single transaction: KSh ${_formatCurrency(metrics.largestTransaction)}.',
            fonts: fonts,
          ),
          _noteRow(
            iconCodePoint: AppIcons.analytics.codePoint,
            text:
                'Top expense driver: ${metrics.topExpenseCategory} (${metrics.topExpenseShare.toStringAsFixed(1)}% of expenses).',
            fonts: fonts,
          ),
          _noteRow(
            iconCodePoint: AppIcons.check_circle.codePoint,
            text:
                'Recommendations are system-generated and should be reviewed alongside business context.',
            fonts: fonts,
          ),
        ],
      ),
    );
  }

  static pw.Widget _noteRow({
    required int iconCodePoint,
    required String text,
    required _PdfFonts fonts,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _icon(iconCodePoint, fonts, color: _primary, size: 10),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              text,
              style:
                  pw.TextStyle(font: fonts.regular, fontSize: 9, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(
      String title, int iconCodePoint, _PdfFonts fonts) {
    return pw.Row(
      children: [
        _icon(iconCodePoint, fonts, color: _primary, size: 13),
        pw.SizedBox(width: 6),
        pw.Text(
          title,
          style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: _ink),
        ),
      ],
    );
  }

  static pw.Widget _tableText(
    String text,
    _PdfFonts fonts, {
    bool isHeader = false,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: isHeader ? fonts.semiBold : fonts.regular,
          fontSize: isHeader ? 8.8 : 8.6,
          color: isHeader ? _ink : _ink,
        ),
      ),
    );
  }

  static pw.Widget _icon(
    int codePoint,
    _PdfFonts fonts, {
    required PdfColor color,
    required double size,
  }) {
    return pw.Icon(
      pw.IconData(codePoint),
      color: color,
      size: size,
      font: fonts.icons,
    );
  }

  static _ReportMetrics _computeMetrics(
    List<model.Transaction> transactions,
    Map<int, Category>? categoryMap,
  ) {
    double totalIncome = 0;
    double totalExpenses = 0;
    int incomeCount = 0;
    int expenseCount = 0;
    double largestTransaction = 0;
    final expenseByCategory = <String, double>{};
    final incomeByCategory = <String, double>{};

    DateTime? newest;
    DateTime? oldest;

    for (final tx in transactions) {
      final date = _parseDateSafe(tx.date);
      newest = newest == null || date.isAfter(newest) ? date : newest;
      oldest = oldest == null || date.isBefore(oldest) ? date : oldest;

      largestTransaction = math.max(largestTransaction, tx.amount);

      final categoryName = _resolveCategoryName(tx, categoryMap);

      if (tx.type == 'income') {
        totalIncome += tx.amount;
        incomeCount++;
        incomeByCategory[categoryName] =
            (incomeByCategory[categoryName] ?? 0) + tx.amount;
      } else {
        totalExpenses += tx.amount;
        expenseCount++;
        expenseByCategory[categoryName] =
            (expenseByCategory[categoryName] ?? 0) + tx.amount;
      }
    }

    final balance = totalIncome - totalExpenses;
    final savingsRate = totalIncome > 0 ? (balance / totalIncome * 100) : 0.0;
    final burnRate =
        totalIncome > 0 ? (totalExpenses / totalIncome * 100) : 0.0;
    final averageTransaction = transactions.isNotEmpty
        ? (totalIncome + totalExpenses) / transactions.length
        : 0.0;

    String topExpenseCategory = 'N/A';
    double topExpenseShare = 0;
    if (expenseByCategory.isNotEmpty && totalExpenses > 0) {
      final top = expenseByCategory.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      topExpenseCategory = top.key;
      topExpenseShare = top.value / totalExpenses * 100;
    }

    final healthScore = _computeHealthScore(
      balance: balance,
      savingsRate: savingsRate,
      burnRate: burnRate,
      topExpenseShare: topExpenseShare,
    );

    return _ReportMetrics(
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
      balance: balance,
      savingsRate: savingsRate,
      burnRate: burnRate,
      averageTransaction: averageTransaction,
      transactionCount: transactions.length,
      incomeCount: incomeCount,
      expenseCount: expenseCount,
      healthScore: healthScore,
      healthLabel: _healthLabel(healthScore),
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
      topExpenseCategory: topExpenseCategory,
      topExpenseShare: topExpenseShare,
      largestTransaction: largestTransaction,
      dateFrom: oldest,
      dateTo: newest,
    );
  }

  static int _computeHealthScore({
    required double balance,
    required double savingsRate,
    required double burnRate,
    required double topExpenseShare,
  }) {
    var score = 55;

    if (balance > 0) {
      score += 12;
    } else {
      score -= 18;
    }

    if (savingsRate >= 25) {
      score += 18;
    } else if (savingsRate >= 10) {
      score += 8;
    } else {
      score -= 10;
    }

    if (burnRate <= 75) {
      score += 10;
    } else if (burnRate > 100) {
      score -= 16;
    }

    if (topExpenseShare > 50) {
      score -= 8;
    } else if (topExpenseShare <= 25) {
      score += 5;
    }

    return score.clamp(0, 100);
  }

  static String _healthLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 65) return 'Stable';
    if (score >= 45) return 'Needs Attention';
    return 'Critical';
  }

  static PdfColor _scoreColor(int score) {
    if (score >= 80) return _success;
    if (score >= 65) return _primary;
    if (score >= 45) return _warning;
    return _danger;
  }

  static List<String> _buildRecommendations(_ReportMetrics metrics) {
    final recommendations = <String>[];

    if (metrics.balance < 0) {
      recommendations.add(
        'Operating at a deficit. Prioritize immediate cost controls and increase revenue inflows.',
      );
    } else {
      recommendations.add(
        'Positive net cash flow maintained. Consider routing a fixed portion to long-term reserves.',
      );
    }

    if (metrics.savingsRate < 15) {
      recommendations.add(
        'Savings rate is below enterprise target (15%+). Introduce monthly saving automation to enforce discipline.',
      );
    } else {
      recommendations.add(
        'Savings rate is healthy. Maintain this threshold to strengthen cash resilience.',
      );
    }

    if (metrics.topExpenseShare > 40) {
      recommendations.add(
        'Expense concentration risk detected in ${metrics.topExpenseCategory}. Review contracts and define a spend cap policy.',
      );
    } else {
      recommendations.add(
        'Expense distribution is reasonably diversified across categories, reducing concentration risk.',
      );
    }

    return recommendations;
  }

  static String _periodLabel(String timeFilter) {
    switch (timeFilter) {
      case 'week':
        return 'This Week';
      case 'year':
        return 'This Year';
      case 'month':
      default:
        return 'This Month';
    }
  }

  static DateTime _parseDateSafe(String raw) {
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return DateTime.now();
    }
  }

  static String _resolveCategoryName(
    model.Transaction transaction,
    Map<int, Category>? categoryMap,
  ) {
    if (transaction.categoryId != null &&
        categoryMap != null &&
        categoryMap.containsKey(transaction.categoryId)) {
      return categoryMap[transaction.categoryId]!.name;
    }
    return 'Uncategorized';
  }

  static String _resolveDescription(
    model.Transaction transaction,
    Map<int, Category>? categoryMap,
  ) {
    final description = transaction.description.trim();
    if (description.isNotEmpty) {
      return description;
    }

    final category = _resolveCategoryName(transaction, categoryMap);
    if (transaction.type == 'income') {
      return '$category income entry';
    }
    if (transaction.amount >= 10000) {
      return '$category major expense';
    }
    if (transaction.amount >= 5000) {
      return '$category significant expense';
    }
    return '$category regular expense';
  }

  static String _formatCurrency(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  static String _formatCompact(double amount) {
    final abs = amount.abs();
    if (abs >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    }
    if (abs >= 1000) {
      return '${(amount / 1000).toStringAsFixed(2)}K';
    }
    return amount.toStringAsFixed(2);
  }

  static String _ellipsize(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars - 1)}…';
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font semiBold;
  final pw.Font bold;
  final pw.Font icons;

  const _PdfFonts({
    required this.regular,
    required this.semiBold,
    required this.bold,
    required this.icons,
  });
}

class _ReportMetrics {
  final double totalIncome;
  final double totalExpenses;
  final double balance;
  final double savingsRate;
  final double burnRate;
  final double averageTransaction;
  final int transactionCount;
  final int incomeCount;
  final int expenseCount;
  final int healthScore;
  final String healthLabel;
  final Map<String, double> expenseByCategory;
  final Map<String, double> incomeByCategory;
  final String topExpenseCategory;
  final double topExpenseShare;
  final double largestTransaction;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  const _ReportMetrics({
    required this.totalIncome,
    required this.totalExpenses,
    required this.balance,
    required this.savingsRate,
    required this.burnRate,
    required this.averageTransaction,
    required this.transactionCount,
    required this.incomeCount,
    required this.expenseCount,
    required this.healthScore,
    required this.healthLabel,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.topExpenseCategory,
    required this.topExpenseShare,
    required this.largestTransaction,
    required this.dateFrom,
    required this.dateTo,
  });
}
