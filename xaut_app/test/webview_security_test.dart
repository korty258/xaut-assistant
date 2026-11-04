import 'package:flutter_test/flutter_test.dart';
import 'package:xaut_app/screens/webview_login_screen.dart';

void main() {
  group('WebViewLoginScreen.isAllowedUrl 域名白名单与强制 HTTPS 安全门禁测试', () {
    test('放行合法的西理工 HTTPS 域名', () {
      expect(WebViewLoginScreen.isAllowedUrl('https://xaut.edu.cn'), isTrue);
      expect(WebViewLoginScreen.isAllowedUrl('https://xaut.edu.cn/'), isTrue);
      expect(WebViewLoginScreen.isAllowedUrl('https://jwgl.xaut.edu.cn/jsxsd/'), isTrue);
      expect(WebViewLoginScreen.isAllowedUrl('https://ids.xaut.edu.cn/authserver/login'), isTrue);
      expect(WebViewLoginScreen.isAllowedUrl('https://lib.xaut.edu.cn/index.html'), isTrue);
    });

    test('放行 about:blank 内核空白页', () {
      expect(WebViewLoginScreen.isAllowedUrl('about:blank'), isTrue);
      expect(WebViewLoginScreen.isAllowedUrl(' about:blank '), isTrue);
    });

    test('拦截空 URL 与畸形空 Host 请求', () {
      expect(WebViewLoginScreen.isAllowedUrl(''), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('   '), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('https:///'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('https:///path/to/page'), isFalse);
    });

    test('强制拦截非 HTTPS 明文 HTTP 请求 (防明文降级与窃听)', () {
      expect(WebViewLoginScreen.isAllowedUrl('http://xaut.edu.cn'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('http://jwgl.xaut.edu.cn/jsxsd/'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('http://ids.xaut.edu.cn/'), isFalse);
    });

    test('拦截仿冒钓鱼域名与非校内外部域名', () {
      // 类似 xaut.edu.cn.evil.com 钓鱼
      expect(WebViewLoginScreen.isAllowedUrl('https://xaut.edu.cn.attacker.com'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('https://xaut.edu.cn.evil.com/login'), isFalse);
      // 前缀欺骗 fakexaut.edu.cn
      expect(WebViewLoginScreen.isAllowedUrl('https://fakexaut.edu.cn'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('https://notxaut.edu.cn'), isFalse);
      // 普通外网域名
      expect(WebViewLoginScreen.isAllowedUrl('https://www.baidu.com'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('https://github.com'), isFalse);
    });

    test('拦截非 HTTP(S) 协议 (如 javascript: / file: 等)', () {
      expect(WebViewLoginScreen.isAllowedUrl('javascript:alert(1)'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('file:///C:/Windows/System32'), isFalse);
      expect(WebViewLoginScreen.isAllowedUrl('data:text/html,<html></html>'), isFalse);
    });
  });
}
