import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/category_model.dart';
import '../../data/repositories/category_repository.dart';

class CategoryProvider extends ChangeNotifier {
  final CategoryRepository _categoryRepository;

  List<CategoryModel> _categories = [];
  bool _isLoading = false;
  String? _errorMessage;

  CategoryProvider({CategoryRepository? categoryRepository})
      : _categoryRepository = categoryRepository ?? CategoryRepository() {
    loadCategories();
  }

  List<CategoryModel> get categories => _categories;
  List<CategoryModel> get expenseCategories =>
      _categories.where((c) => c.type == 'expense').toList();
  List<CategoryModel> get eventCategories =>
      _categories.where((c) => c.type == 'event').toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadCategories() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _categories = await _categoryRepository.getCategories();
    } catch (e) {
      _errorMessage = 'Failed to load categories: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addCategory({
    required String name,
    required String type,
    required int iconCode,
    int? colorValue,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _errorMessage = 'Category name cannot be empty';
      notifyListeners();
      return false;
    }

    final exists = _categories.any((c) =>
        c.type == type && c.name.toLowerCase() == trimmedName.toLowerCase());
    if (exists) {
      _errorMessage = 'Category "$trimmedName" already exists';
      notifyListeners();
      return false;
    }

    try {
      final newCat = await _categoryRepository.addCategory(
        name: trimmedName,
        type: type,
        iconCode: iconCode,
        colorValue: colorValue,
      );
      _categories.add(newCat);
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add category: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCategory(String id) async {
    try {
      final success = await _categoryRepository.deleteCategory(id);
      if (success) {
        _categories.removeWhere((c) => c.id == id);
        _errorMessage = null;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = 'Failed to delete category: $e';
      notifyListeners();
      return false;
    }
  }

  IconData getExpenseIcon(String categoryName) {
    final cat = _categories.cast<CategoryModel?>().firstWhere(
          (c) => c?.type == 'expense' && c?.name == categoryName,
          orElse: () => null,
        );
    if (cat != null) {
      return cat.icon;
    }
    return ExpenseCategories.getIcon(categoryName);
  }

  Color getExpenseColor(String categoryName) {
    final cat = _categories.cast<CategoryModel?>().firstWhere(
          (c) => c?.type == 'expense' && c?.name == categoryName,
          orElse: () => null,
        );
    if (cat != null) {
      return cat.color;
    }
    return ExpenseCategories.getColor(categoryName);
  }

  IconData getEventIcon(String categoryName) {
    final cat = _categories.cast<CategoryModel?>().firstWhere(
          (c) => c?.type == 'event' && c?.name == categoryName,
          orElse: () => null,
        );
    if (cat != null) {
      return cat.icon;
    }
    return EventCategories.getIcon(categoryName);
  }

  Color getEventColor(String categoryName) {
    final cat = _categories.cast<CategoryModel?>().firstWhere(
          (c) => c?.type == 'event' && c?.name == categoryName,
          orElse: () => null,
        );
    if (cat != null) {
      return cat.color;
    }
    return EventCategories.getColor(categoryName);
  }
}
