import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum MicButtonState { ready, listening, processing, disabled }

/// Prominent 88dp voice capture button with concrete label and gentle listening pulse.
class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.state,
    required this.label,
    this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
    this.onHoldCancel,
    this.semanticLabel,
  });

  final MicButtonState state;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;
  final VoidCallback? onHoldCancel;
  final String? semanticLabel;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.state == MicButtonState.listening && !reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final isInteractive = widget.state != MicButtonState.disabled &&
        widget.state != MicButtonState.processing;

    final (Color bg, Color fg, Color ring, IconData icon) =
        switch (widget.state) {
      MicButtonState.ready => (
          tokens.primary,
          Colors.white,
          tokens.primaryContainer,
          Icons.mic_rounded,
        ),
      MicButtonState.listening => (
          tokens.riskHigh,
          Colors.white,
          tokens.riskHighContainer,
          Icons.stop_rounded,
        ),
      MicButtonState.processing => (
          tokens.primaryContainer,
          tokens.primary,
          tokens.primaryContainer,
          Icons.hourglass_top_rounded,
        ),
      MicButtonState.disabled => (
          tokens.outline,
          tokens.inkMuted,
          tokens.outline,
          Icons.mic_off_rounded,
        ),
    };

    final circle = AnimatedContainer(
      duration: AppMotion.standard,
      curve: AppMotion.curve,
      width: AppSizes.micButton,
      height: AppSizes.micButton,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: widget.state == MicButtonState.listening
            ? Border.all(color: ring, width: 6)
            : null,
      ),
      child: Center(
        child: widget.state == MicButtonState.processing
            ? SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              )
            : Icon(icon, size: 36, color: fg),
      ),
    );

    final animatedCircle = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = widget.state == MicButtonState.listening
            ? 1.0 + (_controller.value * 0.06)
            : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: circle,
    );

    return Semantics(
      button: true,
      enabled: isInteractive,
      label: widget.semanticLabel ?? widget.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: isInteractive ? widget.onTap : null,
            onLongPressStart:
                isInteractive && widget.onHoldStart != null
                    ? (_) => widget.onHoldStart!()
                    : null,
            onLongPressEnd:
                isInteractive && widget.onHoldEnd != null
                    ? (_) => widget.onHoldEnd!()
                    : null,
            onLongPressCancel:
                isInteractive && widget.onHoldCancel != null
                    ? widget.onHoldCancel
                    : null,
            child: animatedCircle,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: AppTypography.label(tokens.ink),
          ),
        ],
      ),
    );
  }
}
