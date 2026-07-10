class UserSettingsModel {
  const UserSettingsModel({
    required this.userId,
    required this.freeDropUsed,
    required this.freeDropsUsed,
    required this.onboardingCompleted,
    this.fcmToken,
    this.onboardingAnswers,
    this.displayName,
  });

  final String userId;
  final bool freeDropUsed;

  /// How many drops this user has created (counted against the configurable
  /// `free_drop_limit`).
  final int freeDropsUsed;
  final bool onboardingCompleted;
  final String? fcmToken;
  final Map<String, dynamic>? onboardingAnswers;

  /// Sender's chosen display name, used to fill the share link's `?from=`.
  final String? displayName;

  factory UserSettingsModel.fromJson(Map<String, dynamic> json) {
    return UserSettingsModel(
      userId: json['user_id'] as String,
      freeDropUsed: json['free_drop_used'] as bool? ?? false,
      freeDropsUsed: (json['free_drops_used'] as num?)?.toInt() ?? 0,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      fcmToken: json['fcm_token'] as String?,
      onboardingAnswers: json['onboarding_answers'] as Map<String, dynamic>?,
      displayName: json['display_name'] as String?,
    );
  }

  UserSettingsModel copyWith({
    bool? freeDropUsed,
    int? freeDropsUsed,
    bool? onboardingCompleted,
    String? fcmToken,
    Map<String, dynamic>? onboardingAnswers,
    String? displayName,
  }) {
    return UserSettingsModel(
      userId: userId,
      freeDropUsed: freeDropUsed ?? this.freeDropUsed,
      freeDropsUsed: freeDropsUsed ?? this.freeDropsUsed,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      fcmToken: fcmToken ?? this.fcmToken,
      onboardingAnswers: onboardingAnswers ?? this.onboardingAnswers,
      displayName: displayName ?? this.displayName,
    );
  }
}
