#!/usr/bin/env python
# -*- coding: utf-8 -*-

import socket
import json
import traceback
from concurrent.futures import ThreadPoolExecutor

# WiFi通信类
class WiFiCommunication:
    def __init__(self, host=None, port=8266, timeout=1):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.socket = None
        self.is_connected = False
    
    def connect(self, host=None, port=None):
        if host:
            self.host = host
        if port:
            self.port = port
        
        try:
            print(f"正在连接到 {self.host}:{self.port}...")
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(self.timeout)
            self.socket.connect((self.host, self.port))
            self.is_connected = True
            print("连接成功！")
            return True
        except Exception as e:
            print(f"WiFi连接失败: {e}")
            traceback.print_exc()
            self.is_connected = False
            return False
    
    def disconnect(self):
        if self.socket:
            try:
                print("正在断开连接...")
                self.socket.close()
                print("连接已断开")
            except Exception as e:
                print(f"断开连接时出错: {e}")
            finally:
                self.socket = None
                self.is_connected = False
    
    def read_data(self):
        """通过WiFi读取单片机发送的数据"""
        if not self.is_connected or not self.socket:
            print("未连接到设备，无法读取数据")
            return None
        
        try:
            print(f"正在从 {self.host}:{self.port} 读取数据...")
            
            # 发送获取数据的命令
            print("发送命令: GET_CURRENT")
            self.socket.send(b"GET_CURRENT\n")
            
            # 等待确认响应
            print("等待设备响应...")
            response = self.socket.recv(1024).decode()
            print(f"收到响应: {response}")
            
            # 处理多行JSON响应
            try:
                # 分割响应为多行
                json_strings = response.strip().split('\n')
                print(f"分割后的JSON字符串: {json_strings}")
                
                # 尝试解析每一行
                for json_str in json_strings:
                    try:
                        json_data = json.loads(json_str)
                        print(f"成功解析JSON数据: {json_data}")
                        
                        # 转换为标准格式
                        result = {
                            'noise_db': float(json_data['decibels']),
                            'temperature': float(json_data['temperature']),
                            'humidity': float(json_data['humidity']),
                            'light_intensity': float(json_data['lux'])
                        }
                        print(f"转换后的数据: {result}")
                        return result
                    except json.JSONDecodeError:
                        print(f"无法解析JSON字符串: {json_str}")
                        continue
                    except KeyError as e:
                        print(f"数据格式错误，缺少字段: {e}")
                        continue
                    except ValueError as e:
                        print(f"数据转换错误: {e}")
                        continue
                
                print("所有JSON解析尝试都失败了")
                return None
                
            except Exception as e:
                print(f"处理JSON响应时出错: {e}")
                return None
                
        except Exception as e:
            print(f"WiFi读取数据出错: {e}")
            traceback.print_exc()
            return None

    def scan_network(self, ip_range, port=8266):
        """扫描网络寻找可用设备"""
        available_devices = []
        print(f"开始扫描网络，IP范围: {ip_range[0]} 到 {ip_range[-1]}, 端口: {port}")
        
        def try_connect(ip):
            try:
                print(f"正在测试 {ip}...")
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(0.5)  # 快速超时
                result = sock.connect_ex((ip, port))
                sock.close()
                
                if result == 0:
                    print(f"发现可连接的设备: {ip}")
                    # 尝试获取数据验证是否是目标设备
                    test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    test_socket.settimeout(1)
                    try:
                        test_socket.connect((ip, port))
                        print(f"正在验证设备 {ip} 是否为目标设备...")
                        test_socket.send(b"GET_CURRENT\n")
                        response = test_socket.recv(1024).decode()
                        print(f"设备 {ip} 响应: {response}")
                        if response == "OK\n": # 假设设备响应 "OK\n" 表示是目标设备
                            print(f"确认为目标设备: {ip}")
                            available_devices.append(ip)
                    except Exception as e:
                        print(f"验证设备 {ip} 时出错: {e}")
                    finally:
                        test_socket.close()
            except Exception as e:
                print(f"连接到 {ip} 时出错: {e}")
        
        # 使用线程池加速扫描
        with ThreadPoolExecutor(max_workers=50) as executor:
            executor.map(try_connect, ip_range)
        
        print(f"扫描完成，找到 {len(available_devices)} 个设备: {available_devices}")
        return available_devices
    
    def get_network_prefix(self):
        """获取当前网络前缀"""
        try:
            # 创建一个UDP socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            # 连接一个公共IP（不会真正建立连接）
            s.connect(("8.8.8.8", 80))
            # 获取本机IP
            local_ip = s.getsockname()[0]
            s.close()
            print(f"当前本机IP: {local_ip}")
            # 返回网络前缀
            prefix = ".".join(local_ip.split(".")[:-1]) + "."
            print(f"使用网络前缀: {prefix}")
            return prefix
        except Exception as e:
            print(f"获取网络前缀出错: {e}，使用默认前缀: 192.168.1.")
            return "192.168.1."