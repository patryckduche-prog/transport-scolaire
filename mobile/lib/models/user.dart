enum UserRole { driver, parent, student, company, region }

class AppUser {
  const AppUser({required this.id, required this.name, required this.email, required this.role});
  final String id;
  final String name;
  final String email;
  final UserRole role;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'].toString(),
        name: json['name'] as String,
        email: json['email'] as String,
        role: UserRole.values.firstWhere((r) => r.name == json['role']),
      );
}
