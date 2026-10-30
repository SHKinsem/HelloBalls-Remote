import 'package:flutter/material.dart';

/// Button. [selected] highlights it (e.g. the current mode). With [confirm]
/// it only fires on a long press, for actions that should not happen by accident.
class RemoteButton extends StatelessWidget {
  const RemoteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.confirm = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool confirm;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = danger
        ? scheme.error
        : selected
            ? scheme.primary
            : scheme.surfaceContainerHighest;
    final fg = danger
        ? scheme.onError
        : selected
            ? scheme.onPrimary
            : scheme.onSurface;
    return Material(
      color: onPressed == null ? bg.withValues(alpha: 0.4) : bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: confirm ? null : onPressed,
        onLongPress: confirm ? onPressed : null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: danger ? 20 : 15)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slider with a label and value readout. [returnToZero] snaps back to [min]
/// when released (spring throttle).
class RemoteSlider extends StatelessWidget {
  const RemoteSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.vertical = false,
    this.returnToZero = false,
  });

  final String label;
  final double value, min, max, step;
  final ValueChanged<double> onChanged;
  final bool vertical;
  final bool returnToZero;

  @override
  Widget build(BuildContext context) {
    final divisions = step > 0 ? ((max - min) / step).round() : null;
    final slider = Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeEnd: returnToZero ? (_) => onChanged(min) : null,
    );
    final text = Text('$label  ${value.round()}', style: Theme.of(context).textTheme.labelMedium);
    if (!vertical) {
      return Column(mainAxisSize: MainAxisSize.min, children: [text, slider]);
    }
    return Column(children: [
      text,
      Expanded(child: RotatedBox(quarterTurns: 3, child: slider)),
    ]);
  }
}

/// On/off switch with a label.
class RemoteToggle extends StatelessWidget {
  const RemoteToggle({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: value ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Row(children: [
          const SizedBox(width: 8),
          Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label))),
          Switch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// Read-only tile showing a status value.
class StatusTile extends StatelessWidget {
  const StatusTile({super.key, required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      // Scale down rather than overflow on small screens
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: warn ? scheme.onErrorContainer : scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}
