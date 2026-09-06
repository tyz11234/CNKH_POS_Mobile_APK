import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/ocr_purchase_schema.dart';
import '../models/product.dart';
import '../models/purchase_ocr.dart';
import 'pos_repository.dart';
import 'product_match_service.dart';
import 'purchase_validation_service.dart';
import 'sync_store.dart';

class PurchaseOcrRepository {
  PurchaseOcrRepository(this.posRepo)
      : _database = posRepo.database,
        _matcher = const ProductMatchService(),
        _validator = const PurchaseValidationService();

  final PosRepository posRepo;
  final AppDatabase _database;
  final ProductMatchService _matcher;
  final PurchaseValidationService _validator;

  Future<Database> _db() async {
    final db = await _database.db;
    await ensureOcrPurchaseSchema(db);
    return db;
  }

  Future<PurchaseDraft> prepareDraft(PurchaseDraft draft) async {
    final suppliers = await posRepo.listSuppliers();
    var supplierId = draft.supplierId;
    var supplierName = draft.supplierName;
    if ((supplierId ?? '').isEmpty && supplierName.trim().isNotEmpty) {
      Supplier? best;
      var bestScore = 0.0;
      final normalized = _matcher.normalizeName(supplierName);
      for (final supplier in suppliers) {
        final score = _matcher.similarity(
          normalized,
          _matcher.normalizeName(supplier.name),
        );
        if (score > bestScore) {
          bestScore = score;
          best = supplier;
        }
      }
      if (best != null && bestScore >= 0.78) {
        supplierId = best.id;
        supplierName = best.name;
      }
    }

    final products = await posRepo.searchProducts('', limit: 5000);
    final preparedLines = <PurchaseDraftLine>[];
    for (final original in draft.lines) {
      var line = original;
      Product? product;
      var confidence = line.matchConfidence;
      var source = '';

      if ((line.matchedProductId ?? '').isNotEmpty) {
        product = await posRepo.getProduct(line.matchedProductId!);
        confidence = product == null ? 0 : (confidence <= 0 ? 1 : confidence);
      }

      if (product == null && (supplierId ?? '').isNotEmpty) {
        final alias = await lookupAlias(supplierId!, line.rawProductName);
        if (alias != null) {
          product = await posRepo.getProduct(alias['product_id'] as String);
          if (product != null) {
            confidence = 1;
            source = 'supplier_memory';
          }
        }
      }

      if (product == null) {
        final candidates = _matcher.rank(line.rawProductName, products);
        if (candidates.isNotEmpty && candidates.first.confidence >= 0.82) {
          product = candidates.first.product;
          confidence = candidates.first.confidence;
          source = candidates.first.source;
        }
      }

      if (product != null) {
        line = line.copyWith(
          matchedProductId: product.id,
          matchedProductName: product.nameZh,
          matchConfidence: confidence,
        );
      } else {
        line = line.copyWith(
          clearMatchedProduct: true,
          matchedProductName: '',
          matchConfidence: 0,
        );
      }

      final history = line.isMatched
          ? await historyForProduct(line.matchedProductId!)
          : const PurchaseHistorySample();
      final warnings = _validator.validateLine(line, history: history);
      if (source == 'supplier_memory') {
        warnings.insert(
          0,
          const PurchaseWarning(
            code: 'supplier_memory_match',
            message: '已按该供应商历史商品名称自动匹配。',
            level: PurchaseWarningLevel.info,
          ),
        );
      }
      preparedLines.add(line.copyWith(warnings: warnings));
    }

    final next = draft.copyWith(
      supplierId: supplierId,
      supplierName: supplierName,
      lines: preparedLines,
    );
    final draftWarnings = <PurchaseWarning>[
      ...draft.warnings.where((w) =>
          w.code == 'no_product_lines' ||
          w.code == 'invoice_total_missing' ||
          w.code == 'supplier_missing'),
      ..._validator.validateDraft(next),
    ];
    return next.copyWith(warnings: _dedupeWarnings(draftWarnings));
  }

  Future<PurchaseDraft> validateDraft(PurchaseDraft draft) async {
    final lines = <PurchaseDraftLine>[];
    for (final line in draft.lines) {
      final history = line.isMatched
          ? await historyForProduct(line.matchedProductId!)
          : const PurchaseHistorySample();
      lines.add(line.copyWith(
        warnings: _validator.validateLine(line, history: history),
      ));
    }
    final next = draft.copyWith(lines: lines);
    return next.copyWith(
      warnings: _dedupeWarnings([
        ...draft.warnings.where((w) =>
            w.code == 'invoice_total_missing' ||
            w.code == 'no_product_lines'),
        ..._validator.validateDraft(next),
      ]),
    );
  }

  List<PurchaseWarning> _dedupeWarnings(List<PurchaseWarning> input) {
    final seen = <String>{};
    return [for (final w in input) if (seen.add('${w.code}:${w.message}')) w];
  }

  Future<List<ProductMatchCandidate>> candidatesFor(String rawName) async {
    final products = await posRepo.searchProducts('', limit: 5000);
    return _matcher.rank(rawName, products, limit: 8);
  }

  Future<Map<String, Object?>?> lookupAlias(
    String supplierId,
    String rawName,
  ) async {
    final db = await _db();
    final normalized = _matcher.normalizeName(rawName);
    final rows = await db.query(
      'supplier_product_aliases',
      where: 'supplier_id=? AND normalized_name=?',
      whereArgs: [supplierId, normalized],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<PurchaseHistorySample> historyForProduct(String productId) async {
    final db = await _db();
    final rows = await db.rawQuery(
      "SELECT lines_json FROM purchases WHERE COALESCE(reversed,0)=0 ORDER BY purchased_at DESC LIMIT 80",
    );
    final quantities = <double>[];
    int? lastCost;
    for (final row in rows) {
      try {
        final lines = jsonDecode(row['lines_json'] as String) as List;
        for (final raw in lines) {
          final line = Map<String, dynamic>.from(raw as Map);
          if (line['productId']?.toString() != productId) continue;
          final qty = (line['invoiceQty'] as num?)?.toDouble() ??
              (line['qty'] as num?)?.toDouble();
          final cost = (line['invoiceUnitCostCents'] as num?)?.toInt() ??
              (line['unitCostCents'] as num?)?.toInt();
          if (qty != null && qty > 0) quantities.add(qty);
          lastCost ??= cost;
        }
      } catch (_) {}
      if (quantities.length >= 12 && lastCost != null) break;
    }
    quantities.sort();
    double? median;
    if (quantities.isNotEmpty) {
      final mid = quantities.length ~/ 2;
      median = quantities.length.isOdd
          ? quantities[mid]
          : (quantities[mid - 1] + quantities[mid]) / 2;
    }
    return PurchaseHistorySample(
      typicalQuantity: median,
      lastUnitCostCents: lastCost,
    );
  }

  Future<void> saveDraft(PurchaseDraft draft) async {
    final db = await _db();
    await db.transaction((txn) async {
      await txn.insert(
        'purchase_drafts',
        {
          'id': draft.draftId,
          'supplier_id': draft.supplierId,
          'supplier_name': draft.supplierName,
          'invoice_no': draft.invoiceNo,
          'invoice_date': draft.invoiceDate,
          'image_path': draft.imagePath,
          'ocr_raw_text': draft.ocrRawText,
          'discount_cents': draft.discountCents,
          'tax_cents': draft.taxCents,
          'delivery_fee_cents': draft.deliveryFeeCents,
          'other_fee_cents': draft.otherFeeCents,
          'invoice_total_cents': draft.invoiceTotalCents,
          'warnings_json': jsonEncode(draft.warnings.map((w) => w.toMap()).toList()),
          'created_at': draft.createdAt,
          'created_by': draft.createdBy,
          'status': draft.status,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'purchase_draft_lines',
        where: 'draft_id=?',
        whereArgs: [draft.draftId],
      );
      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        await txn.insert('purchase_draft_lines', {
          'id': line.id,
          'draft_id': draft.draftId,
          'sort_order': i,
          'raw_text': line.rawText,
          'raw_product_name': line.rawProductName,
          'matched_product_id': line.matchedProductId,
          'matched_product_name': line.matchedProductName,
          'match_confidence': line.matchConfidence,
          'quantity': line.quantity,
          'unit': line.unit,
          'unit_cost_cents': line.unitCostCents,
          'line_subtotal_cents': line.lineSubtotalCents,
          'original_quantity': line.originalQuantity,
          'original_unit_cost_cents': line.originalUnitCostCents,
          'original_line_subtotal_cents': line.originalLineSubtotalCents,
          'conversion_factor': line.conversionFactor,
          'warnings_json': jsonEncode(line.warnings.map((w) => w.toMap()).toList()),
          'user_modified': line.userModified ? 1 : 0,
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> listDrafts() async {
    final db = await _db();
    return db.query(
      'purchase_drafts',
      where: "status='draft'",
      orderBy: 'created_at DESC',
    );
  }

  Future<PurchaseDraft?> loadDraft(String draftId) async {
    final db = await _db();
    final headers = await db.query(
      'purchase_drafts',
      where: 'id=?',
      whereArgs: [draftId],
      limit: 1,
    );
    if (headers.isEmpty) return null;
    final row = headers.first;
    final lineRows = await db.query(
      'purchase_draft_lines',
      where: 'draft_id=?',
      whereArgs: [draftId],
      orderBy: 'sort_order ASC',
    );
    List<PurchaseWarning> decodeWarnings(Object? raw) {
      try {
        return (jsonDecode(raw?.toString() ?? '[]') as List)
            .map((e) => PurchaseWarning.fromMap(
                Map<String, Object?>.from(e as Map)))
            .toList();
      } catch (_) {
        return const [];
      }
    }

    final lines = <PurchaseDraftLine>[];
    for (final l in lineRows) {
      lines.add(PurchaseDraftLine(
        id: l['id'] as String,
        rawText: l['raw_text'] as String? ?? '',
        rawProductName: l['raw_product_name'] as String? ?? '',
        matchedProductId: l['matched_product_id'] as String?,
        matchedProductName: l['matched_product_name'] as String? ?? '',
        matchConfidence: (l['match_confidence'] as num?)?.toDouble() ?? 0,
        quantity: (l['quantity'] as num?)?.toDouble() ?? 0,
        unit: l['unit'] as String? ?? 'pcs',
        unitCostCents: (l['unit_cost_cents'] as num?)?.toInt() ?? 0,
        lineSubtotalCents:
            (l['line_subtotal_cents'] as num?)?.toInt() ?? 0,
        originalQuantity: (l['original_quantity'] as num?)?.toDouble(),
        originalUnitCostCents:
            (l['original_unit_cost_cents'] as num?)?.toInt(),
        originalLineSubtotalCents:
            (l['original_line_subtotal_cents'] as num?)?.toInt(),
        conversionFactor:
            (l['conversion_factor'] as num?)?.toDouble() ?? 1,
        warnings: decodeWarnings(l['warnings_json']),
        userModified: l['user_modified'] == 1,
      ));
    }
    return PurchaseDraft(
      draftId: draftId,
      supplierId: row['supplier_id'] as String?,
      supplierName: row['supplier_name'] as String? ?? '',
      invoiceNo: row['invoice_no'] as String? ?? '',
      invoiceDate: row['invoice_date'] as String? ?? '',
      imagePath: row['image_path'] as String? ?? '',
      ocrRawText: row['ocr_raw_text'] as String? ?? '',
      lines: lines,
      discountCents: (row['discount_cents'] as num?)?.toInt() ?? 0,
      taxCents: (row['tax_cents'] as num?)?.toInt() ?? 0,
      deliveryFeeCents:
          (row['delivery_fee_cents'] as num?)?.toInt() ?? 0,
      otherFeeCents: (row['other_fee_cents'] as num?)?.toInt() ?? 0,
      invoiceTotalCents: (row['invoice_total_cents'] as num?)?.toInt(),
      warnings: decodeWarnings(row['warnings_json']),
      createdAt: row['created_at'] as String,
      createdBy: row['created_by'] as String,
      status: row['status'] as String? ?? 'draft',
    );
  }

  Future<String> commitDraft(PurchaseDraft original, {required String operator}) async {
    final draft = await validateDraft(original);
    if (draft.hasBlockingIssues) {
      throw StateError('仍有未匹配商品或无效数据，不能直接入库');
    }
    final db = await _db();
    await saveDraft(draft);
    final purchaseId = AppDatabase.newId();
    final purchaseNo = await _database.nextPurchaseNo();
    final now = DateTime.now().toIso8601String();
    final totalCents = draft.invoiceTotalCents ?? draft.calculatedTotalCents;

    await db.transaction((txn) async {
      final localLines = <Map<String, Object?>>[];
      final remoteLines = <Map<String, Object?>>[];
      for (final line in draft.lines) {
        final productId = line.matchedProductId!;
        final rows = await txn.query(
          'products',
          where: 'id=? AND is_deleted=0',
          whereArgs: [productId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('进货商品已不存在：${line.matchedProductName}');
        final beforeCost = (rows.first['cost_cents'] as num?)?.toInt() ?? 0;
        final stockQty = line.stockQuantity;
        final baseCost = line.baseUnitCostCents;
        final local = <String, Object?>{
          'productId': productId,
          'name': line.matchedProductName,
          'rawProductName': line.rawProductName,
          'qty': stockQty,
          'invoiceQty': line.quantity,
          'unit': line.unit,
          'conversionFactor': line.conversionFactor,
          'unitCostCents': baseCost,
          'invoiceUnitCostCents': line.unitCostCents,
          'subtotalCents': line.lineSubtotalCents,
          'beforeCostCents': beforeCost,
          'ocrOriginalQty': line.originalQuantity,
          'ocrOriginalUnitCostCents': line.originalUnitCostCents,
          'ocrOriginalSubtotalCents': line.originalLineSubtotalCents,
          'userModified': line.userModified,
        };
        localLines.add(local);
        remoteLines.add({
          ...local,
          'productId': await remoteEntityId(txn, 'product', productId),
        });
      }

      await queueMutation(txn, 'purchase', purchaseId, {
        'id': purchaseId,
        'purchase_no': purchaseNo,
        'purchased_at': now,
        'supplier_id': await remoteEntityId(txn, 'supplier', draft.supplierId!),
        'supplier_name': draft.supplierName,
        'invoice_no': draft.invoiceNo,
        'invoice_date': draft.invoiceDate,
        'lines': remoteLines,
        'total_cents': totalCents,
        'discount_cents': draft.discountCents,
        'tax_cents': draft.taxCents,
        'delivery_fee_cents': draft.deliveryFeeCents,
        'other_fee_cents': draft.otherFeeCents,
        'source': 'ocr',
        'draft_id': draft.draftId,
        'ocr_raw_text': draft.ocrRawText,
        'operator': operator,
        'notes': 'OCR purchase',
      });

      await txn.insert('purchases', {
        'id': purchaseId,
        'purchase_no': purchaseNo,
        'supplier_id': draft.supplierId,
        'supplier_name': draft.supplierName,
        'purchased_at': now,
        'total_cents': totalCents,
        'lines_json': jsonEncode(localLines),
        'notes': 'OCR purchase',
        'invoice_no': draft.invoiceNo,
        'invoice_date': draft.invoiceDate,
        'discount_cents': draft.discountCents,
        'tax_cents': draft.taxCents,
        'delivery_fee_cents': draft.deliveryFeeCents,
        'other_fee_cents': draft.otherFeeCents,
        'source': 'ocr',
        'draft_id': draft.draftId,
        'image_path': draft.imagePath,
        'ocr_raw_text': draft.ocrRawText,
        'reversed': 0,
      });

      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        final stored = localLines[i];
        final productId = line.matchedProductId!;
        final stockQty = line.stockQuantity;
        final baseCost = line.baseUnitCostCents;
        await txn.rawUpdate(
          'UPDATE products SET stock=stock+?, cost_cents=? WHERE id=?',
          [stockQty, baseCost, productId],
        );
        await txn.insert('stock_moves', {
          'id': AppDatabase.newId(),
          'product_id': productId,
          'change': stockQty,
          'reason': 'purchase',
          'created_at': now,
          'operator': operator,
          'notes': purchaseNo,
        });
        await _rememberAlias(
          txn,
          supplierId: draft.supplierId!,
          rawName: line.rawProductName,
          productId: productId,
          unit: line.unit,
          conversionFactor: line.conversionFactor,
          now: now,
        );
        if (line.userModified) {
          await txn.insert('purchase_audit_log', {
            'id': AppDatabase.newId(),
            'purchase_id': purchaseId,
            'draft_id': draft.draftId,
            'occurred_at': now,
            'username': operator,
            'action': 'ocr_line_edited',
            'field_name': 'line',
            'original_value': jsonEncode({
              'qty': line.originalQuantity,
              'unit_cost_cents': line.originalUnitCostCents,
              'subtotal_cents': line.originalLineSubtotalCents,
            }),
            'final_value': jsonEncode(stored),
            'details': line.rawText,
          });
        }
      }

      if (draft.imagePath.isNotEmpty) {
        await txn.insert('purchase_attachments', {
          'id': AppDatabase.newId(),
          'purchase_id': purchaseId,
          'local_path': draft.imagePath,
          'kind': 'invoice_image',
          'created_at': now,
        });
      }
      await txn.insert('purchase_audit_log', {
        'id': AppDatabase.newId(),
        'purchase_id': purchaseId,
        'draft_id': draft.draftId,
        'occurred_at': now,
        'username': operator,
        'action': 'ocr_purchase_committed',
        'field_name': '',
        'original_value': '',
        'final_value': '$totalCents',
        'details': 'invoice=${draft.invoiceNo}; warnings=${draft.warnings.length}',
      });
      await txn.update(
        'purchase_drafts',
        {'status': 'committed'},
        where: 'id=?',
        whereArgs: [draft.draftId],
      );
    });
    return purchaseId;
  }

  Future<void> _rememberAlias(
    DatabaseExecutor txn, {
    required String supplierId,
    required String rawName,
    required String productId,
    required String unit,
    required double conversionFactor,
    required String now,
  }) async {
    final normalized = _matcher.normalizeName(rawName);
    if (normalized.isEmpty) return;
    final existing = await txn.query(
      'supplier_product_aliases',
      where: 'supplier_id=? AND normalized_name=?',
      whereArgs: [supplierId, normalized],
      limit: 1,
    );
    if (existing.isEmpty) {
      await txn.insert('supplier_product_aliases', {
        'id': AppDatabase.newId(),
        'supplier_id': supplierId,
        'raw_name': rawName,
        'normalized_name': normalized,
        'product_id': productId,
        'unit': unit,
        'conversion_factor': conversionFactor,
        'use_count': 1,
        'last_used_at': now,
      });
    } else {
      await txn.update(
        'supplier_product_aliases',
        {
          'raw_name': rawName,
          'product_id': productId,
          'unit': unit,
          'conversion_factor': conversionFactor,
          'use_count': ((existing.first['use_count'] as num?)?.toInt() ?? 0) + 1,
          'last_used_at': now,
        },
        where: 'id=?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<Map<String, Object?>?> getPurchase(String id) async {
    final db = await _db();
    final rows = await db.query('purchases', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> purchaseAudit(String purchaseId) async {
    final db = await _db();
    return db.query(
      'purchase_audit_log',
      where: 'purchase_id=?',
      whereArgs: [purchaseId],
      orderBy: 'occurred_at ASC',
    );
  }

  Future<void> reversePurchase({
    required String purchaseId,
    required String operator,
    required String reason,
    String notes = '',
  }) async {
    if (reason.trim().isEmpty) throw ArgumentError('撤销原因不能为空');
    final db = await _db();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('进货记录不存在');
      final purchase = rows.first;
      if (purchase['reversed'] == 1) return;
      if ((await txn.query(
        'purchase_reversals',
        where: 'purchase_id=?',
        whereArgs: [purchaseId],
        limit: 1,
      )).isNotEmpty) return;

      final lines = (jsonDecode(purchase['lines_json'] as String) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final now = DateTime.now().toIso8601String();
      for (final line in lines) {
        final productId = line['productId']?.toString() ?? '';
        final qty = (line['qty'] as num?)?.toDouble() ?? 0;
        if (productId.isEmpty || !qty.isFinite || qty <= 0) {
          throw StateError('原进货商品资料无效，无法安全撤销');
        }
        final productRows = await txn.query(
          'products',
          where: 'id=? AND is_deleted=0',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) throw StateError('原进货商品已不存在，无法撤销');
        final currentCost = (productRows.first['cost_cents'] as num?)?.toInt() ?? 0;
        final purchaseCost = (line['unitCostCents'] as num?)?.toInt();
        final beforeCost = (line['beforeCostCents'] as num?)?.toInt();
        final update = <String, Object?>{
          'stock': (productRows.first['stock'] as num).toDouble() - qty,
        };
        if (purchaseCost != null &&
            beforeCost != null &&
            currentCost == purchaseCost) {
          update['cost_cents'] = beforeCost;
        }
        await txn.update('products', update, where: 'id=?', whereArgs: [productId]);
        await txn.insert('stock_moves', {
          'id': AppDatabase.newId(),
          'product_id': productId,
          'change': -qty,
          'reason': 'purchase_reversal',
          'created_at': now,
          'operator': operator,
          'notes': '${purchase['purchase_no']} · $reason',
        });
      }

      await queueMutation(txn, 'purchase_reverse', purchaseId, {
        'purchase_id': purchaseId,
        'purchase_no': purchase['purchase_no'],
        'reason': reason,
        'notes': notes,
        'operator': operator,
      });
      await txn.insert('purchase_reversals', {
        'id': AppDatabase.newId(),
        'purchase_id': purchaseId,
        'reversed_at': now,
        'reversed_by': operator,
        'reason': reason,
        'notes': notes,
      });
      await txn.update(
        'purchases',
        {
          'reversed': 1,
          'reversed_at': now,
          'reversed_by': operator,
          'reversal_reason': reason,
          'reversal_notes': notes,
        },
        where: 'id=?',
        whereArgs: [purchaseId],
      );
      await txn.insert('purchase_audit_log', {
        'id': AppDatabase.newId(),
        'purchase_id': purchaseId,
        'occurred_at': now,
        'username': operator,
        'action': 'purchase_reversed',
        'field_name': 'status',
        'original_value': 'committed',
        'final_value': 'reversed',
        'details': '$reason${notes.isEmpty ? '' : ': $notes'}',
      });
    });
  }
}
