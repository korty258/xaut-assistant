#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
强智教务系统 (智校园 APP 原生接口) 探测与调用工具
参考: Letki/QZAPI_Archive, WindRunnerMax/SHST, cdfmlr/qzgo
"""

import requests
import json
import sys
import argparse

DEFAULT_BASE_URL = "http://jwgl.xaut.edu.cn"

class QiangZhiAppClient:
    def __init__(self, base_url=DEFAULT_BASE_URL, timeout=8):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Linux; U; Android 12; zh-cn) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Mobile Safari/537.36",
            "Accept": "application/json, text/javascript, */*",
        })
        self.token = None
        self.user_info = None

    def probe_api(self):
        """探测学校服务器是否开放了 /app.do 接口"""
        url = f"{self.base_url}/app.do"
        print(f"[+] 正在探测强智 App 接口: {url}")
        try:
            # 尝试访问 getCurrentTime 或基础参数
            res = self.session.get(url, params={"method": "getCurrentTime", "currDate": "2024-09-01"}, timeout=self.timeout)
            print(f"[+] 响应状态码: {res.status_code}")
            print(f"[+] 响应头 Content-Type: {res.headers.get('Content-Type')}")
            print(f"[+] 响应内容预览: {res.text[:200]}")
            
            # 判断是否返回了 JSON
            try:
                data = res.json()
                print("[√] 成功！该系统开放了标准的强智移动端 app.do 接口。")
                return True, data
            except Exception:
                if "404" in res.text or res.status_code == 404:
                    print("[-] 接口返回 404，学校可能未部署 app.do 接口模块或关闭了外网映射。")
                elif "统一身份认证" in res.text or "ids.xaut.edu.cn" in res.text:
                    print("[-] 接口被重定向到统一身份认证 (CAS/IDS)，需采用方案 B (WebView/Cookie 模式)。")
                else:
                    print(f"[-] 返回内容非标准 JSON (可能是 HTML 报错页或内网拦截页)。")
                return False, res.text
        except requests.exceptions.RequestException as e:
            print(f"[!] 网络请求失败: {e}")
            print("[*] 提示: 西安理工大学教务系统可能需要校内校园网或连接学校 VPN 才能直连。")
            return False, str(e)

    def login(self, xh, pwd):
        """
        调用 app.do?method=authUser 登录
        """
        url = f"{self.base_url}/app.do"
        params = {
            "method": "authUser",
            "xh": xh,
            "pwd": pwd
        }
        res = self.session.get(url, params=params, timeout=self.timeout)
        data = res.json()
        # 强智 app 登录返回字段通常包含 token, flag, msg 等
        if data.get("success") is True or data.get("token") or data.get("flag") == "1":
            self.token = data.get("token")
            self.user_info = data
            self.session.headers.update({"token": self.token})
            print(f"[√] 登录成功！获取到 Token: {self.token}")
            return True, data
        else:
            msg = data.get("msg") or data.get("message") or "未知原因"
            print(f"[-] 登录失败: {msg}")
            return False, data

    def get_current_time(self, curr_date=""):
        """获取当前学年、学期、周次"""
        url = f"{self.base_url}/app.do"
        params = {
            "method": "getCurrentTime",
            "currDate": curr_date
        }
        headers = {"token": self.token} if self.token else {}
        res = self.session.get(url, params=params, headers=headers, timeout=self.timeout)
        return res.json()

    def get_schedule(self, xh, xnxqid, zc):
        """
        查询指定周次课表
        :param xh: 学号
        :param xnxqid: 学年学期 (如 2024-2025-1)
        :param zc: 周次 (如 1)
        """
        url = f"{self.base_url}/app.do"
        params = {
            "method": "getKbcxAzc",
            "xh": xh,
            "xnxqid": xnxqid,
            "zc": zc
        }
        headers = {"token": self.token} if self.token else {}
        res = self.session.get(url, params=params, headers=headers, timeout=self.timeout)
        return res.json()

    def get_grades(self, xh, xnxqid=""):
        """查询成绩"""
        url = f"{self.base_url}/app.do"
        params = {
            "method": "getCjcx",
            "xh": xh,
            "xnxqid": xnxqid
        }
        headers = {"token": self.token} if self.token else {}
        res = self.session.get(url, params=params, headers=headers, timeout=self.timeout)
        return res.json()

    def get_exams(self, xh, xnxqid=""):
        """查询考试安排"""
        url = f"{self.base_url}/app.do"
        params = {
            "method": "getKscx",
            "xh": xh,
            "xnxqid": xnxqid
        }
        headers = {"token": self.token} if self.token else {}
        res = self.session.get(url, params=params, headers=headers, timeout=self.timeout)
        return res.json()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="强智教务移动端 API (app.do) 测试工具")
    parser.add_argument("--url", default=DEFAULT_BASE_URL, help="教务系统地址 (默认: http://jwgl.xaut.edu.cn)")
    parser.add_argument("--probe", action="store_true", help="探测 app.do 是否开放")
    parser.add_argument("--xh", help="学生学号")
    parser.add_argument("--pwd", help="登录密码")
    parser.add_argument("--semester", default="", help="学年学期代码，如 2024-2025-1")
    parser.add_argument("--week", default="1", help="查询周次")
    
    args = parser.parse_args()
    client = QiangZhiAppClient(base_url=args.url)

    if args.probe or (not args.xh):
        client.probe_api()
        if not args.xh:
            print("\n[i] 提示: 若需要测试完整登录与拉取课表，请使用参数: python qiangzhi_probe.py --xh 你的学号 --pwd 你的密码")
            sys.exit(0)

    # 登录测试
    success, res = client.login(args.xh, args.pwd)
    if success:
        time_info = client.get_current_time()
        print(f"[+] 当前教学周期信息: {json.dumps(time_info, ensure_ascii=False)}")
        
        sem = args.semester or time_info.get("xnxqid", "")
        if sem:
            print(f"[+] 获取第 {args.week} 周课表...")
            kb = client.get_schedule(args.xh, sem, args.week)
            print(f"[+] 课表结果数量: {len(kb) if isinstance(kb, list) else '未知'}")
            print(json.dumps(kb, ensure_ascii=False, indent=2))
