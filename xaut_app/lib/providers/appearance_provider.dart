import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用外观与无障碍视觉偏好管理（本地 SharedPreferences 持久化，撤回授权时同步清空）。
class AppearanceProvider extends ChangeNotifier {
  static const String reduceTransparencyKey = 'jinhua_reduce_transparency_v1';

  bool _reduceTransparency;

  AppearanceProvider({bool initialReduceTransparency = false})
      : _reduceTransparency = initialReduceTransparency;

  /// 是否开启「减弱界面透明与动态模糊」（高对比实心表面 + 零自定义片段着色器模式）。
  bool get reduceTransparency => _reduceTransparency;

  /// 冷启动前同步读取用户持久化配置，避免首帧闪烁。
  static Future<bool> loadReduceTransparency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(reduceTransparencyKey) ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// 在可能未挂载 [AppearanceProvider] 的隔离单测树中安全订阅状态。
  static AppearanceProvider? maybeWatch(BuildContext context) {
    try {
      return context.watch<AppearanceProvider>();
    } on ProviderNotFoundException catch (_) {
      return null;
    }
  }

  /// 在可能未挂载 [AppearanceProvider] 的隔离单测树中安全读取实例。
  static AppearanceProvider? maybeRead(BuildContext context) {
    try {
      return context.read<AppearanceProvider>();
    } on ProviderNotFoundException catch (_) {
      return null;
    }
  }

  Future<void> setReduceTransparency(bool value) async {
    if (_reduceTransparency == value) return;
    _reduceTransparency = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(reduceTransparencyKey, value);
    } on Object catch (_) {
      // 偏好写入异常不影响内存态即时生效
    }
  }

  Future<void> toggleReduceTransparency() =>
      setReduceTransparency(!_reduceTransparency);

  /// 撤回法律授权后重置内存态偏好为默认值。
  void resetToDefault() {
    if (!_reduceTransparency) return;
    _reduceTransparency = false;
    notifyListeners();
  }
}
