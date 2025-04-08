#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import platform
import ctypes
import threading
import signal
import tkinter as tk # 需要 tk 来创建 root

# 从 app 模块导入主应用类
from app import UpperMonitorApp

def enable_dpi_awareness():
    """尝试在 Windows 上启用 DPI 感知"""
    if platform.system() == "Windows":
        try:
            # Per-Monitor DPI awareness v2 (需要 Windows 10 Creators Update+)
            ctypes.windll.shcore.SetProcessDpiAwareness(2)
            print("已启用 DPI 感知 (Per-Monitor v2)")
            return True
        except (AttributeError, OSError):
            try:
                # Per-Monitor DPI awareness v1 (需要 Windows 8.1+)
                ctypes.windll.shcore.SetProcessDpiAwareness(1)
                print("已启用 DPI 感知 (Per-Monitor v1)")
                return True
            except (AttributeError, OSError):
                try:
                    # System DPI awareness (适用于旧版 Windows)
                    ctypes.windll.user32.SetProcessDPIAware()
                    print("已启用 DPI 感知 (System)")
                    return True
                except (AttributeError, OSError):
                    print("无法启用 DPI 感知，可能在非 Windows 或旧版 Windows 上运行")
                    return False
    return False # 非 Windows 系统

# 主函数
def main():
    print("Starting application...")
    try:
        # 确保我们在主线程中运行
        if threading.current_thread() is not threading.main_thread():
            print("错误: 必须在主线程中运行 Tkinter 应用")
            return

        print("尝试启用 DPI 感知...")
        enable_dpi_awareness()

        print("创建根窗口...")
        root = tk.Tk()
        # 隐藏默认的空窗口直到 App 初始化完成
        root.withdraw() 

        print("创建应用程序实例...")
        app = UpperMonitorApp(root) # UpperMonitorApp 会处理窗口的 geometry 和 minsize

        print("设置关闭协议...")
        root.protocol("WM_DELETE_WINDOW", app.on_closing)

        # 捕获Ctrl+C事件
        def signal_handler(sig, frame):
            print(f"收到信号 {sig}，正在关闭应用程序...")
            # 确保在主线程调用 on_closing
            root.after(0, app.on_closing)

        # 在支持的平台上注册信号处理
        supported_signals = [signal.SIGINT, signal.SIGTERM]
        for sig in supported_signals:
             if hasattr(signal, sig.name): # 检查信号是否在当前平台定义
                 try:
                     signal.signal(sig, signal_handler)
                     print(f"已注册信号处理: {sig.name}")
                 except (ValueError, OSError) as e:
                     print(f"注册信号 {sig.name} 失败: {e}")
             else:
                 print(f"信号 {sig.name} 在当前平台不可用")


        print("启动主循环...")
        # 在主循环开始前显示窗口
        root.deiconify() 
        root.mainloop()
        print("主循环结束")

    except Exception as e:
        print(f"应用程序发生严重错误: {e}")
        import traceback
        traceback.print_exc()
        # 可以在这里添加错误日志记录
        sys.exit(1)

if __name__ == "__main__":
    print("脚本启动")
    main()
    print("脚本结束")