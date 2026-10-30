class ExamItem {
  final String campus;
  final String batch;
  final String courseCode;
  final String courseName;
  final String teacher;
  final String examTime;
  final String room;

  const ExamItem({
    required this.campus,
    required this.batch,
    required this.courseCode,
    required this.courseName,
    required this.teacher,
    required this.examTime,
    required this.room,
  });

  factory ExamItem.fromJson(Map<String, dynamic> json) {
    return ExamItem(
      campus: json['campus'] as String? ?? '',
      batch: json['batch'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      teacher: json['teacher'] as String? ?? '',
      examTime: json['examTime'] as String? ?? '',
      room: json['room'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'campus': campus,
      'batch': batch,
      'courseCode': courseCode,
      'courseName': courseName,
      'teacher': teacher,
      'examTime': examTime,
      'room': room,
    };
  }
}
