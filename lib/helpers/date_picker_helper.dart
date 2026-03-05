/// Date picker helper utility
///
/// Provides consistent date and date range picker dialogs
/// with modern Material Design styling.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DatePickerHelper {
  static Future<DateTime?> showModernDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    return await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.neutralBackground,
              onSurface: AppColors.neutralDark,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.neutralBackground,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  static Future<DateTimeRange?> showModernDateRangePicker({
    required BuildContext context,
    required DateTime firstDate,
    required DateTime lastDate,
    DateTimeRange? initialDateRange,
  }) async {
    return await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.neutralBackground,
              onSurface: AppColors.neutralDark,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.neutralBackground,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
