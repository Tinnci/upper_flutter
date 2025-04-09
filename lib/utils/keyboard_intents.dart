import 'package:flutter/material.dart';

/// 刷新数据意图
class RefreshDataIntent extends Intent {
  const RefreshDataIntent();
}

/// 保存设置意图
class SaveSettingsIntent extends Intent {
  const SaveSettingsIntent();
}

/// 连接/断开设备意图
class ToggleConnectionIntent extends Intent {
  const ToggleConnectionIntent();
}

/// 扫描设备意图
class ScanDevicesIntent extends Intent {
  const ScanDevicesIntent();
}

/// 导航到主页意图
class NavigateHomeIntent extends Intent {
  const NavigateHomeIntent();
}

/// 导航到数据库页面意图
class NavigateDatabaseIntent extends Intent {
  const NavigateDatabaseIntent();
}

/// 导航到设置页面意图
class NavigateSettingsIntent extends Intent {
  const NavigateSettingsIntent();
}

/// 删除数据意图
class DeleteDataIntent extends Intent {
  const DeleteDataIntent();
}

/// 导出数据意图
class ExportDataIntent extends Intent {
  const ExportDataIntent();
}

/// 重置设置意图
class ResetSettingsIntent extends Intent {
  const ResetSettingsIntent();
}
