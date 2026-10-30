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
    return GradeItem(
      semester: json['semester'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      score: json['score'] as String? ?? '',
      credit: (json['credit'] as num?)?.toDouble() ?? 0.0,
      gpa: (json['gpa'] as num?)?.toDouble() ?? 0.0,
      category: json['category'] as String? ?? '',
      examType: json['examType'] as String? ?? '',
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
    return GradeSummary(
      totalCourses: (json['totalCourses'] as num?)?.toInt() ?? 0,
      totalCredits: (json['totalCredits'] as num?)?.toDouble() ?? 0.0,
      averageScore: (json['averageScore'] as num?)?.toDouble() ?? 0.0,
      averageGpa: (json['averageGpa'] as num?)?.toDouble() ?? 0.0,
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
