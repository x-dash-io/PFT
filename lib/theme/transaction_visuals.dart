import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'app_theme.dart';

class TransactionVisual {
  final IconData icon;
  final Color accent;
  final String label;

  const TransactionVisual({
    required this.icon,
    required this.accent,
    required this.label,
  });
}

TransactionVisual resolveTransactionVisual({
  required String type,
  required String description,
  String? categoryName,
}) {
  final text = '$description ${categoryName ?? ''}'.toLowerCase();

  bool containsAny(List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  if (containsAny(['wifi', 'internet', 'broadband', 'data', 'hotspot'])) {
    return const TransactionVisual(
      icon: AppIcons.wifi,
      accent: AppColors.info,
      label: 'Internet',
    );
  }

  if (containsAny(['electricity', 'power', 'token', 'light'])) {
    return const TransactionVisual(
      icon: AppIcons.lightbulb_outline,
      accent: AppColors.warning,
      label: 'Electricity',
    );
  }

  if (containsAny(['water'])) {
    return const TransactionVisual(
      icon: AppIcons.water_drop_outlined,
      accent: AppColors.secondary,
      label: 'Water',
    );
  }

  if (containsAny(['rent', 'house', 'home'])) {
    return const TransactionVisual(
      icon: AppIcons.house_outlined,
      accent: AppColors.tertiary,
      label: 'Housing',
    );
  }

  if (containsAny(['movie', 'netflix', 'stream', 'subscription'])) {
    return const TransactionVisual(
      icon: AppIcons.movie_outlined,
      accent: AppColors.tertiary,
      label: 'Entertainment',
    );
  }

  if (containsAny(['food', 'restaurant', 'lunch', 'dinner', 'cafe'])) {
    return const TransactionVisual(
      icon: AppIcons.restaurant,
      accent: AppColors.warning,
      label: 'Food',
    );
  }

  if (containsAny(['transport', 'uber', 'bolt', 'taxi', 'fuel', 'matatu'])) {
    return const TransactionVisual(
      icon: AppIcons.directions_car,
      accent: AppColors.info,
      label: 'Transport',
    );
  }

  if (containsAny(['shopping', 'grocery', 'market'])) {
    return const TransactionVisual(
      icon: AppIcons.shopping_cart,
      accent: AppColors.primary,
      label: 'Shopping',
    );
  }

  if (containsAny(['hospital', 'medical', 'clinic', 'health'])) {
    return const TransactionVisual(
      icon: AppIcons.local_hospital,
      accent: AppColors.error,
      label: 'Health',
    );
  }

  if (containsAny(['tuition', 'school', 'education', 'course'])) {
    return const TransactionVisual(
      icon: AppIcons.school,
      accent: AppColors.primary,
      label: 'Education',
    );
  }

  if (containsAny(['salary', 'payroll', 'wage', 'bonus'])) {
    return const TransactionVisual(
      icon: AppIcons.work,
      accent: AppColors.success,
      label: 'Salary',
    );
  }

  if (containsAny(['gift'])) {
    return const TransactionVisual(
      icon: AppIcons.card_giftcard,
      accent: AppColors.tertiary,
      label: 'Gift',
    );
  }

  if (containsAny(['loan', 'debt', 'credit'])) {
    return const TransactionVisual(
      icon: AppIcons.credit_card_outlined,
      accent: AppColors.error,
      label: 'Credit',
    );
  }

  if (containsAny(['save', 'saving', 'invest'])) {
    return const TransactionVisual(
      icon: AppIcons.savings,
      accent: AppColors.success,
      label: 'Savings',
    );
  }

  if (type == 'income') {
    return const TransactionVisual(
      icon: AppIcons.account_balance_wallet,
      accent: AppColors.success,
      label: 'Income',
    );
  }

  return const TransactionVisual(
    icon: AppIcons.receipt_long_outlined,
    accent: AppColors.error,
    label: 'Expense',
  );
}
