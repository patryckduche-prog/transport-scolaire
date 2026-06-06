import 'package:flutter/material.dart';

class RootBackGuard extends StatelessWidget {
  const RootBackGuard({
    required this.child,
    this.message = 'Vous etes deja sur la page principale.',
    this.onBack,
    super.key,
  });

  final Widget child;
  final String message;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (onBack != null) {
          onBack!();
          return;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
      child: child,
    );
  }
}
