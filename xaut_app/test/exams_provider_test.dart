import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/providers/exams_provider.dart';

ExamItem _makeExam({
  required String courseName,
  required String examTime,
  String room = '曲江10-101',
  String campus = '曲江校区',
  String batch = '期末考试',
  String courseCode = 'CS101',
  String teacher = '任课教师',
}) {
  return ExamItem(
    campus: campus,
    batch: batch,
    courseCode: courseCode,
    courseName: courseName,
    teacher: teacher,
    examTime: examTime,
    room: room,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ExamsProvider Smart Sorting & Countdown Tests', () {
    final fixedNow = DateTime(2026, 11, 10, 10, 0, 0); // 2026-11-10 10:00

    test('ExamItem evaluateStatus categorizes exam times accurately', () {
      // 1. 正在考试中: 2026-11-10 09:30 ~ 11:30
      final ongoingExam = _makeExam(
        courseName: '操作系统',
        examTime: '2026-11-10 09:30~11:30',
        room: '曲江10-101',
      );
      final statusOngoing = ongoingExam.evaluateStatus(fixedNow);
      expect(statusOngoing.status, equals(ExamStatus.ongoing));
      expect(statusOngoing.badgeText, equals('考试中'));

      // 2. 今天下午考试: 2026-11-10 14:00 ~ 16:00
      final todayExam = _makeExam(
        courseName: '计算机网络',
        examTime: '2026-11-10 14:00~16:00',
        room: '曲江10-102',
      );
      final statusToday = todayExam.evaluateStatus(fixedNow);
      expect(statusToday.status, equals(ExamStatus.today));
      expect(statusToday.badgeText, equals('今天'));

      // 3. 明天考试: 2026-11-11 08:30 ~ 10:30
      final tomorrowExam = _makeExam(
        courseName: '数据库系统',
        examTime: '2026-11-11 08:30~10:30',
        room: '曲江10-103',
      );
      final statusTomorrow = tomorrowExam.evaluateStatus(fixedNow);
      expect(statusTomorrow.status, equals(ExamStatus.tomorrow));
      expect(statusTomorrow.badgeText, equals('明天'));

      // 4. 4天后考试: 2026-11-14 14:00 ~ 16:00
      final upcomingExam = _makeExam(
        courseName: '编译原理',
        examTime: '2026-11-14 14:00~16:00',
        room: '曲江10-104',
      );
      final statusUpcoming = upcomingExam.evaluateStatus(fixedNow);
      expect(statusUpcoming.status, equals(ExamStatus.upcoming));
      expect(statusUpcoming.badgeText, equals('还有 4 天'));

      // 5. 昨天已考完: 2026-11-09 14:00 ~ 16:00
      final finishedExam = _makeExam(
        courseName: '线性代数',
        examTime: '2026-11-09 14:00~16:00',
        room: '曲江10-105',
      );
      final statusFinished = finishedExam.evaluateStatus(fixedNow);
      expect(statusFinished.status, equals(ExamStatus.finished));
      expect(statusFinished.badgeText, equals('已结束'));

      // 6. 待定考试: 时间为空或无效
      final unscheduledExam = _makeExam(
        courseName: '软件工程综合实训',
        examTime: '时间待定',
        room: '待定',
      );
      final statusUnscheduled = unscheduledExam.evaluateStatus(fixedNow);
      expect(statusUnscheduled.status, equals(ExamStatus.unscheduled));
      expect(statusUnscheduled.badgeText, equals('时间待定'));
    });

    test('sortExams orders upcoming first (ascending), unscheduled middle, finished bottom', () {
      final list = [
        _makeExam(courseName: '已考完科目', examTime: '2026-11-05 14:00~16:00'),
        _makeExam(courseName: '大后天考试', examTime: '2026-11-13 08:30~10:30'),
        _makeExam(courseName: '今天下午考试', examTime: '2026-11-10 14:00~16:00'),
        _makeExam(courseName: '时间待定科目', examTime: '时间待定'),
        _makeExam(courseName: '明天考试', examTime: '2026-11-11 08:30~10:30'),
      ];

      final sorted = ExamsProvider.sortExams(list, fixedNow);

      expect(sorted[0].courseName, equals('今天下午考试'));
      expect(sorted[1].courseName, equals('明天考试'));
      expect(sorted[2].courseName, equals('大后天考试'));
      expect(sorted[3].courseName, equals('时间待定科目'));
      expect(sorted[4].courseName, equals('已考完科目'));
    });

    test('ExamsProvider correctly computes upcomingCount with injected nowProvider', () async {
      final provider = ExamsProvider(nowProvider: () => fixedNow);

      // 注入 3 门考试：1 门今天，1 门大后天，1 门已结束
      final sampleExams = [
        _makeExam(courseName: '考试A', examTime: '2026-11-10 14:00~16:00'),
        _makeExam(courseName: '考试B', examTime: '2026-11-13 08:30~10:30'),
        _makeExam(courseName: '考试C', examTime: '2026-11-01 14:00~16:00'),
      ];

      await provider.updateExams(sampleExams);

      expect(provider.upcomingCount, equals(2));
      expect(provider.exams.first.courseName, equals('考试A'));
      expect(provider.exams.last.courseName, equals('考试C'));
    });
  });
}
