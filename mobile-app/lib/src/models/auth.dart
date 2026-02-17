/// Authentication models for JWT tokens
class AuthTokens {
  final String accessToken;
  final String refreshToken;

  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
      };

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'],
        refreshToken: json['refresh_token'],
      );
}

class LoginResponse {
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> user;

  LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        accessToken: json['access_token'],
        refreshToken: json['refresh_token'],
        user: json['user'],
      );
}
