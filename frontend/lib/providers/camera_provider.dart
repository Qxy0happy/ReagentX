import 'package:flutter/foundation.dart';

class CameraProvider extends ChangeNotifier {
  String? _imagePath;

  String? get imagePath => _imagePath;

  void setImagePath(String? path) {
    _imagePath = path;
    notifyListeners();
  }

  void clear() {
    _imagePath = null;
    notifyListeners();
  }
}
