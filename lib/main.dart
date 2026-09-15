import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui_shell.dart';

void main() {
  runApp(const Boot());
}

/// Opens local storage, then hands the loaded state to the app.
///
/// A storage failure becomes a readable screen — never a crash. The user's
/// data is still on disk either way.
class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  AppState? _state;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final AppState state = await AppState.open();
      if (!mounted) return;
      setState(() => _state = state);
    } catch (error) {
      if (!mounted) return;
      setState(() => _fatal = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState? state = _state;
    if (state != null) {
      return JournalMdApp(state: state);
    }
    if (_fatal != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _BootFailure(message: _fatal!, onRetry: _open),
      );
    }
    // The brief blank frame before the intro veil takes over.
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SizedBox.expand(),
    );
  }
}

/// Shown when local storage itself cannot be opened at all.
class _BootFailure extends StatelessWidget {
  const _BootFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'journal.md could not open its storage',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your notes are safe on disk — this is about the app not '
                  'being able to reach them. The message below may help '
                  'narrow it down.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: SelectableText(
                    message,
                    style: TextStyle(fontSize: 11.5, color: scheme.error),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

