#!/usr/bin/env python
# -*- coding: utf-8 -*-

import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import datetime
import csv

# 数据库查看窗口
class DatabaseViewerWindow:
    def __init__(self, parent, db, dpi_scale=1.0): # 接收 dpi_scale 参数
        self.top = tk.Toplevel(parent)
        self.top.title("数据库记录查看器")
        self.dpi_scale = dpi_scale # 保存传入的 dpi_scale
        # 考虑 DPI 缩放调整初始大小
        # try:
        #     # 不再自行计算，使用传入的 dpi_scale
        #     # dpi_scale = self.top.tk.call('tk', 'scaling')
        # except tk.TclError:
        #     dpi_scale = 1.0
        initial_width = int(800 * self.dpi_scale)
        initial_height = int(600 * self.dpi_scale)
        min_width = int(800 * self.dpi_scale)
        min_height = int(600 * self.dpi_scale)
        self.top.geometry(f"{initial_width}x{initial_height}")
        self.top.minsize(min_width, min_height)
        
        self.top.grab_set()  # 使窗口为模态
        
        self.db = db # 传入 Database 实例
        self.create_widgets()
        self.load_data()
    
    def create_widgets(self):
        # 创建主框架, padding 也使用 dpi_scale
        main_frame = ttk.Frame(self.top, padding=int(10 * self.dpi_scale))
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # 顶部控制区域
        control_frame = ttk.Frame(main_frame)
        control_frame.pack(fill=tk.X, padx=int(5 * self.dpi_scale), pady=int(5 * self.dpi_scale))
        
        # 日期选择, padx 也使用 dpi_scale
        ttk.Label(control_frame, text="起始日期:").pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        self.start_date_var = tk.StringVar()
        # Entry width 是字符数，通常不需要缩放，但 padx 需要
        ttk.Entry(control_frame, textvariable=self.start_date_var, width=20).pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        ttk.Label(control_frame, text="(YYYY-MM-DD HH:MM:SS)").pack(side=tk.LEFT, padx=int(2 * self.dpi_scale))
        
        ttk.Label(control_frame, text="结束日期:").pack(side=tk.LEFT, padx=int(10 * self.dpi_scale))
        self.end_date_var = tk.StringVar()
        ttk.Entry(control_frame, textvariable=self.end_date_var, width=20).pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        ttk.Label(control_frame, text="(YYYY-MM-DD HH:MM:SS)").pack(side=tk.LEFT, padx=int(2 * self.dpi_scale))
        
        # 搜索按钮, padx 也使用 dpi_scale
        ttk.Button(control_frame, text="搜索", command=self.search_data).pack(side=tk.LEFT, padx=int(10 * self.dpi_scale))
        
        # 刷新按钮, padx 也使用 dpi_scale
        ttk.Button(control_frame, text="刷新", command=self.load_data).pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        
        # 清空按钮, padx 也使用 dpi_scale
        ttk.Button(control_frame, text="清空数据库", command=self.clear_database).pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        
        # 导出按钮, padx 也使用 dpi_scale
        ttk.Button(control_frame, text="导出CSV", command=self.export_csv).pack(side=tk.LEFT, padx=int(5 * self.dpi_scale))
        
        # 中部表格区域
        table_frame = ttk.Frame(main_frame)
        table_frame.pack(fill=tk.BOTH, expand=True, padx=int(5 * self.dpi_scale), pady=int(5 * self.dpi_scale))
        
        # 创建表格
        columns = ("id", "timestamp", "noise_db", "temperature", "humidity", "light_intensity")
        self.tree = ttk.Treeview(table_frame, columns=columns, show="headings")
        
        # 设置列标题
        self.tree.heading("id", text="ID")
        self.tree.heading("timestamp", text="时间戳")
        self.tree.heading("noise_db", text="噪声(dB)")
        self.tree.heading("temperature", text="温度(°C)")
        self.tree.heading("humidity", text="湿度(%)")
        self.tree.heading("light_intensity", text="光照(lux)")
        
        # 设置列宽 (使用传入的 self.dpi_scale)
        # dpi_scale = getattr(self, 'dpi_scale', 1.0) # 不再需要 getattr
        self.tree.column("id", width=int(50 * self.dpi_scale))
        self.tree.column("timestamp", width=int(150 * self.dpi_scale))
        self.tree.column("noise_db", width=int(80 * self.dpi_scale))
        self.tree.column("temperature", width=int(80 * self.dpi_scale))
        self.tree.column("humidity", width=int(80 * self.dpi_scale))
        self.tree.column("light_intensity", width=int(100 * self.dpi_scale))
        
        # 添加滚动条
        scrollbar = ttk.Scrollbar(table_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscroll=scrollbar.set)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        # 状态栏
        self.status_var = tk.StringVar(value="就绪")
        status_bar = ttk.Label(main_frame, textvariable=self.status_var, anchor=tk.W)
        status_bar.pack(fill=tk.X, padx=int(5 * self.dpi_scale), pady=int(2 * self.dpi_scale))

        # 配置主框架的行列权重，使表格区域可伸缩
        main_frame.rowconfigure(1, weight=1) # 表格区域在第1行 (0是控制区)
        main_frame.columnconfigure(0, weight=1)
        table_frame.rowconfigure(0, weight=1)
        table_frame.columnconfigure(0, weight=1)

    
    def load_data(self, data=None):
        """加载数据到表格"""
        # 清空表格
        for item in self.tree.get_children():
            self.tree.delete(item)
        
        # 获取数据
        if data is None:
            data = self.db.get_all_readings()
        
        # 填充表格
        for row in data:
            self.tree.insert("", tk.END, values=row)
        
        self.status_var.set(f"显示 {len(data)} 条记录")
    
    def search_data(self):
        """按日期范围搜索数据"""
        start_date = self.start_date_var.get().strip()
        end_date = self.end_date_var.get().strip()
        
        if not start_date and not end_date:
            self.load_data()
            return
        
        # 验证日期格式
        date_format = "%Y-%m-%d %H:%M:%S"
        try:
            if start_date:
                datetime.datetime.strptime(start_date, date_format)
            if end_date:
                datetime.datetime.strptime(end_date, date_format)
        except ValueError:
            messagebox.showerror("错误", "日期格式无效，请使用 YYYY-MM-DD HH:MM:SS 格式")
            return
        
        # 搜索数据
        data = self.db.search_readings(start_date, end_date)
        self.load_data(data)
    
    def clear_database(self):
        """清空数据库"""
        if messagebox.askyesno("确认", "确定要清空所有数据吗？此操作不可撤销！"):
            self.db.clear_all_data()
            self.load_data([])
            messagebox.showinfo("成功", "数据库已清空")
    
    def export_csv(self):
        """导出数据为CSV文件"""
        # 获取保存路径
        file_path = filedialog.asksaveasfilename(
            defaultextension=".csv",
            filetypes=[("CSV文件", "*.csv"), ("所有文件", "*.*")],
            title="保存数据为CSV"
        )
        
        if not file_path:
            return
        
        # 获取当前显示的数据
        data = []
        for item in self.tree.get_children():
            values = self.tree.item(item, "values")
            data.append(values)
        
        try:
            with open(file_path, 'w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                # 写入表头
                writer.writerow(["ID", "时间戳", "噪声(dB)", "温度(°C)", "湿度(%)", "光照(lux)"])
                # 写入数据
                writer.writerows(data)
            
            messagebox.showinfo("成功", f"数据已导出到 {file_path}")
        except Exception as e:
            messagebox.showerror("错误", f"导出失败: {e}")

if __name__ == '__main__':
    # 简单的测试代码
    class MockDatabase:
        def get_all_readings(self):
            return [
                (1, '2024-01-01 10:00:00', 55.5, 25.0, 60.0, 500.0),
                (2, '2024-01-01 10:01:00', 56.0, 25.1, 60.5, 510.0),
            ]
        def search_readings(self, start_date=None, end_date=None, limit=1000):
             return [(3, '2024-01-01 10:02:00', 57.0, 25.2, 61.0, 520.0)] if start_date else self.get_all_readings()
        def clear_all_data(self):
            print("Mock clear_all_data called")
        
    root = tk.Tk()
    root.withdraw() # 隐藏主测试窗口
    db_mock = MockDatabase()
    # 测试时也传递一个 dpi_scale (例如 1.0 或 1.5)
    app = DatabaseViewerWindow(root, db_mock, dpi_scale=1.5)
    root.mainloop()