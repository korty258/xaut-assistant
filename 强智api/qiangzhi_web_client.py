#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
强智教务 Web 端 (jsxsd) 爬虫客户端
结合 NJUST-JWC-Enhance 与 Dawn-Course 的网页请求逻辑与表格解析
"""

import requests
import base64
import re
from bs4 import BeautifulSoup
import json
import argparse

DEFAULT_HOST = "http://jwgl.xaut.edu.cn"

class QiangZhiWebClient:
    def __init__(self, host=DEFAULT_HOST):
        self.host = host.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
        })

    @staticmethod
    def encode_credentials(username, password):
        """
        强智教务系统经典的账号密码编码算法:
        base64(username) + "%%%" + base64(password)
        """
        u_b64 = base64.b64encode(username.encode("utf-8")).decode("utf-8")
        p_b64 = base64.b64encode(password.encode("utf-8")).decode("utf-8")
        return f"{u_b64}%%%{p_b64}"

    def login_direct(self, username, password):
        """
        强智内嵌登录入口 (/jsxsd/xk/LoginToXk)
        （适用于未强制开启统一认证，或内网直登入口）
        """
        login_url = f"{self.host}/jsxsd/xk/LoginToXk"
        encoded = self.encode_credentials(username, password)
        data = {
            "userAccount": username,
            "userPassword": password,
            "encoded": encoded
        }
        res = self.session.post(login_url, data=data, allow_redirects=True)
        # 判断登录是否成功 (通常跳转到 /jsxsd/framework/xsMain.html 或 xsMain.jsp)
        if "xsMain" in res.url or "学生个人中心" in res.text or "退出" in res.text:
            print("[√] Web 端直接登录成功！")
            return True
        else:
            print("[-] 账号密码登录失败，或该系统强制使用了学校统一身份认证 (CAS)。")
            return False

    def fetch_schedule_html(self, semester=""):
        """
        拉取学生课表页面
        :param semester: 学期代码，例如 '2024-2025-1'。为空时系统返回当前学期。
        """
        url = f"{self.host}/jsxsd/xskb/xskb_list.do"
        params = {}
        if semester:
            params["xnxq01id"] = semester
            
        res = self.session.get(url, params=params)
        return res.text

    def parse_schedule_html(self, html_content):
        """
        解析强智课表表格 (解析逻辑同 Dawn-Course 的 qiangzhi.js)
        """
        soup = BeautifulSoup(html_content, "html.parser")
        table = soup.find("table", id="timetable") or soup.find("table", id="kbtable")
        if not table:
            return {"error": "未找到课表表格 (#timetable 或 #kbtable)，可能登录态已失效或页面结构不符"}

        courses = []
        rows = table.find_all("tr")

        section_idx = 0
        for r_idx, row in enumerate(rows):
            tds = row.find_all("td")
            if not tds:
                continue

            section_idx += 1
            # 强智系统表格通常前几列为节次，后7列为星期一至星期日
            start_col = 0
            if len(tds) >= 8:
                start_col = len(tds) - 7

            for col_idx in range(start_col, len(tds)):
                day_of_week = (col_idx - start_col) + 1
                td = tds[col_idx]
                
                # 寻找课表内容容器
                kb_contents = td.find_all(class_=re.compile(r"kbcontent"))
                if not kb_contents:
                    # 如果没有 class，提取整个 td
                    text = td.get_text(separator="\n", strip=True)
                    if text and text != "&nbsp;":
                        courses.extend(self._parse_course_block(text, day_of_week, section_idx))
                else:
                    for kb in kb_contents:
                        text = kb.get_text(separator="\n", strip=True)
                        if text and text != "&nbsp;":
                            courses.extend(self._parse_course_block(text, day_of_week, section_idx))

        return courses

    def _parse_course_block(self, text, day_of_week, section_idx):
        """解析单元格内部的课程文本"""
        courses = []
        # 分隔多个课程
        blocks = text.split("---------------------")
        for blk in blocks:
            lines = [l.strip() for l in blk.strip().split("\n") if l.strip()]
            if not lines:
                continue

            name = lines[0]
            teacher = ""
            weeks_str = ""
            room = ""

            for line in lines[1:]:
                if "周" in line:
                    weeks_str = line
                elif any(kw in line for kw in ["楼", "教室", "馆", "室", "中心", "场"]):
                    room = line
                elif not teacher:
                    teacher = line
                elif not room:
                    room = line

            courses.append({
                "name": name,
                "teacher": teacher,
                "room": room,
                "day": day_of_week,
                "section": section_idx,
                "raw_weeks": weeks_str
            })
        return courses

    def fetch_grades_html(self, semester=""):
        """获取历年成绩页面"""
        url = f"{self.host}/jsxsd/kscj/cjcx_list"
        data = {"kksj": semester} if semester else {}
        res = self.session.post(url, data=data)
        return res.text


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="强智教务 Web 端 (jsxsd) 客户端测试")
    parser.add_argument("--host", default=DEFAULT_HOST, help="教务系统地址")
    parser.add_argument("--user", help="学号")
    parser.add_argument("--pwd", help="密码")
    parser.add_argument("--semester", default="", help="学年学期代码")
    parser.add_argument("--file", help="从本地 HTML 文件直接解析课表进行测试")

    args = parser.parse_args()
    client = QiangZhiWebClient(host=args.host)

    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            html = f.read()
        res = client.parse_schedule_html(html)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif args.user and args.pwd:
        if client.login_direct(args.user, args.pwd):
            html = client.fetch_schedule_html(args.semester)
            res = client.parse_schedule_html(html)
            print(f"[+] 解析出课程数: {len(res)}")
            print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print("[i] 用法示例:")
        print("  1. 登录并抓取课表: python qiangzhi_web_client.py --user 你的学号 --pwd 你的密码")
        print("  2. 解析本地保存的课表网页: python qiangzhi_web_client.py --file kbtable.html")
