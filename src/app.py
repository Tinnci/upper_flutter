#!/usr/bin/env python
# -*- coding: utf-8 -*-

import tkinter as tk
from tkinter import ttk, messagebox
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.animation import FuncAnimation
import queue
import threading
import time
import sys # 需要 sys.exit
import datetime # 导入 datetime 模块

# 从其他模块导入类
from database import Database
from communication import WiFiCommunication
from ui_components import DatabaseViewerWindow

# 上位机GUI类
class UpperMonitorApp:
    def __init__(self, root):
        self.root = root
        self.root.title("环境监测上位机系统")

        # 获取 DPI 缩放因子 (需要 Tk 8.6+)
        try:
            # 使用winfo_fpixels获取更精确的缩放比例
            # tk.call('tk', 'scaling') 可能在某些系统/版本不准确
            # 像素点 / 点 = 缩放比例 (例如 96 dpi 时为 1.0)
            pixels = self.root.winfo_fpixels('1i') # 获取1英寸对应的像素数
            self.dpi_scale = pixels / 72.0 # Tkinter内部通常使用72点/英寸
            if self.dpi_scale <= 0: # 安全检查
                 raise tk.TclError("Invalid DPI scale")
            print(f"Calculated Tkinter DPI Scale (winfo_fpixels/72): {self.dpi_scale}")
            # 限制最大缩放比例为 1.25 (125%)
            max_scale = 1.25
            if self.dpi_scale > max_scale:
                print(f"Scaling factor {self.dpi_scale:.2f} exceeds max {max_scale:.2f}. Limiting to {max_scale:.2f}.")
                self.dpi_scale = max_scale
            print(f"Using effective DPI Scale: {self.dpi_scale}")
        except tk.TclError:
             try:
                 # 备用方法
                 self.dpi_scale = float(self.root.tk.call('tk', 'scaling')) # 确保是浮点数
                 print(f"Calculated Tkinter DPI Scale (tk scaling): {self.dpi_scale}")
                 # 同样限制最大缩放比例
                 max_scale = 1.25
                 if self.dpi_scale > max_scale:
                     print(f"Scaling factor {self.dpi_scale:.2f} exceeds max {max_scale:.2f}. Limiting to {max_scale:.2f}.")
                     self.dpi_scale = max_scale
                 print(f"Using effective DPI Scale: {self.dpi_scale}")
             except tk.TclError:
                 self.dpi_scale = 1.0 # 最终备用
                 print("无法获取 Tkinter 缩放因子，使用默认值 1.0")

        # 根据缩放因子调整初始窗口大小
        initial_width = int(1000 * self.dpi_scale)
        initial_height = int(600 * self.dpi_scale)
        min_width = int(800 * self.dpi_scale)
        min_height = int(600 * self.dpi_scale)
        self.root.geometry(f"{initial_width}x{initial_height}")
        self.root.minsize(min_width, min_height)

        # 初始化数据库和通信对象
        self.db = Database()
        self.wifi_comm = WiFiCommunication()

        # 当前通信方式
        self.comm_mode = tk.StringVar(value="wifi")

        # 当前传感器数据
        self.current_data = {
            'noise_db': 0.0,
            'temperature': 0.0,
            'humidity': 0.0,
            'light_intensity': 0.0
        }

        # 数据接收标志
        self.receiving_data = False

        # 数据队列，用于线程间安全通信
        self.data_queue = queue.Queue()

        # 状态变量
        self.status_var = tk.StringVar(value="就绪")

        # 创建界面
        self.create_widgets()

        # 创建图表
        self.create_charts()

        # 启动数据队列处理循环
        self.after_id = None # 用于存储 after 调度的 ID
        self.start_queue_processing()

        # 绑定窗口大小变化事件
        self.root.bind('<Configure>', self.on_resize)
        self._resize_debounce_id = None # 用于 resize 事件防抖

    def init_animation(self):
        """初始化图表动画"""
        def update(frame):
            """动画更新函数"""
            readings = self.db.get_latest_readings(30)
            if not readings:
                # 如果没有数据，返回当前的线条对象，避免blit错误
                return self.noise_line, self.temp_line, self.humidity_line, self.light_line

            # 提取时间戳并转换为 datetime 对象
            # readings 的顺序是 (id, timestamp, noise, temp, humidity, light)
            # 注意：数据库返回的数据是倒序的（最新的在前），绘图时需要反转
            readings.reverse() # 反转列表，让时间从左到右递增
            timestamps_str = [r[1] for r in readings]
            try:
                times = [datetime.datetime.strptime(ts, "%Y-%m-%d %H:%M:%S") for ts in timestamps_str]
            except ValueError as e:
                 print(f"时间格式错误: {e}, 数据: {timestamps_str}")
                 # 如果时间格式错误，返回空线条避免崩溃
                 return self.noise_line, self.temp_line, self.humidity_line, self.light_line

            noise_data = [r[2] for r in readings]
            temp_data = [r[3] for r in readings]
            humidity_data = [r[4] for r in readings]
            light_data = [r[5] for r in readings]

            self.noise_line.set_data(times, noise_data)
            self.temp_line.set_data(times, temp_data)
            self.humidity_line.set_data(times, humidity_data)
            self.light_line.set_data(times, light_data)

            for ax, data in [
                (self.axes[0, 0], noise_data),
                (self.axes[0, 1], temp_data),
                (self.axes[1, 0], humidity_data),
                (self.axes[1, 1], light_data)
            ]:
                if data:
                    ax.relim()
                    ax.autoscale_view()
                # ax.set_xlim(0, max(1, len(times) - 1)) # 移除固定 xlim，让其自动滚动

            return self.noise_line, self.temp_line, self.humidity_line, self.light_line

        self.animation = FuncAnimation(
            self.fig,
            update,
            interval=1000,
            blit=False, # 禁用 blit 以允许坐标轴滚动
            cache_frame_data=False
        )

    def process_data_queue(self):
        """处理数据队列"""
        try:
            while not self.data_queue.empty():
                data = self.data_queue.get_nowait()
                self.current_data = data
                self.db.insert_reading(
                    data['noise_db'],
                    data['temperature'],
                    data['humidity'],
                    data['light_intensity']
                )
                self.update_ui_values()
                self.data_queue.task_done()
        except queue.Empty:
            pass
        except Exception as e:
            print(f"处理数据队列时出错: {e}")

    def update_ui_values(self):
        """更新UI显示值"""
        self.noise_label.config(text=f"{self.current_data['noise_db']:.1f}")
        self.temp_label.config(text=f"{self.current_data['temperature']:.1f}")
        self.humidity_label.config(text=f"{self.current_data['humidity']:.1f}")
        self.light_label.config(text=f"{self.current_data['light_intensity']:.1f}")

    def start_queue_processing(self):
        """启动定期处理数据队列的循环"""
        self.process_data_queue()
        self.after_id = self.root.after(100, self.start_queue_processing)

    def on_closing(self):
        """窗口关闭时的处理"""
        print("正在关闭应用程序...")
        self.receiving_data = False
        if hasattr(self, 'animation') and self.animation:
             try:
                 self.animation.event_source.stop()
                 print("动画已停止")
             except Exception as e:
                 print(f"停止动画时出错: {e}")
        if self.wifi_comm.is_connected:
            self.wifi_comm.disconnect()
        if not self.data_queue.empty():
            try:
                print("等待数据队列处理完成...")
                self.data_queue.join(timeout=1.0)
                print("数据队列处理完成")
            except Exception as e:
                print(f"等待数据队列完成时出错: {e}")
        if self.after_id:
            try:
                self.root.after_cancel(self.after_id)
                print("已取消 after 事件")
            except Exception as e:
                 print(f"取消 after 事件时发生错误: {e}")
        print("销毁主窗口...")
        self.root.destroy()
        print("应用程序已关闭。")
        sys.exit(0) # 强制退出进程确保完全关闭

    def create_charts(self):
        """创建图表"""
        try:
            plt.rcParams['font.sans-serif'] = ['SimHei']
            plt.rcParams['axes.unicode_minus'] = False
        except Exception as e:
            print(f"设置 Matplotlib 中文字体失败: {e}. 可能需要安装 SimHei 字体。")
        plt.rcParams['axes.grid'] = True
        plt.rcParams['grid.alpha'] = 0.3

        # Matplotlib 的 DPI 设置应与 Tkinter 的物理像素密度匹配
        # 使用 adjusted_dpi = self.root.winfo_fpixels('1i') 可能更准确
        adjusted_dpi = self.root.winfo_fpixels('1i') # 使用屏幕的实际DPI
        print(f"使用的 Matplotlib DPI: {adjusted_dpi}")

        # figsize 单位是英寸，需要根据 DPI 调整以获得期望的像素大小
        # 例如，期望图表宽度为 800 像素：figsize_width = 800 / adjusted_dpi
        fig_width_pixels = 800 * self.dpi_scale # 期望宽度像素
        fig_height_pixels = 500 * self.dpi_scale # 期望高度像素
        figsize_w = fig_width_pixels / adjusted_dpi
        figsize_h = fig_height_pixels / adjusted_dpi

        self.fig, self.axes = plt.subplots(2, 2, figsize=(figsize_w, figsize_h), dpi=adjusted_dpi)
        self.fig.set_constrained_layout(True)

        plot_config = {'linewidth': 1.5 * self.dpi_scale, 'alpha': 0.8} # 线宽也缩放
        title_fontsize = 10 * self.dpi_scale
        label_fontsize = 8 * self.dpi_scale
        tick_labelsize = 8 * self.dpi_scale

        lines = [
            self.axes[0, 0].plot([], [], 'r-', **plot_config)[0],
            self.axes[0, 1].plot([], [], 'b-', **plot_config)[0],
            self.axes[1, 0].plot([], [], 'g-', **plot_config)[0],
            self.axes[1, 1].plot([], [], 'y-', **plot_config)[0]
        ]
        self.noise_line, self.temp_line, self.humidity_line, self.light_line = lines

        titles = ['噪声分贝', '温度', '湿度', '光照强度']
        xlabels = ['时间'] * 4 # 修改 X 轴标签
        ylabels = ['分贝 (dB)', '温度 (°C)', '湿度 (%)', '光照 (lux)']
        axs = self.axes.flatten()

        for i, ax in enumerate(axs):
            ax.set_title(titles[i], fontsize=title_fontsize)
            ax.set_xlabel(xlabels[i], fontsize=label_fontsize)
            ax.set_ylabel(ylabels[i], fontsize=label_fontsize)
            ax.tick_params(labelsize=tick_labelsize)

        self.init_animation()

        self.canvas = FigureCanvasTkAgg(self.fig, master=self.root)
        self.canvas_widget = self.canvas.get_tk_widget()
        self.canvas_widget.grid(row=4, column=0, columnspan=2, sticky=(tk.W, tk.E, tk.N, tk.S), pady=int(5 * self.dpi_scale)) # pady 也应缩放
        # 确保 grid 布局先生效
        self.root.update_idletasks()
        # 初始绘制延迟，确保在 Tkinter 空闲时执行绘制
        self.root.after_idle(self.canvas.draw_idle)


    def create_widgets(self):
        """创建界面控件"""
        # 使用 ttk.Style 来管理样式和缩放
        style = ttk.Style(self.root)
        # print(f"Theme names: {style.theme_names()}")
        # print(f"Current theme: {style.theme_use()}")
        # 尝试使用 'clam', 'alt', 'default', 'vista' 等主题看效果
        try:
             # 在Windows上 'vista' 或 'xpnative' 通常能更好地处理DPI
             if sys.platform == "win32":
                 style.theme_use('vista')
             else:
                 # 其他系统尝试 'clam' 或 'alt'
                 current_theme = style.theme_use()
                 if 'clam' in style.theme_names():
                     style.theme_use('clam')
                 elif 'alt' in style.theme_names():
                     style.theme_use('alt')
                 else:
                     style.theme_use(current_theme) # 保持默认
             print(f"Using theme: {style.theme_use()}")
        except tk.TclError as e:
             print(f"Failed to set theme: {e}")

        # 根据DPI调整默认字体大小
        default_font = tk.font.nametofont("TkDefaultFont")
        default_font.configure(size=int(10 * self.dpi_scale)) # 基础大小10
        self.root.option_add("*Font", default_font)

        # 主框架
        main_frame = ttk.Frame(self.root, padding=int(10 * self.dpi_scale))
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(4, weight=1) # 图表行占满剩余空间

        # --- 通信控制 ---
        control_frame = ttk.LabelFrame(main_frame, text="通信控制", padding=int(5 * self.dpi_scale))
        control_frame.grid(row=0, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=int(5 * self.dpi_scale))
        control_frame.columnconfigure(9, weight=1) # 让状态标签前的空间可扩展

        ttk.Label(control_frame, text="通信方式:").grid(row=0, column=0, padx=int(5 * self.dpi_scale))
        self.comm_mode_radio2 = ttk.Radiobutton(control_frame, text="WiFi", variable=self.comm_mode, value="wifi", command=self.update_comm_ui)
        self.comm_mode_radio2.grid(row=0, column=1, padx=int(2 * self.dpi_scale))

        self.wifi_frame = ttk.Frame(control_frame)
        self.wifi_frame.grid(row=0, column=2, columnspan=4, padx=int(5 * self.dpi_scale))

        ttk.Label(self.wifi_frame, text="IP地址:").pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        self.host_var = tk.StringVar(value="192.168.1.100")
        self.host_combo = ttk.Combobox(self.wifi_frame, textvariable=self.host_var, width=15)
        self.host_combo.pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))

        ttk.Label(self.wifi_frame, text="端口:").pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        self.wifi_port_var = tk.StringVar(value="8266")
        wifi_port_entry = ttk.Entry(self.wifi_frame, textvariable=self.wifi_port_var, width=5)
        wifi_port_entry.pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))

        self.scan_btn = ttk.Button(self.wifi_frame, text="扫描设备", command=self.scan_devices)
        self.scan_btn.pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))

        self.connect_var = tk.StringVar(value="连接")
        self.connect_btn = ttk.Button(control_frame, textvariable=self.connect_var, command=self.toggle_connection)
        self.connect_btn.grid(row=0, column=6, padx=int(5 * self.dpi_scale))

        self.status_label = ttk.Label(control_frame, textvariable=self.status_var)
        self.status_label.grid(row=0, column=9, padx=int(5 * self.dpi_scale), sticky=tk.E)

        # --- 数据管理 ---
        delete_frame = ttk.LabelFrame(main_frame, text="数据管理", padding=int(5 * self.dpi_scale))
        delete_frame.grid(row=1, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=int(5 * self.dpi_scale))

        self.view_db_btn = ttk.Button(delete_frame, text="查看数据库", command=self.open_database_viewer)
        self.view_db_btn.grid(row=0, column=0, padx=int(5 * self.dpi_scale))

        self.delete_all_btn = ttk.Button(delete_frame, text="删除所有数据", command=self.delete_all_data)
        self.delete_all_btn.grid(row=0, column=1, padx=int(5 * self.dpi_scale))

        ttk.Label(delete_frame, text="删除天数前的数据:").grid(row=0, column=2, padx=int(5 * self.dpi_scale))
        self.days_var = tk.StringVar(value="7")
        days_entry = ttk.Entry(delete_frame, textvariable=self.days_var, width=5)
        days_entry.grid(row=0, column=3, padx=int(5 * self.dpi_scale))
        self.delete_old_btn = ttk.Button(delete_frame, text="删除", command=self.delete_old_data)
        self.delete_old_btn.grid(row=0, column=4, padx=int(5 * self.dpi_scale))

        # --- 实时数据 ---
        data_frame = ttk.LabelFrame(main_frame, text="实时数据", padding=int(5 * self.dpi_scale))
        data_frame.grid(row=2, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=int(5 * self.dpi_scale))

        ttk.Label(data_frame, text="噪声 (dB):").grid(row=0, column=0, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W)
        self.noise_label = ttk.Label(data_frame, text="--", width=10, anchor=tk.E)
        self.noise_label.grid(row=0, column=1, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W+tk.E)

        ttk.Label(data_frame, text="温度 (°C):").grid(row=1, column=0, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W)
        self.temp_label = ttk.Label(data_frame, text="--", width=10, anchor=tk.E)
        self.temp_label.grid(row=1, column=1, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W+tk.E)

        ttk.Label(data_frame, text="湿度 (%):").grid(row=2, column=0, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W)
        self.humidity_label = ttk.Label(data_frame, text="--", width=10, anchor=tk.E)
        self.humidity_label.grid(row=2, column=1, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W+tk.E)

        ttk.Label(data_frame, text="光照 (lux):").grid(row=3, column=0, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W)
        self.light_label = ttk.Label(data_frame, text="--", width=10, anchor=tk.E)
        self.light_label.grid(row=3, column=1, padx=int(5 * self.dpi_scale), pady=int(2*self.dpi_scale), sticky=tk.W+tk.E)
        data_frame.columnconfigure(1, weight=1) # 让数据显示列扩展

        # 初始化界面状态
        self.update_comm_ui()

    def update_comm_ui(self):
        """更新通信UI"""
        # 目前只有 WiFi，无需操作，但保留以备扩展
        pass

    def toggle_connection(self):
        """连接或断开通信"""
        if self.wifi_comm.is_connected or self.receiving_data:
            self.receiving_data = False
            # 启动一个短计时器来确保接收线程有机会退出循环
            self.root.after(100, self._disconnect_wifi)
        else:
            host = self.host_var.get()
            try:
                port = int(self.wifi_port_var.get())
            except ValueError:
                 messagebox.showerror("错误", "端口号必须是数字")
                 return

            if not host:
                messagebox.showerror("错误", "请输入IP地址")
                return

            # 在后台线程尝试连接，避免阻塞UI
            threading.Thread(target=self._connect_wifi, args=(host, port), daemon=True).start()
            self.status_var.set(f"正在连接到 {host}:{port}...")
            self.connect_btn.configure(state='disabled') # 禁用按钮直到连接完成

    def _connect_wifi(self, host, port):
        """在后台线程执行WiFi连接"""
        if self.wifi_comm.connect(host, port):
            self.root.after(0, self._on_wifi_connected, host, port) # 回到主线程更新UI
        else:
            self.root.after(0, self._on_wifi_connect_failed, host, port)

    def _on_wifi_connected(self, host, port):
        """WiFi连接成功后在主线程更新UI"""
        self.connect_var.set("断开")
        self.receiving_data = True
        self.status_var.set(f"已连接到WiFi {host}:{port}")
        self.connect_btn.configure(state='normal')
        # 启动数据接收线程
        threading.Thread(target=self.receive_data_thread, daemon=True).start()

    def _on_wifi_connect_failed(self, host, port):
        """WiFi连接失败后在主线程更新UI"""
        messagebox.showerror("错误", f"无法连接到WiFi {host}:{port}")
        self.status_var.set("连接失败")
        self.connect_btn.configure(state='normal')

    def _disconnect_wifi(self):
         """执行实际的WiFi断开操作"""
         if self.wifi_comm.is_connected:
             self.wifi_comm.disconnect()
         self.connect_var.set("连接")
         self.status_var.set("已断开连接")
         self.connect_btn.configure(state='normal') # 重新启用连接按钮


    def receive_data_thread(self):
        """接收数据的线程"""
        print("数据接收线程启动")
        while self.receiving_data:
            data = None
            if self.wifi_comm.is_connected:
                # print("尝试从WiFi读取数据...") # 减少打印频率
                data = self.wifi_comm.read_data()

            if data:
                # print(f"成功获取数据: {data}") # 减少打印频率
                self.data_queue.put(data)
            # else:
                # print("未获取到数据") # 减少打印频率

            time.sleep(1) # 每秒尝试读取一次
        print("数据接收线程结束")


    def open_database_viewer(self):
        """打开数据库查看窗口"""
        # 传递 self.db 实例和 dpi_scale 给新窗口
        DatabaseViewerWindow(self.root, self.db, dpi_scale=self.dpi_scale)

    def delete_all_data(self):
        if messagebox.askyesno("确认", "确定要删除所有数据吗？此操作不可恢复！"):
            try:
                self.db.clear_all_data()
                messagebox.showinfo("成功", "所有数据已删除")
            except Exception as e:
                 messagebox.showerror("错误", f"删除数据时出错: {e}")

    def delete_old_data(self):
        try:
            days = int(self.days_var.get())
            if days <= 0:
                messagebox.showerror("错误", "请输入大于0的天数")
                return

            if messagebox.askyesno("确认", f"确定要删除{days}天前的所有数据吗？此操作不可恢复！"):
                try:
                    self.db.delete_data_before(days)
                    messagebox.showinfo("成功", f"{days}天前的数据已删除")
                except Exception as e:
                    messagebox.showerror("错误", f"删除旧数据时出错: {e}")
        except ValueError:
            messagebox.showerror("错误", "请输入有效的天数")

    def scan_devices(self):
        """扫描网络中的可用设备"""
        self.status_var.set("正在扫描设备...")
        self.scan_btn.configure(state='disabled')
        self.connect_btn.configure(state='disabled') # 扫描时也禁用连接
        self.root.update_idletasks() # 确保UI更新

        def scan_thread():
            devices = []
            error_msg = None
            try:
                network_prefix = self.wifi_comm.get_network_prefix()
                ip_range = [network_prefix + str(i) for i in range(1, 255)]
                print(f"开始扫描，IP范围: {ip_range[0]} 到 {ip_range[-1]}")
                devices = self.wifi_comm.scan_network(ip_range)
            except Exception as e:
                print(f"扫描出错: {e}")
                error_msg = f"扫描出错: {e}"
            finally:
                # 确保在主线程更新UI
                self.root.after(0, self._on_scan_complete, devices, error_msg)

        threading.Thread(target=scan_thread, daemon=True).start()

    def _on_scan_complete(self, devices, error_msg):
        """扫描完成后在主线程更新UI"""
        if error_msg:
            self.status_var.set(error_msg)
        elif devices:
            self.host_combo['values'] = devices
            self.host_var.set(devices[0]) # 默认选中第一个找到的设备
            self.status_var.set(f"找到 {len(devices)} 个设备")
            print(f"找到设备: {devices}")
        else:
            self.status_var.set("未找到设备")
            print("未找到任何设备")
        self.scan_btn.configure(state='normal')
        self.connect_btn.configure(state='normal') # 重新启用连接按钮

    def on_resize(self, event=None):
        """处理窗口大小变化事件，使用防抖避免过于频繁的重绘"""
        if self._resize_debounce_id:
            self.root.after_cancel(self._resize_debounce_id)
        self._resize_debounce_id = self.root.after(150, self._do_resize_draw) # 增加延迟

    def _do_resize_draw(self):
        """实际执行重绘操作"""
        if hasattr(self, 'canvas') and self.canvas_widget.winfo_exists():
            # print("窗口大小改变，触发 Matplotlib 重绘 (draw_idle)") # 减少打印
            try:
                # 重新计算 figsize 可能有助于解决某些缩放问题
                # adjusted_dpi = self.root.winfo_fpixels('1i')
                # fig_width_pixels = self.canvas_widget.winfo_width() # 获取当前画布宽度
                # fig_height_pixels = self.canvas_widget.winfo_height() # 获取当前画布高度
                # figsize_w = fig_width_pixels / adjusted_dpi
                # figsize_h = fig_height_pixels / adjusted_dpi
                # self.fig.set_size_inches(figsize_w, figsize_h, forward=True)
                # print(f"Resized fig to inches: {figsize_w}x{figsize_h}")

                # 简单地调用 draw_idle 通常足够
                self.canvas.draw_idle()
            except Exception as e:
                print(f"重绘图表时出错: {e}")
        self._resize_debounce_id = None