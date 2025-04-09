import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings_model.dart';

/// 设置服务，用于保存和加载应用程序设置
class SettingsService {
  static const String _settingsKey = 'app_settings';
  
  /// 保存设置到SharedPreferences
  Future<bool> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(settings.toJson());
      return await prefs.setString(_settingsKey, settingsJson);
    } catch (e) {
      debugPrint('保存设置时出错: $e');
      return false;
    }
  }
  
  /// 从SharedPreferences加载设置
  Future<AppSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);
      
      if (settingsJson == null) {
        // 如果没有保存的设置，返回默认设置
        return AppSettings();
      }
      
      final Map<String, dynamic> settingsMap = jsonDecode(settingsJson);
      return AppSettings.fromJson(settingsMap);
    } catch (e) {
      debugPrint('加载设置时出错: $e');
      // 出错时返回默认设置
      return AppSettings();
    }
  }
  
  /// 更新单个设置项
  Future<bool> updateSetting(String key, dynamic value) async {
    try {
      final settings = await loadSettings();
      final Map<String, dynamic> settingsMap = settings.toJson();
      
      // 更新指定的设置项
      settingsMap[key] = value;
      
      // 创建新的设置对象并保存
      final updatedSettings = AppSettings.fromJson(settingsMap);
      return await saveSettings(updatedSettings);
    } catch (e) {
      debugPrint('更新设置时出错: $e');
      return false;
    }
  }
  
  /// 重置所有设置为默认值
  Future<bool> resetSettings() async {
    try {
      return await saveSettings(AppSettings());
    } catch (e) {
      debugPrint('重置设置时出错: $e');
      return false;
    }
  }
}
