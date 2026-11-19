/// 强智教务 WebView 注入脚本基础 JS 片段集合
///
/// 职责单一：集中维护 Origin 安全守卫、CAS 登录态检测以及跨端异步通信 / Fetch / 教学周回退
/// 运行时辅助脚本，供 [SyncScriptBuilder] 按需组合。
class SyncScriptFragments {
  /// 顶层运行环境 Origin 白名单安全守卫（防范导航竞态与恶意外跳）
  static const String originGuardJs = r'''
    if (typeof window !== 'undefined' && window.location) {
      var proto = window.location.protocol;
      var host = (window.location.hostname || '').toLowerCase();
      if (proto !== 'https:' || !(host === 'xaut.edu.cn' || host.endsWith('.xaut.edu.cn'))) {
        throw new Error('Blocked script execution on untrusted origin: ' + window.location.href);
      }
    }
  ''';

  /// 统一提取的统一身份认证 (CAS) 与登录状态检测函数常量
  ///
  /// 单一定义原则：供所有跨模块异步拉取管线与单页同步注入脚本共享，杜绝多处拷贝维护
  static const String checkAuthJs = r'''
    function checkAuth(doc, html, url) {
      if (url && (url.indexOf('/authserver/login') !== -1 || url.indexOf('/authserver/') !== -1)) return true;
      if (doc) {
        if (doc.getElementById('casLoginForm')) return true;
        if (doc.querySelector('form[action*="authserver"]') || doc.querySelector('form[action*="login"]')) {
          if (doc.querySelector('input[name="username"]') && doc.querySelector('input[name="password"]')) {
            return true;
          }
        }
      }
      if (html && typeof html === 'string') {
        if (html.indexOf('casLoginForm') !== -1 || html.indexOf('/authserver/login') !== -1) return true;
      }
      return false;
    }
  ''';

  /// 跨端原生消息桥接、AbortController 任务管理、异步 Fetch 与教学周回退探测运行时
  ///
  /// 约定调用前已声明 `var reqId` 与 `var timeoutMs`。
  static const String bridgeRuntimeJs = r'''
      window.__jinhuaActiveTasks = window.__jinhuaActiveTasks || {};
      var taskState = { aborted: false, controllers: [] };
      if (reqId) {
        window.__jinhuaActiveTasks[reqId] = taskState;
      }

      if (!window.__jinhuaAbortTask) {
        window.__jinhuaAbortTask = function(id) {
          if (!id || !window.__jinhuaActiveTasks) return;
          var task = window.__jinhuaActiveTasks[id];
          if (task) {
            task.aborted = true;
            if (Array.isArray(task.controllers)) {
              for (var i = 0; i < task.controllers.length; i++) {
                try { task.controllers[i].abort(); } catch(e) {}
              }
            }
            delete window.__jinhuaActiveTasks[id];
          }
        };
      }

      if (!window.__jinhuaAbortAllTasks) {
        window.__jinhuaAbortAllTasks = function() {
          if (!window.__jinhuaActiveTasks) return;
          for (var id in window.__jinhuaActiveTasks) {
            if (Object.prototype.hasOwnProperty.call(window.__jinhuaActiveTasks, id)) {
              try { window.__jinhuaAbortTask(id); } catch(e) {}
            }
          }
          window.__jinhuaActiveTasks = {};
        };
      }

      function postToFlutter(msgObj) {
        try {
          if (taskState.aborted && msgObj && msgObj.type !== 'aborted') {
            return false;
          }
          if (typeof msgObj === 'object' && msgObj !== null) {
            if (reqId) {
              msgObj.requestId = reqId;
            }
          }
          var str = typeof msgObj === 'string' ? msgObj : JSON.stringify(msgObj);
          if (typeof window !== 'undefined') {
            if (window.JinhuaBridge && typeof window.JinhuaBridge.postMessage === 'function') {
              window.JinhuaBridge.postMessage(str);
              return true;
            }
            if (window.chrome && window.chrome.webview && typeof window.chrome.webview.postMessage === 'function') {
              window.chrome.webview.postMessage(str);
              return true;
            }
          }
        } catch(e) {}
        return false;
      }

      var deadline = Date.now() + timeoutMs;
      function remainingMs() {
        return Math.max(0, deadline - Date.now());
      }

      async function fetchHtmlAsync(url, optionsOrTimeout) {
        if (taskState.aborted || remainingMs() <= 0) {
          throw new Error('请求超时或已取消');
        }
        var opt = {};
        var maxStepMs = 15000;
        if (typeof optionsOrTimeout === 'number') {
          maxStepMs = optionsOrTimeout;
        } else if (optionsOrTimeout && typeof optionsOrTimeout === 'object') {
          opt = optionsOrTimeout;
          if (typeof opt.timeout === 'number') {
            maxStepMs = opt.timeout;
          }
        }
        var stepBudget = Math.min(maxStepMs || 15000, remainingMs());
        if (stepBudget <= 0) {
          throw new Error('请求超时或已取消');
        }
        try {
          var init = {
            method: opt.method || 'GET',
            credentials: 'include',
            headers: opt.headers || {}
          };
          if (opt.body) {
            init.body = opt.body;
          }
          if (typeof AbortController !== 'undefined') {
            var controller = new AbortController();
            init.signal = controller.signal;
            taskState.controllers.push(controller);
            var timeoutTimer = setTimeout(function() {
              try { controller.abort(); } catch(e) {}
            }, stepBudget);
            try {
              var resp = await fetch(url, init);
              clearTimeout(timeoutTimer);
              var cIdx = taskState.controllers.indexOf(controller);
              if (cIdx !== -1) taskState.controllers.splice(cIdx, 1);
              if (taskState.aborted) throw new Error('请求已取消');
              if (resp && resp.ok) {
                return await resp.text();
              }
            } catch(err) {
              clearTimeout(timeoutTimer);
              var cIdx2 = taskState.controllers.indexOf(controller);
              if (cIdx2 !== -1) taskState.controllers.splice(cIdx2, 1);
              if (taskState.aborted || remainingMs() <= 0) {
                throw new Error('请求超时或已取消');
              }
              return null;
            }
          } else {
            var resp = await fetch(url, init);
            if (taskState.aborted) throw new Error('请求已取消');
            if (resp && resp.ok) {
              return await resp.text();
            }
          }
        } catch(e) {
          if (taskState.aborted || remainingMs() <= 0) {
            throw new Error('请求超时或已取消');
          }
        }
        return null;
      }

      async function fetchHtmlAsyncPost(url, data, maxStepMs) {
        return await fetchHtmlAsync(url, {
          method: 'POST',
          timeout: maxStepMs || 15000,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
          },
          body: data
        });
      }

      async function resolveTeachingWeekWithFallbackAsync(doc, currentUrl) {
        var allowSelect = currentUrl.indexOf('/jsxsd/xskb/') === -1;
        var info = parseQiangZhiTeachingWeek(doc, allowSelect);
        if (info && info.currentWeek) {
          return info;
        }

        var probeUrls = [
          '/jsxsd/framework/xsMain_new.jsp?t1=1',
          '/jsxsd/framework/xsMain.jsp',
          '/jsxsd/framework/xsMain_10700.htmlx'
        ];
        for (var i = 0; i < probeUrls.length; i++) {
          if (taskState.aborted || remainingMs() <= 800) break;
          var html = await fetchHtmlAsync(probeUrls[i], 6000);
          if (html) {
            var pDoc = new DOMParser().parseFromString(html, 'text/html');
            var subInfo = parseQiangZhiTeachingWeek(pDoc, true);
            if (subInfo) {
              if (!info.semester && subInfo.semester) info.semester = subInfo.semester;
              if (subInfo.currentWeek) {
                info.currentWeek = subInfo.currentWeek;
                return info;
              }
            }
          }
        }

        // 终极保底：从强智教学周历 (/jsxsd/jxzl/jxzl_query) 提取第 1 周周一公历日期
        if (!taskState.aborted && remainingMs() > 800) {
          var calHtml = await fetchHtmlAsync('/jsxsd/jxzl/jxzl_query', 6000);
          if (calHtml) {
            var calDoc = new DOMParser().parseFromString(calHtml, 'text/html');
            var startStr = parseQiangZhiCalendarStart(calDoc);
            if (startStr) {
              info.semesterStartDate = startStr;
            }
            if (!info.semester) {
              var calSem = parseQiangZhiTeachingWeek(calDoc, false);
              if (calSem && calSem.semester) info.semester = calSem.semester;
            }
          }
        }

        return info;
      }
  ''';
}
