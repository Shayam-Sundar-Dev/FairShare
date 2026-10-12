import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fairshare/data/database/database_helper.dart';
import 'package:fairshare/data/repositories/category_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late CategoryRepository categoryRepo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchema(db);
    DatabaseHelper.setDatabaseForTesting(db);

    categoryRepo = CategoryRepository();
  });

  tearDown(() async {
    await db.close();
  });

  test('default categories are seeded into the database', () async {
    final expenseCats = await categoryRepo.getCategories(type: 'expense');
    final eventCats = await categoryRepo.getCategories(type: 'event');

    expect(expenseCats.isNotEmpty, isTrue);
    expect(eventCats.isNotEmpty, isTrue);

    // Verify all seeded categories have isDefault == true
    for (final cat in expenseCats) {
      expect(cat.isDefault, isTrue);
    }
  });

  test('can add a custom category and query it', () async {
    final newCat = await categoryRepo.addCategory(
      name: 'Pet Supplies',
      type: 'expense',
      iconCode: Icons.pets_rounded.codePoint,
      colorValue: const Color(0xFF2A9D8F).toARGB32(),
    );

    expect(newCat.name, 'Pet Supplies');
    expect(newCat.isDefault, isFalse);

    final expenseCats = await categoryRepo.getCategories(type: 'expense');
    final found = expenseCats.where((c) => c.name == 'Pet Supplies');
    expect(found.isNotEmpty, isTrue);
    expect(found.first.color.toARGB32(), const Color(0xFF2A9D8F).toARGB32());
  });

  test('cannot delete default categories but can delete custom categories', () async {
    final expenseCats = await categoryRepo.getCategories(type: 'expense');
    final defaultCat = expenseCats.first;

    // Attempt to delete default category
    final deleteDefaultResult = await categoryRepo.deleteCategory(defaultCat.id);
    expect(deleteDefaultResult, isFalse);

    // Add a custom category
    final customCat = await categoryRepo.addCategory(
      name: 'Gaming',
      type: 'expense',
      iconCode: Icons.sports_esports_rounded.codePoint,
    );

    // Delete custom category
    final deleteCustomResult = await categoryRepo.deleteCategory(customCat.id);
    expect(deleteCustomResult, isTrue);

    final afterDelete = await categoryRepo.getCategories(type: 'expense');
    expect(afterDelete.any((c) => c.id == customCat.id), isFalse);
  });
}
