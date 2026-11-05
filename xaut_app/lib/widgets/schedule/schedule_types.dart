import '../../models/course.dart';

/// 课程卡片动态分栏定位布局项
class CourseLayoutItem {
  final Course course;
  final int subColIndex;
  final int totalSubCols;
  final List<Course> allClusterCourses;

  const CourseLayoutItem({
    required this.course,
    required this.subColIndex,
    required this.totalSubCols,
    this.allClusterCourses = const [],
  });
}

/// 智能计算多课程排布算法（智能聚类、本周优先、多课折叠、杜绝细条）
List<CourseLayoutItem> computeCourseLayout(List<Course> dayCourses, int currentWeek) {
  if (dayCourses.isEmpty) return [];

  // 1. 排序：按起始节次升序；相同时本周有课的优先靠前；持续节次长的优先
  final sorted = List<Course>.from(dayCourses)
    ..sort((a, b) {
      if (a.startSection != b.startSection) {
        return a.startSection.compareTo(b.startSection);
      }
      final aActive = a.isActiveInWeek(currentWeek) ? 1 : 0;
      final bActive = b.isActiveInWeek(currentWeek) ? 1 : 0;
      if (aActive != bActive) {
        return bActive.compareTo(aActive);
      }
      return b.stepCount.compareTo(a.stepCount);
    });

  // 2. 将在时间区间上存在重叠交集的课程聚类成簇 (Cluster)
  final clusters = <List<Course>>[];
  List<Course>? currentCluster;
  int clusterEndSection = 0;

  for (final course in sorted) {
    if (currentCluster == null || course.startSection > clusterEndSection) {
      currentCluster = [course];
      clusterEndSection = course.endSection;
      clusters.add(currentCluster);
    } else {
      currentCluster.add(course);
      if (course.endSection > clusterEndSection) {
        clusterEndSection = course.endSection;
      }
    }
  }

  // 3. 针对每个簇，分配互不冲突且移动端友好的展示卡片
  final result = <CourseLayoutItem>[];

  for (final cluster in clusters) {
    if (cluster.length == 1) {
      result.add(CourseLayoutItem(
        course: cluster.first,
        subColIndex: 0,
        totalSubCols: 1,
        allClusterCourses: cluster,
      ));
      continue;
    }

    // 簇内存在多门课程在时间区间上重叠或跨周轮替
    final activeCourses = cluster.where((c) => c.isActiveInWeek(currentWeek)).toList();

    if (activeCourses.isNotEmpty) {
      if (activeCourses.length == 1) {
        result.add(CourseLayoutItem(
          course: activeCourses.first,
          subColIndex: 0,
          totalSubCols: 1,
          allClusterCourses: cluster,
        ));
      } else {
        final displayCount = activeCourses.length > 2 ? 2 : activeCourses.length;
        for (int i = 0; i < displayCount; i++) {
          result.add(CourseLayoutItem(
            course: activeCourses[i],
            subColIndex: i,
            totalSubCols: displayCount,
            allClusterCourses: cluster,
          ));
        }
      }
    } else {
      final sortedByProximity = List<Course>.from(cluster)
        ..sort((a, b) {
          final distA = a.weeks.isEmpty
              ? 999
              : a.weeks.map((w) => (w - currentWeek).abs()).reduce((x, y) => x < y ? x : y);
          final distB = b.weeks.isEmpty
              ? 999
              : b.weeks.map((w) => (w - currentWeek).abs()).reduce((x, y) => x < y ? x : y);
          if (distA != distB) return distA.compareTo(distB);
          return a.startSection.compareTo(b.startSection);
        });

      result.add(CourseLayoutItem(
        course: sortedByProximity.first,
        subColIndex: 0,
        totalSubCols: 1,
        allClusterCourses: cluster,
      ));
    }
  }

  return result;
}
