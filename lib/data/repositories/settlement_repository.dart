import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/settlement_model.dart';

class SettlementRepository {
  final DatabaseHelper _databaseHelper;
  final Uuid _uuid = const Uuid();

  SettlementRepository({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  Future<List<SettlementModel>> getSettlementsForEvent(String eventId) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'settlements',
      where: 'event_id = ?',
      whereArgs: [eventId],
      orderBy: 'settled_at DESC',
    );
    return results.map((m) => SettlementModel.fromMap(m)).toList();
  }

  Future<SettlementModel> recordSettlement({
    required String eventId,
    required String payerId,
    required String payeeId,
    required double amount,
    required DateTime settledAt,
    String note = '',
  }) async {
    final db = await _databaseHelper.database;
    final settlement = SettlementModel(
      id: _uuid.v4(),
      eventId: eventId,
      payerId: payerId,
      payeeId: payeeId,
      amount: amount,
      settledAt: settledAt,
      note: note,
    );

    await db.insert('settlements', settlement.toMap());
    return settlement;
  }

  Future<void> deleteSettlement(String id) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'settlements',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
