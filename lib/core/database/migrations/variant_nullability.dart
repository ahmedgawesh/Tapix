import '../app_database.dart';

/// Repairs the historical NOT NULL SKU/barcode schema before warehouse setup.
/// Uses SQLite's create-copy-drop-rename procedure; never renames the old table.
/// Unexpected schema, corruption, or a failed copy aborts without losing rows.
Future<void> repairVariantNullability(AppDatabase db) async {
  if ((await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name IN "
            "('product_variants__old', 'product_variants__repair')",
          )
          .get())
      .isNotEmpty) {
    throw StateError(
      'An unfinished variant repair requires explicit recovery.',
    );
  }
  final columns = await db
      .customSelect('PRAGMA table_xinfo(product_variants)')
      .get();
  final targets = columns
      .where(
        (r) =>
            const {'sku', 'barcode'}.contains(r.read<String>('name')) &&
            r.read<int>('notnull') == 1,
      )
      .toList();
  if (targets.isEmpty) return;
  if ((await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE name = 'business_warehouse_stocks' AND type = 'table'",
          )
          .get())
      .isNotEmpty) {
    throw StateError(
      'Legacy variant schema requires repair before warehouse migration.',
    );
  }
  final ddl =
      (await db
              .customSelect(
                "SELECT sql FROM sqlite_master WHERE name = 'product_variants' AND type = 'table'",
              )
              .getSingle())
          .read<String>('sql');
  final prefix = RegExp(
    r'^CREATE\s+TABLE\s+(?:"product_variants"|`product_variants`|\[product_variants\]|product_variants)\s*\(',
    caseSensitive: false,
  );
  if (!prefix.hasMatch(ddl)) {
    throw StateError('Unsupported variant table definition.');
  }
  var revised = ddl.replaceFirst(
    prefix,
    'CREATE TABLE product_variants__repair (',
  );
  for (final target in targets) {
    final name = target.read<String>('name');
    // Accept the historical column declaration, not arbitrary SQL expressions.
    // Preserve every other column and constraint, including later additions.
    final declaration = RegExp(
      '(?:\\(|,)\\s*(?:"$name"|`$name`|\\[$name\\]|$name)\\s+TEXT\\s+(?:UNIQUE\\s+)?NOT\\s+NULL\\b',
      caseSensitive: false,
    );
    if (declaration.allMatches(revised).length != 1) {
      throw StateError('Unsupported $name nullability constraint.');
    }
    revised = revised.replaceFirstMapped(
      declaration,
      (match) => match
          .group(0)!
          .replaceFirst(RegExp(r'NOT\s+NULL', caseSensitive: false), ''),
    );
  }
  final dependencies = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE tbl_name = 'product_variants' "
        "AND type IN ('index', 'trigger') AND sql IS NOT NULL ORDER BY type, name",
      )
      .get();
  final foreignKeys = (await db.customSelect('PRAGMA foreign_keys').getSingle())
      .read<int>('foreign_keys');
  final legacyAlter =
      (await db.customSelect('PRAGMA legacy_alter_table').getSingle())
          .read<int>('legacy_alter_table');
  try {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    if ((await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ) !=
        0) {
      throw StateError(
        'Variant schema repair requires a connection outside a transaction.',
      );
    }
    // Keep views and external triggers referring to the final table name while
    // the original is briefly absent inside the transaction.
    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.transaction(() async {
      if ((await db.customSelect('PRAGMA foreign_key_check').get())
          .isNotEmpty) {
        throw StateError(
          'Foreign key violations must be reviewed before variant repair.',
        );
      }
      int? sequence;
      if ((await db
              .customSelect(
                "SELECT 1 FROM sqlite_master WHERE name = 'sqlite_sequence'",
              )
              .get())
          .isNotEmpty) {
        sequence =
            (await db
                    .customSelect(
                      "SELECT seq FROM sqlite_sequence WHERE name = 'product_variants'",
                    )
                    .getSingleOrNull())
                ?.read<int>('seq');
      }
      await db.customStatement(revised);
      String quote(String name) => '"${name.replaceAll('"', '""')}"';
      final names = columns
          .where((r) => r.read<int>('hidden') == 0)
          .map((r) => quote(r.read<String>('name')))
          .join(', ');
      // Preserve stored values exactly; empty identifiers are not silently
      // rewritten, and no financial defaults are invented during schema repair.
      await db.customStatement(
        'INSERT INTO product_variants__repair ($names) SELECT $names FROM product_variants',
      );
      await db.customStatement('DROP TABLE product_variants');
      await db.customStatement(
        'ALTER TABLE product_variants__repair RENAME TO product_variants',
      );
      for (final dependency in dependencies) {
        await db.customStatement(dependency.read<String>('sql'));
      }
      if (sequence != null) {
        await db.customStatement(
          "UPDATE sqlite_sequence SET seq = MAX(seq, ?) WHERE name = 'product_variants'",
          [sequence],
        );
      }
      if ((await db.customSelect('PRAGMA foreign_key_check').get())
          .isNotEmpty) {
        throw StateError('Variant repair would break foreign keys.');
      }
      final repaired = await db
          .customSelect('PRAGMA table_info(product_variants)')
          .get();
      if (repaired.any(
        (r) =>
            const {'sku', 'barcode'}.contains(r.read<String>('name')) &&
            r.read<int>('notnull') != 0,
      )) {
        throw StateError('Variant nullability repair did not complete.');
      }
    });
  } finally {
    try {
      await db.customStatement('PRAGMA legacy_alter_table = $legacyAlter');
    } finally {
      await db.customStatement('PRAGMA foreign_keys = $foreignKeys');
    }
  }
}
