/// 强智教务考试安排跨 iframe 异步穿透拉取 JS 状态机片段
///
/// 职责单一：封装考试查询外壳页 (`/jsxsd/xsks/xsksap_query`) 元数据解析、目标子页 URL
/// 组装及多候选学期 GET/POST 权威空表判定的异步状态机。
class ExamSyncScriptFragment {
  static const String examScheduleAsyncJs = r'''
      function extractExamQueryMeta(qDoc) {
        var meta = { iframeUrl: null, xnxqid: '' };
        if (!qDoc) return meta;

        try {
          var iframes = qDoc.querySelectorAll('iframe, frame');
          for (var f = 0; f < iframes.length; f++) {
            var src = (iframes[f].getAttribute('src') || '').trim();
            if (src && src !== 'about:blank' && (src.indexOf('xsksap_list') !== -1 || src.indexOf('xsks') !== -1)) {
              meta.iframeUrl = src;
              break;
            }
          }
        } catch(e) {}

        try {
          // 必须优先精确查找学年学期下拉框，严禁使用 ', select' 导致误命中前序考试类别下拉框(#xqlbmc)
          var sel =
            qDoc.querySelector('select[name="xnxqid"]') ||
            qDoc.querySelector('#xnxqid') ||
            qDoc.querySelector('select[name="xnxq01id"]') ||
            qDoc.querySelector('#xnxq01id');

          if (!sel) {
            var allSels = qDoc.querySelectorAll('select');
            for (var si = 0; si < allSels.length; si++) {
              var opts = allSels[si].querySelectorAll('option');
              for (var oi = 0; oi < opts.length; oi++) {
                if (/^\d{4}-\d{4}-\d+$/.test((opts[oi].value || '').trim())) {
                  sel = allSels[si];
                  break;
                }
              }
              if (sel) break;
            }
          }

          if (sel) {
            var opt = sel.querySelector('option[selected]');
            if (opt && (opt.value || '').trim()) {
              meta.xnxqid = opt.value.trim();
            } else if (typeof sel.value === 'string' && /^\d{4}-\d{4}-\d+$/.test(sel.value.trim())) {
              meta.xnxqid = sel.value.trim();
            } else if (sel.options && sel.options.length > 0) {
              for (var k = 0; k < sel.options.length; k++) {
                var v = (sel.options[k].value || '').trim();
                if (/^\d{4}-\d{4}-\d+$/.test(v)) {
                  meta.xnxqid = v;
                  break;
                }
              }
              if (!meta.xnxqid) {
                for (var k2 = 0; k2 < sel.options.length; k2++) {
                  var v2 = (sel.options[k2].value || '').trim();
                  if (v2) {
                    meta.xnxqid = v2;
                    break;
                  }
                }
              }
            }
          }
        } catch(e) {}

        return meta;
      }

      function buildExamTargetUrl(iframeUrl, sem) {
        var targetUrl = '/jsxsd/xsks/xsksap_list';
        if (iframeUrl) {
          targetUrl = iframeUrl;
          if (targetUrl.indexOf('/') !== 0 && targetUrl.indexOf('http') !== 0) {
            targetUrl = '/jsxsd/xsks/' + targetUrl;
          }
        }
        if (sem) {
          if (/[?&]xnxqid=/.test(targetUrl)) {
            targetUrl = targetUrl.replace(/([?&]xnxqid=)[^&]*/, '$1' + encodeURIComponent(sem));
          } else {
            targetUrl += (targetUrl.indexOf('?') !== -1 ? '&' : '?') + 'xnxqid=' + encodeURIComponent(sem);
          }
        }
        return targetUrl;
      }

      async function fetchExamScheduleAsync(fallbackSemester, gradesList, currentUrl) {
        var hadTransportError = false;
        var confirmedEmptyExamList = false;

        function isAuthoritativeExamListDoc(doc) {
          if (!doc) return false;
          var exTable = findTableAcrossFrames(doc, function(d) {
            return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
          });
          if (!exTable) return false;
          var trs = exTable.querySelectorAll('tr');
          if (!trs || trs.length === 0) return false;
          for (var r = 0; r < Math.min(trs.length, 3); r++) {
            var thText = (trs[r].textContent || '').replace(/\s+/g, '');
            if (thText.indexOf('课程名称') !== -1 || thText.indexOf('考试课程') !== -1 || thText.indexOf('考试时间') !== -1) {
              return true;
            }
          }
          if ((exTable.textContent || '').indexOf('未查询到数据') !== -1) {
            return true;
          }
          return false;
        }

        // 0. 若当前处于考试查询页且 DOM 内已直接渲染出考试行，直接提取返回
        if (currentUrl && currentUrl.indexOf('/jsxsd/xsks/') !== -1 && typeof document !== 'undefined') {
          if (checkAuth(document, null, currentUrl)) {
            return { exams: [], status: 'not_logged_in', error: null };
          }
          var liveExams = parseQiangZhiExams(document);
          if (liveExams && liveExams.length > 0) {
            return { exams: liveExams, status: 'ok', error: null };
          }
        }

        // 1. 优先请求考试查询外壳页 /jsxsd/xsks/xsksap_query 提取默认激活学年学期 (xnxqid) 与内嵌 iframe 地址
        var qDoc = null;
        var queryHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_query', 12000);
        if (queryHtml === null) {
          hadTransportError = true;
        } else {
          qDoc = new DOMParser().parseFromString(queryHtml, 'text/html');
          if (checkAuth(qDoc, queryHtml, null)) {
            return { exams: [], status: 'not_logged_in', error: null };
          }
          var queryExams = parseQiangZhiExams(qDoc);
          if (queryExams && queryExams.length > 0) {
            return { exams: queryExams, status: 'ok', error: null };
          }
        }

        var queryMeta = extractExamQueryMeta(qDoc);
        var liveMeta = (currentUrl && currentUrl.indexOf('/jsxsd/xsks/') !== -1 && typeof document !== 'undefined')
          ? extractExamQueryMeta(document)
          : { iframeUrl: null, xnxqid: '' };
        var iframeUrl = queryMeta.iframeUrl || liveMeta.iframeUrl;

        // 2. 汇总候选学年学期列表 (按 考试外壳页选中学期 -> 当前页选中学期 -> 教务顶栏/课表学期 -> 最新成绩学期 优先级去重)
        var candidateSemesters = [];
        function addCandidateSem(s) {
          var trimmed = (s || '').trim();
          if (trimmed && candidateSemesters.indexOf(trimmed) === -1) {
            candidateSemesters.push(trimmed);
          }
        }
        addCandidateSem(liveMeta.xnxqid);
        addCandidateSem(queryMeta.xnxqid);
        addCandidateSem(fallbackSemester);
        if (Array.isArray(gradesList) && gradesList.length > 0) {
          var sems = gradesList
            .map(function(g) { return (g && g.semester ? String(g.semester) : '').trim(); })
            .filter(function(s) { return s.length > 0; })
            .sort();
          if (sems.length > 0) {
            addCandidateSem(sems[sems.length - 1]);
          }
        }

        // 3. 携带学年学期参数请求 /jsxsd/xsks/xsksap_list
        for (var cIdx = 0; cIdx < candidateSemesters.length; cIdx++) {
          var sem = candidateSemesters[cIdx];
          var targetUrl = buildExamTargetUrl(iframeUrl, sem);

          var getHtml = await fetchHtmlAsync(targetUrl, 12000);
          if (getHtml === null) {
            hadTransportError = true;
          } else {
            var getDoc = new DOMParser().parseFromString(getHtml, 'text/html');
            if (checkAuth(getDoc, getHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var getExams = parseQiangZhiExams(getDoc);
            if (getExams && getExams.length > 0) {
              return { exams: getExams, status: 'ok', error: null };
            }
            if (isAuthoritativeExamListDoc(getDoc)) {
              confirmedEmptyExamList = true;
            }
          }

          var postHtml = await fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list', 'xnxqid=' + encodeURIComponent(sem), 12000);
          if (postHtml === null) {
            hadTransportError = true;
          } else {
            var postDoc = new DOMParser().parseFromString(postHtml, 'text/html');
            if (checkAuth(postDoc, postHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var postExams = parseQiangZhiExams(postDoc);
            if (postExams && postExams.length > 0) {
              return { exams: postExams, status: 'ok', error: null };
            }
            if (isAuthoritativeExamListDoc(postDoc)) {
              confirmedEmptyExamList = true;
            }
          }

          var postFullHtml = await fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list', 'xqlbmc=&xnxqid=' + encodeURIComponent(sem), 12000);
          if (postFullHtml === null) {
            hadTransportError = true;
          } else {
            var postFullDoc = new DOMParser().parseFromString(postFullHtml, 'text/html');
            if (checkAuth(postFullDoc, postFullHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var postFullExams = parseQiangZhiExams(postFullDoc);
            if (postFullExams && postFullExams.length > 0) {
              return { exams: postFullExams, status: 'ok', error: null };
            }
            if (isAuthoritativeExamListDoc(postFullDoc)) {
              confirmedEmptyExamList = true;
            }
          }
        }

        // 4. 终极保底：无参数 GET /jsxsd/xsks/xsksap_list
        if (candidateSemesters.length === 0 || !confirmedEmptyExamList) {
          var fallbackHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_list', 12000);
          if (fallbackHtml === null) {
            hadTransportError = true;
          } else {
            var fbDoc = new DOMParser().parseFromString(fallbackHtml, 'text/html');
            if (checkAuth(fbDoc, fallbackHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var fbExams = parseQiangZhiExams(fbDoc);
            if (fbExams && fbExams.length > 0) {
              return { exams: fbExams, status: 'ok', error: null };
            }
            if (candidateSemesters.length === 0 && isAuthoritativeExamListDoc(fbDoc)) {
              confirmedEmptyExamList = true;
            }
          }
        }

        if (!hadTransportError && confirmedEmptyExamList) {
          return { exams: [], status: 'empty', error: null };
        }
        return {
          exams: [],
          status: 'error',
          error: hadTransportError
            ? '考试安排网络请求失败或部分响应异常，已保留本地缓存'
            : '未找到考试表格(#dataList)，教务页面可能已改版'
        };
      }
  ''';
}
