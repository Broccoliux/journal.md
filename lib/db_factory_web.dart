import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

/// Browser builds persist to IndexedDB, which is what survives a reload.
Future<Database> openJournalDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);