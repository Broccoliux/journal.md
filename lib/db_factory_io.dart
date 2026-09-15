import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';

/// Non-web implementations (unit tests, desktop debugging) use memory.
Future<Database> openJournalDatabase(String name) =>
    databaseFactoryMemory.openDatabase(name);
