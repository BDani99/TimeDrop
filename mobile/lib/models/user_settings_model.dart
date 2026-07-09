class UserSettingsModel {
  const UserSettingsModel({
    required this.userId,
    required this.freeDropUsed,
    required this.onboardingCompleted,
    this.fcmToken,
    this.onboardingAnswers,
  });

  final String userId;
  final bool freeDropUsed;
  final bool onboardingCompleted;
  final String? fcmToken;
  final Map<String, dynamic>? onboardingAnswers;

  factory UserSettingsModel.fromJson(Map<String, dynamic> json) {
    return UserSettingsModel(
      userId: json['user_id'] as String,
      freeDropUsed: json['free_drop_used'] as bool? ?? false,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      fcmToken: json['fcm_token'] as String?,
      onboardingAnswers: json['onboarding_answers'] as Map<String, dynamic>?,
    );
  }

  UserSettingsModel copyWith({
    bool? freeDropUsed,
    bool? onboardingCompleted,
    String? fcmToken,
    Map<String, dynamic>? onboardingAnswers,
  }) {
    return UserSettingsModel(
      userId: userId,
      freeDropUsed: freeDropUsed ?? this.freeDropUsed,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      fcmToken: fcmToken ?? this.fcmToken,
      onboardingAnswers: onboardingAnswers ?? this.onboardingAnswers,
    );
  }
}
