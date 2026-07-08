class UserSettingsModel {
  const UserSettingsModel({
    required this.userId,
    required this.freeDropUsed,
    this.fcmToken,
  });

  final String userId;
  final bool freeDropUsed;
  final String? fcmToken;

  factory UserSettingsModel.fromJson(Map<String, dynamic> json) {
    return UserSettingsModel(
      userId: json['user_id'] as String,
      freeDropUsed: json['free_drop_used'] as bool? ?? false,
      fcmToken: json['fcm_token'] as String?,
    );
  }

  UserSettingsModel copyWith({bool? freeDropUsed, String? fcmToken}) {
    return UserSettingsModel(
      userId: userId,
      freeDropUsed: freeDropUsed ?? this.freeDropUsed,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}
