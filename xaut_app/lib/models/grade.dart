class GradeItem {
  final String semester;
  final String courseCode;
  final String courseName;
  final String score;
  final double credit;
  final double gpa;
  final String category;
  final String examType;

  const GradeItem({
    required this.semester,
    required this.courseCode,
    required this.courseName,
    required this.score,
    required this.credit,
    required this.gpa,
    required this.category,
    required this.examType,
  });

  factory GradeItem.fromJson(Map<String, dynamic> json) {
    final rawCourseName = json['courseName'];
    if (rawCourseName is! String || rawCourseName.trim().isEmpty) {
      throw const FormatException('GradeItem JSON 缺少有效的课程名称 (courseName)');
    }
    final hasCoreGradeField = json['score'] is String ||
        json['grade'] is String ||
        json['credit'] is num;
    if (!hasCoreGradeField) {
      throw const FormatException('GradeItem JSON 缺少成绩或学分核心字段');
    }

    final rawScore = json['score'] is String
        ? json['score'] as String
        : (json['grade'] is String ? json['grade'] as String : '');
    final rawSemester = json['semester'];
    final rawCourseCode = json['courseCode'];
    final rawCredit = json['credit'];
    final rawGpa = json['gpa'];
    final rawCategory = json['category'];
    final rawExamType = json['examType'];

    return GradeItem(
      semester: rawSemester is String ? rawSemester : '',
      courseCode: rawCourseCode is String ? rawCourseCode : '',
      courseName: rawCourseName,
      score: rawScore,
      credit: rawCredit is num ? rawCredit.toDouble() : 0.0,
      gpa: rawGpa is num ? rawGpa.toDouble() : -1.0,
      category: rawCategory is String ? rawCategory : '',
      examType: rawExamType is String ? rawExamType : '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'semester': semester,
      'courseCode': courseCode,
      'courseName': courseName,
      'score': score,
      'credit': credit,
      'gpa': gpa,
      'category': category,
      'examType': examType,
    };
  }
}

class GradeSummary {
  final int totalCourses;
  final double totalCredits;
  final double averageScore;
  final double averageGpa;

  const GradeSummary({
    required this.totalCourses,
    required this.totalCredits,
    required this.averageScore,
    required this.averageGpa,
  });

  factory GradeSummary.fromJson(Map<String, dynamic> json) {
    final rawTotalCourses = json['totalCourses'];
    final rawTotalCredits = json['totalCredits'];
    final rawAverageScore = json['averageScore'];
    final rawAverageGpa = json['averageGpa'];
    return GradeSummary(
      totalCourses: rawTotalCourses is num ? rawTotalCourses.toInt() : 0,
      totalCredits: rawTotalCredits is num ? rawTotalCredits.toDouble() : 0.0,
      averageScore: rawAverageScore is num ? rawAverageScore.toDouble() : 0.0,
      averageGpa: rawAverageGpa is num ? rawAverageGpa.toDouble() : 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalCourses': totalCourses,
      'totalCredits': totalCredits,
      'averageScore': averageScore,
      'averageGpa': averageGpa,
    };
  }
}
