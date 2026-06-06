import 'package:flutter/material.dart';

class RootBackGuard extends StatelessWidget {
  const RootBackGuard({
    required this.child,
    this.message = 'Vous etes deja sur la page principale.',
    super.key,
  });

  final Widget child;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      },
      child: child,
    );
  }
}
