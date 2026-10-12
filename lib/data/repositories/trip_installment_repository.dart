import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/trip_installment_model.dart';

class TripInstallmentRepository {
  final DatabaseHelper _databaseHelper;
  final Uuid _uuid = const Uuid();

  TripInstallmentRepository({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  Future<List<TripInstallmentModel>> getInstallmentsForEvent(String eventId) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'trip_installments',
      where: 'event_id = ?',
      whereArgs: [eventId],
      orderBy: 'installment_number ASC, person_id ASC',
    );
    return results.map((m) => TripInstallmentModel.fromMap(m)).toList();
  }

  Future<void> setInstallmentPaidStatus({
    required String id,
    required bool isPaid,
    double? paidAmount,
  }) async {
    final db = await _databaseHelper.database;
    await db.update(
      'trip_installments',
      {
        'is_paid': isPaid ? 1 : 0,
        'paid_amount': ?paidAmount,
        'paid_at': isPaid ? DateTime.now().millisecondsSinceEpoch : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> batchSaveInstallments(
    String eventId,
    List<TripInstallmentModel> installments,
  ) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'trip_installments',
        where: 'event_id = ?',
        whereArgs: [eventId],
      );

      for (final inst in installments) {
        final id = inst.id.isEmpty ? _uuid.v4() : inst.id;
        final map = inst.copyWith(id: id, eventId: eventId).toMap();
        await txn.insert('trip_installments', map);
      }
    });
  }

  Future<void> deleteInstallmentsForEvent(String eventId) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'trip_installments',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }
}
