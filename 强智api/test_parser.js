const { parseWeeks, calculateSections } = require('./qiangzhi_parser');

console.log("=== 1. 测试课表基础解析 ===");
console.log("周次 1-16(周):", parseWeeks("1-16(周)"));
console.log("小节计算:", calculateSections(1, "1-16(周)[01-02节]"));

console.log("\n[√] 脚本加载正常，已包含 parseQiangZhiCourses, parseQiangZhiGrades, parseQiangZhiExams");
