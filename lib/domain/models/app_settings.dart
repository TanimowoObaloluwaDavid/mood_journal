import '../../core/theme/app_theme.dart';

/// User preferences. Persisted as JSON so adding a field never needs a migration.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.remindersEnabled = true,
    this.reminderHour = 21,
    this.reminderMinute = 0,
    this.encryptionEnabled = true,
    this.passcodeEnabled = false,
    this.dailyPromptEnabled = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: AppThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      remindersEnabled: json['remindersEnabled'] as bool? ?? true,
      reminderHour: (json['reminderHour'] as num?)?.toInt() ?? 21,
      reminderMinute: (json['reminderMinute'] as num?)?.toInt() ?? 0,
      encryptionEnabled: json['encryptionEnabled'] as bool? ?? true,
      passcodeEnabled: json['passcodeEnabled'] as bool? ?? false,
      dailyPromptEnabled: json['dailyPromptEnabled'] as bool? ?? true,
    );
  }

  static const defaultPromptHour = 9;

  final AppThemeMode themeMode;
  final bool remindersEnabled;
  final int reminderHour;
  final int reminderMinute;

  /// Encrypt entry text at rest. Turning this off decrypts existing rows in place.
  final bool encryptionEnabled;

  final bool passcodeEnabled;
  final bool dailyPromptEnabled;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? remindersEnabled,
    int? reminderHour,
    int? reminderMinute,
    bool? encryptionEnabled,
    bool? passcodeEnabled,
    bool? dailyPromptEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
      passcodeEnabled: passcodeEnabled ?? this.passcodeEnabled,
      dailyPromptEnabled: dailyPromptEnabled ?? this.dailyPromptEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'remindersEnabled': remindersEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'encryptionEnabled': encryptionEnabled,
        'passcodeEnabled': passcodeEnabled,
        'dailyPromptEnabled': dailyPromptEnabled,
      };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.remindersEnabled == remindersEnabled &&
      other.reminderHour == reminderHour &&
      other.reminderMinute == reminderMinute &&
      other.encryptionEnabled == encryptionEnabled &&
      other.passcodeEnabled == passcodeEnabled &&
      other.dailyPromptEnabled == dailyPromptEnabled;

  @override
  int get hashCode => Object.hash(
        themeMode,
        remindersEnabled,
        reminderHour,
        reminderMinute,
        encryptionEnabled,
        passcodeEnabled,
        dailyPromptEnabled,
      );
}

/// Prompts rotate deterministically per day so the same prompt shows all day
/// and the next day brings a different one.
class JournalPrompts {
  const JournalPrompts._();

  static const all = <String>[
    'What went well today?',
    'What drained your energy today?',
    'What are you avoiding?',
    'Who made today better?',
    'What did you learn today?',
    'What would you tell yourself from a year ago?',
    'What is one small thing you can do better tomorrow?',
    'What are you grateful for right now?',
    'What felt hard, and how did you get through it?',
    'What is taking up more space in your head than it deserves?',
  ];

  static String forDay(DateTime date) {
    final seed = date.year * 10000 + date.month * 100 + date.day;
    return all[seed % all.length];
  }
}
