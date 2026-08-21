// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:firebase_functions/firebase_functions.dart';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) async {
  await runFunctions((firebase) {
    // Uses sqlite3 (a native/FFI package with a build hook) to prove the
    // compiled-and-deployed function can load and run its native library.
    firebase.https.onRequest(name: 'sqliteDemo', (request) async {
      final db = sqlite3.openInMemory();
      try {
        db.execute('CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)');
        db.execute("INSERT INTO items (name) VALUES ('a'), ('b'), ('c')");
        final rows = db.select('SELECT COUNT(*) AS count FROM items');
        final count = rows.first['count'];
        return Response.ok(
          'sqlite3 ${sqlite3.version.libVersion}, items: $count',
        );
      } finally {
        db.close();
      }
    });
  });
}
