import 'package:flutter/foundation.dart';

import '../models/nomad_route.dart';
import '../models/user.dart';

class AppState extends ChangeNotifier {
  AppUser? user;
  String? token;
  NomadRoute? selectedDriverRoute;
  bool darkMode = false;

  bool get isAuthenticated => token != null;

  void setSession(AppUser nextUser, String nextToken) {
    user = nextUser;
    token = nextToken;
    notifyListeners();
  }

  void selectDriverRoute(NomadRoute route) {
    selectedDriverRoute = route;
    notifyListeners();
  }

  void toggleDarkMode() {
    darkMode = !darkMode;
    notifyListeners();
  }

  void logout() {
    user = null;
    token = null;
    selectedDriverRoute = null;
    notifyListeners();
  }
}
