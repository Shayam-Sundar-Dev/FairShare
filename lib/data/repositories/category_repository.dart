import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/category_model.dart';

class CategoryRepository {
  final DatabaseHelper _databaseHelper;
  final Uuid _uuid = const Uuid();

  CategoryRepository({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  Future<List<CategoryModel>> getCategories({String? type}) async {
    final db = await _databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: type != null ? 'type = ?' : null,
      whereArgs: type != null ? [type] : null,
      orderBy: 'is_default DESC, name ASC',
    );

    return maps.map((map) => CategoryModel.fromMap(map)).toList();
  }

  Future<CategoryModel> addCategory({
    required String name,
    required String type,
    required int iconCode,
    int? colorValue,
  }) async {
    final db = await _databaseHelper.database;
    final category = CategoryModel(
      id: _uuid.v4(),
      name: name.trim(),
      type: type,
      iconCode: iconCode,
      colorValue: colorValue,
      isDefault: false,
    );

    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return category;
  }

  Future<bool> deleteCategory(String id) async {
    final db = await _databaseHelper.database;
    // Protect default categories from deletion
    final count = await db.delete(
      'categories',
      where: 'id = ? AND is_default = 0',
      whereArgs: [id],
    );
    return count > 0;
  }
}
