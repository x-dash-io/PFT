import 'package:flutter/widgets.dart';
import 'package:lucide_icons/lucide_icons.dart';

// ignore_for_file: constant_identifier_names

/// Central app icon aliases backed by Lucide.
///
/// The member names mirror prior Material icon identifiers so the app can be
/// migrated with minimal churn while rendering Lucide glyphs everywhere.
class AppIcons {
  AppIcons._();

  static const IconData account_balance = LucideIcons.landmark;
  static const IconData account_balance_wallet = LucideIcons.wallet;
  static const IconData account_balance_wallet_outlined = LucideIcons.wallet;
  static const IconData account_balance_wallet_rounded = LucideIcons.wallet2;
  static const IconData add = LucideIcons.plus;
  static const IconData all_inclusive = LucideIcons.infinity;
  static const IconData analytics = LucideIcons.lineChart;
  static const IconData analytics_outlined = LucideIcons.lineChart;
  static const IconData arrow_back = LucideIcons.arrowLeft;
  static const IconData arrow_back_rounded = LucideIcons.arrowLeft;
  static const IconData arrow_downward = LucideIcons.arrowDown;
  static const IconData arrow_downward_rounded = LucideIcons.arrowDown;
  static const IconData arrow_forward_rounded = LucideIcons.arrowRight;
  static const IconData arrow_upward = LucideIcons.arrowUp;
  static const IconData arrow_upward_rounded = LucideIcons.arrowUp;
  static const IconData attach_money = LucideIcons.dollarSign;
  static const IconData backup = LucideIcons.uploadCloud;
  static const IconData book = LucideIcons.bookOpen;
  static const IconData build = LucideIcons.wrench;
  static const IconData calendar_today = LucideIcons.calendar;
  static const IconData card_giftcard = LucideIcons.gift;
  static const IconData category = LucideIcons.layoutGrid;
  static const IconData category_outlined = LucideIcons.layoutGrid;
  static const IconData check_circle = LucideIcons.checkCircle;
  static const IconData chevron_right = LucideIcons.chevronRight;
  static const IconData cleaning_services_outlined = LucideIcons.sparkles;
  static const IconData cloud_done = LucideIcons.cloud;
  static const IconData cloud_download_outlined = LucideIcons.downloadCloud;
  static const IconData credit_card_outlined = LucideIcons.creditCard;
  static const IconData delete = LucideIcons.trash2;
  static const IconData delete_forever = LucideIcons.trash2;
  static const IconData delete_outline = LucideIcons.trash2;
  static const IconData directions_car = LucideIcons.car;
  static const IconData edit = LucideIcons.pencil;
  static const IconData edit_outlined = LucideIcons.pencil;
  static const IconData email_outlined = LucideIcons.mail;
  static const IconData error = LucideIcons.alertCircle;
  static const IconData error_outline = LucideIcons.alertCircle;
  static const IconData favorite = LucideIcons.heart;
  static const IconData filter_list = LucideIcons.filter;
  static const IconData flight = LucideIcons.plane;
  static const IconData house = LucideIcons.home;
  static const IconData house_outlined = LucideIcons.home;
  static const IconData info = LucideIcons.info;
  static const IconData info_outline = LucideIcons.info;
  static const IconData insert_chart_outlined = LucideIcons.barChart3;
  static const IconData insights_outlined = LucideIcons.lineChart;
  static const IconData label = LucideIcons.tag;
  static const IconData lightbulb_outline = LucideIcons.lightbulb;
  static const IconData local_hospital = LucideIcons.stethoscope;
  static const IconData lock_outline = LucideIcons.lock;
  static const IconData lock_outline_rounded = LucideIcons.lock;
  static const IconData logout = LucideIcons.logOut;
  static const IconData money = LucideIcons.wallet;
  static const IconData movie = LucideIcons.film;
  static const IconData movie_outlined = LucideIcons.film;
  static const IconData music_note = LucideIcons.music;
  static const IconData notifications = LucideIcons.bell;
  static const IconData notifications_active_outlined = LucideIcons.bellRing;
  static const IconData offline_bolt = LucideIcons.zapOff;
  static const IconData password = LucideIcons.keyRound;
  static const IconData person = LucideIcons.user;
  static const IconData person_add_rounded = LucideIcons.userPlus;
  static const IconData person_outline = LucideIcons.user;
  static const IconData pets = LucideIcons.cat;
  static const IconData phone_android = LucideIcons.smartphone;
  static const IconData phonelink_lock = LucideIcons.smartphone;
  static const IconData picture_as_pdf = LucideIcons.fileText;
  static const IconData question_answer_outlined = LucideIcons.messageCircle;
  static const IconData receipt = LucideIcons.receipt;
  static const IconData receipt_long_outlined = LucideIcons.scrollText;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData repeat = LucideIcons.repeat;
  static const IconData restaurant = LucideIcons.utensils;
  static const IconData savings = LucideIcons.piggyBank;
  static const IconData school = LucideIcons.graduationCap;
  static const IconData search = LucideIcons.search;
  static const IconData security = LucideIcons.shield;
  static const IconData shopping_cart = LucideIcons.shoppingCart;
  static const IconData source = LucideIcons.database;
  static const IconData spa = LucideIcons.flower2;
  static const IconData stacked_line_chart = LucideIcons.lineChart;
  static const IconData support_agent = LucideIcons.lifeBuoy;
  static const IconData sync = LucideIcons.refreshCw;
  static const IconData trending_down = LucideIcons.trendingDown;
  static const IconData trending_up = LucideIcons.trendingUp;
  static const IconData verified_user_outlined = LucideIcons.shieldCheck;
  static const IconData visibility_off_rounded = LucideIcons.eyeOff;
  static const IconData visibility_rounded = LucideIcons.eye;
  static const IconData water_drop_outlined = LucideIcons.droplet;
  static const IconData wifi = LucideIcons.wifi;
  static const IconData work = LucideIcons.briefcase;

  /// Supported category icons that can be persisted and restored.
  static const List<IconData> categoryPickerIcons = [
    shopping_cart,
    restaurant,
    house,
    flight,
    receipt,
    local_hospital,
    school,
    pets,
    phone_android,
    wifi,
    movie,
    spa,
    build,
    book,
    music_note,
    directions_car,
    attach_money,
    work,
    card_giftcard,
    savings,
    category,
    source,
    label,
    security,
    favorite,
    support_agent,
    water_drop_outlined,
    lightbulb_outline,
    cloud_done,
    backup,
    notifications,
    analytics,
    insights_outlined,
    account_balance_wallet,
    account_balance,
    credit_card_outlined,
    filter_list,
    search,
    repeat,
    sync,
    question_answer_outlined,
    chevron_right,
    calendar_today,
    person_outline,
    lock_outline,
    money,
    offline_bolt,
    picture_as_pdf,
  ];

  static const Map<int, IconData> _legacyCategoryIconCodePointMap = {
    0xe59c: shopping_cart,
    0xe532: restaurant,
    0xe328: house,
    0xe297: flight,
    0xe50c: receipt,
    0xe396: local_hospital,
    0xe559: school,
    0xe4a1: pets,
    0xe4a3: phone_android,
    0xe6e7: wifi,
    0xe40d: movie,
    0xe5d8: spa,
    0xe116: build,
    0xe0ef: book,
    0xe415: music_note,
    0xe1d7: directions_car,
    0xe0b2: attach_money,
    0xe6f2: work,
    0xe13e: card_giftcard,
    0xe553: savings,
    0xe148: category,
    0xe5d4: source,
    0xe360: label,
  };

  /// Rebuilds an icon from persisted category code points.
  ///
  /// Category icon picks are restored from known icon constants.
  /// Legacy Material picks are mapped into Lucide equivalents.
  static IconData fromCodePoint(int codePoint) {
    for (final icon in categoryPickerIcons) {
      if (icon.codePoint == codePoint) {
        return icon;
      }
    }
    return _legacyCategoryIconCodePointMap[codePoint] ?? label;
  }
}
