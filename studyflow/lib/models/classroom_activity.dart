class ClassroomActivity {
  const ClassroomActivity({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.title,
    required this.description,
    required this.workType,
    required this.state,
    required this.isCompleted,
    this.alternateLink,
    this.dueAt,
  });

  final String id;
  final String courseId;
  final String courseName;
  final String title;
  final String description;
  final String workType;
  final String state;
  final bool isCompleted;
  final String? alternateLink;
  final DateTime? dueAt;
}

class ClassroomSnapshot {
  const ClassroomSnapshot({
    required this.activities,
    required this.fetchedAt,
    required this.courseCount,
  });

  final List<ClassroomActivity> activities;
  final DateTime fetchedAt;
  final int courseCount;
}
