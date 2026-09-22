/// A traveller's privilege level.
///
/// [admin] is the single moderator role described in the brief: it can
/// delete ANY picture from the "General World" to keep the public feed
/// clean. [standard] travellers can only manage their own pictures.
enum UserRole {
  standard,
  admin;

  static UserRole fromDb(String? value) {
    return value == 'admin' ? UserRole.admin : UserRole.standard;
  }

  String get toDb => this == UserRole.admin ? 'admin' : 'standard';
}
