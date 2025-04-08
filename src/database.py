#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sqlite3
import datetime

# 数据库操作类
class Database:
    def __init__(self, db_name="sensor_data.db"):
        self.db_name = db_name
        # 在初始化时创建表结构
        conn = sqlite3.connect(self.db_name)
        cursor = conn.cursor()
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS sensor_readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            noise_db REAL,
            temperature REAL,
            humidity REAL,
            light_intensity REAL
        )
        ''')
        conn.commit()
        conn.close()
    
    def insert_reading(self, noise_db, temperature, humidity, light_intensity):
        """在当前线程中创建新的连接来插入数据"""
        with sqlite3.connect(self.db_name) as conn:
            cursor = conn.cursor()
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            cursor.execute('''
            INSERT INTO sensor_readings (timestamp, noise_db, temperature, humidity, light_intensity)
            VALUES (?, ?, ?, ?, ?)
            ''', (timestamp, noise_db, temperature, humidity, light_intensity))
    
    def get_latest_readings(self, limit=100):
        """在当前线程中创建新的连接来获取数据"""
        conn = sqlite3.connect(self.db_name)
        cursor = conn.cursor()
        cursor.execute('''
        SELECT * FROM sensor_readings ORDER BY id DESC LIMIT ?
        ''', (limit,))
        result = cursor.fetchall()
        conn.close()
        return result
        
    def get_all_readings(self):
        """获取所有数据记录"""
        conn = sqlite3.connect(self.db_name)
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM sensor_readings ORDER BY id DESC')
        result = cursor.fetchall()
        conn.close()
        return result
    
    def search_readings(self, start_date=None, end_date=None, limit=1000):
        """按日期范围搜索数据"""
        conn = sqlite3.connect(self.db_name)
        cursor = conn.cursor()
        
        if start_date and end_date:
            cursor.execute('''
            SELECT * FROM sensor_readings 
            WHERE timestamp BETWEEN ? AND ? 
            ORDER BY id DESC LIMIT ?
            ''', (start_date, end_date, limit))
        elif start_date:
            cursor.execute('''
            SELECT * FROM sensor_readings 
            WHERE timestamp >= ? 
            ORDER BY id DESC LIMIT ?
            ''', (start_date, limit))
        elif end_date:
            cursor.execute('''
            SELECT * FROM sensor_readings 
            WHERE timestamp <= ? 
            ORDER BY id DESC LIMIT ?
            ''', (end_date, limit))
        else:
            cursor.execute('''
            SELECT * FROM sensor_readings 
            ORDER BY id DESC LIMIT ?
            ''', (limit,))
            
        result = cursor.fetchall()
        conn.close()
        return result
    
    def clear_all_data(self):
        """清空所有数据"""
        conn = sqlite3.connect(self.db_name)
        cursor = conn.cursor()
        cursor.execute('DELETE FROM sensor_readings')
        conn.commit()
        conn.close()

    def delete_data_before(self, days):
        conn = sqlite3.connect(self.db_name)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM sensor_readings WHERE timestamp < datetime('now', ?)", (f'-{days} days',))
        conn.commit()
        conn.close()