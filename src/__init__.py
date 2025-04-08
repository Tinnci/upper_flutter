"""
上位机环境监测系统

这个包包含了环境监测上位机系统的所有核心组件。
主要功能包括：
- GUI界面显示
- WiFi通信
- 数据库管理
- 实时数据图表显示
"""

from .app import UpperMonitorApp
from .communication import WiFiCommunication
from .database import Database
from .ui_components import DatabaseViewerWindow

__version__ = "0.1.0"

__all__ = [
    'UpperMonitorApp',
    'WiFiCommunication',
    'Database',
    'DatabaseViewerWindow',
]