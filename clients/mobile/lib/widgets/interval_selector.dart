import 'package:flutter/material.dart';

class IntervalOption {
  final String label;
  final int milliseconds;
  final String description;

  const IntervalOption({
    required this.label,
    required this.milliseconds,
    required this.description,
  });
}

class IntervalSelector extends StatelessWidget {
  final String title;
  final int currentValueMs;
  final List<IntervalOption> options;
  final Function(int) onChanged;
  final String? subtitle;

  const IntervalSelector({
    Key? key,
    required this.title,
    required this.currentValueMs,
    required this.options,
    required this.onChanged,
    this.subtitle,
  }) : super(key: key);

  // Standard interval options for most data sources
  static const List<IntervalOption> standardIntervals = [
    IntervalOption(label: '100/sec', milliseconds: 10, description: '100 times per second'),
    IntervalOption(label: '10/sec', milliseconds: 100, description: '10 times per second'),
    IntervalOption(label: '1 second', milliseconds: 1000, description: 'Once per second'),
    IntervalOption(label: '5 seconds', milliseconds: 5000, description: 'Every 5 seconds'),
    IntervalOption(label: '10 seconds', milliseconds: 10000, description: 'Every 10 seconds'),
    IntervalOption(label: '30 seconds', milliseconds: 30000, description: 'Every 30 seconds'),
    IntervalOption(label: '1 minute', milliseconds: 60000, description: 'Once per minute'),
    IntervalOption(label: '5 minutes', milliseconds: 300000, description: 'Every 5 minutes'),
    IntervalOption(label: '10 minutes', milliseconds: 600000, description: 'Every 10 minutes'),
    IntervalOption(label: '15 minutes', milliseconds: 900000, description: 'Every 15 minutes'),
    IntervalOption(label: '30 minutes', milliseconds: 1800000, description: 'Every 30 minutes'),
    IntervalOption(label: '1 hour', milliseconds: 3600000, description: 'Once per hour'),
    IntervalOption(label: '2 hours', milliseconds: 7200000, description: 'Every 2 hours'),
    IntervalOption(label: '4 hours', milliseconds: 14400000, description: 'Every 4 hours'),
    IntervalOption(label: 'Never', milliseconds: 0, description: 'Manual trigger only'),
  ];

  // High frequency intervals for sensors like accelerometer
  static const List<IntervalOption> highFrequencyIntervals = [
    IntervalOption(label: '100/sec', milliseconds: 10, description: '100 Hz sampling'),
    IntervalOption(label: '50/sec', milliseconds: 20, description: '50 Hz sampling'),
    IntervalOption(label: '20/sec', milliseconds: 50, description: '20 Hz sampling'),
    IntervalOption(label: '10/sec', milliseconds: 100, description: '10 Hz sampling'),
    IntervalOption(label: '5/sec', milliseconds: 200, description: '5 Hz sampling'),
    IntervalOption(label: '2/sec', milliseconds: 500, description: '2 Hz sampling'),
    IntervalOption(label: '1 second', milliseconds: 1000, description: 'Once per second'),
    IntervalOption(label: '2 seconds', milliseconds: 2000, description: 'Every 2 seconds'),
    IntervalOption(label: '5 seconds', milliseconds: 5000, description: 'Every 5 seconds'),
    IntervalOption(label: '10 seconds', milliseconds: 10000, description: 'Every 10 seconds'),
    IntervalOption(label: '30 seconds', milliseconds: 30000, description: 'Every 30 seconds'),
    IntervalOption(label: '1 minute', milliseconds: 60000, description: 'Once per minute'),
    IntervalOption(label: '5 minutes', milliseconds: 300000, description: 'Every 5 minutes'),
    IntervalOption(label: 'Never', milliseconds: 0, description: 'Manual trigger only'),
  ];

  // Event-driven sources with optional intervals
  static const List<IntervalOption> eventDrivenIntervals = [
    IntervalOption(label: 'Real-time', milliseconds: 0, description: 'Capture all events immediately'),
    IntervalOption(label: '1 second', milliseconds: 1000, description: 'Buffer for 1 second'),
    IntervalOption(label: '5 seconds', milliseconds: 5000, description: 'Buffer for 5 seconds'),
    IntervalOption(label: '10 seconds', milliseconds: 10000, description: 'Buffer for 10 seconds'),
    IntervalOption(label: '30 seconds', milliseconds: 30000, description: 'Buffer for 30 seconds'),
    IntervalOption(label: '1 minute', milliseconds: 60000, description: 'Buffer for 1 minute'),
    IntervalOption(label: '5 minutes', milliseconds: 300000, description: 'Buffer for 5 minutes'),
  ];

  // Low frequency intervals for battery-intensive operations
  static const List<IntervalOption> lowFrequencyIntervals = [
    IntervalOption(label: '1 minute', milliseconds: 60000, description: 'Once per minute'),
    IntervalOption(label: '5 minutes', milliseconds: 300000, description: 'Every 5 minutes'),
    IntervalOption(label: '10 minutes', milliseconds: 600000, description: 'Every 10 minutes'),
    IntervalOption(label: '15 minutes', milliseconds: 900000, description: 'Every 15 minutes'),
    IntervalOption(label: '30 minutes', milliseconds: 1800000, description: 'Every 30 minutes'),
    IntervalOption(label: '1 hour', milliseconds: 3600000, description: 'Once per hour'),
    IntervalOption(label: '2 hours', milliseconds: 7200000, description: 'Every 2 hours'),
    IntervalOption(label: '4 hours', milliseconds: 14400000, description: 'Every 4 hours'),
    IntervalOption(label: '6 hours', milliseconds: 21600000, description: 'Every 6 hours'),
    IntervalOption(label: '12 hours', milliseconds: 43200000, description: 'Twice daily'),
    IntervalOption(label: '24 hours', milliseconds: 86400000, description: 'Once daily'),
    IntervalOption(label: 'Never', milliseconds: 0, description: 'Manual trigger only'),
  ];

  // Get appropriate intervals for data source
  static List<IntervalOption> getIntervalsForSource(String sourceId) {
    switch (sourceId) {
      case 'accelerometer':
      case 'gyroscope':
        return highFrequencyIntervals;
      case 'screen_state':
      case 'app_lifecycle':
      case 'notifications':
        return eventDrivenIntervals;
      case 'screenshot':
      case 'camera':
      case 'android_app_monitoring':
        return lowFrequencyIntervals;
      default:
        return standardIntervals;
    }
  }

  IntervalOption? _findClosestOption() {
    IntervalOption? closest;
    int minDiff = double.maxFinite.toInt();
    
    for (final option in options) {
      if (option.milliseconds == 0 && currentValueMs == 0) {
        return option;
      }
      if (option.milliseconds == 0) continue; // Skip "Never" for non-zero values
      
      final diff = (option.milliseconds - currentValueMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = option;
      }
    }
    
    return closest;
  }

  @override
  Widget build(BuildContext context) {
    final currentOption = _findClosestOption();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<IntervalOption>(
              value: currentOption,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down),
              items: options.map((option) {
                return DropdownMenuItem<IntervalOption>(
                  value: option,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(option.label),
                      Expanded(
                        child: Text(
                          option.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (IntervalOption? newValue) {
                if (newValue != null) {
                  onChanged(newValue.milliseconds);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

// Power consumption indicator widget
class PowerConsumptionIndicator extends StatelessWidget {
  final int intervalMs;
  final String sourceId;

  const PowerConsumptionIndicator({
    Key? key,
    required this.intervalMs,
    required this.sourceId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final consumption = _calculatePowerConsumption();
    final color = _getConsumptionColor(consumption);
    final label = _getConsumptionLabel(consumption);
    
    return Row(
      children: [
        Icon(
          Icons.battery_charging_full,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  double _calculatePowerConsumption() {
    if (intervalMs == 0) return 0.0; // Never/Manual = no power
    
    // Base power consumption for different sources
    final basePower = {
      'accelerometer': 2.0,
      'gyroscope': 2.5,
      'gps': 5.0,
      'camera': 8.0,
      'screenshot': 3.0,
      'bluetooth': 4.0,
      'audio': 6.0,
      'android_app_monitoring': 2.0,
      'battery': 0.5,
      'network': 1.0,
      'screen_state': 0.1,
      'app_lifecycle': 0.1,
      'notifications': 0.1,
    }[sourceId] ?? 1.0;
    
    // Calculate frequency-based multiplier
    final frequencyPerHour = intervalMs > 0 ? 3600000.0 / intervalMs : 0;
    final frequencyMultiplier = frequencyPerHour > 3600 
        ? 3.0 // Very high frequency
        : frequencyPerHour > 60 
            ? 2.0 // High frequency
            : frequencyPerHour > 12 
                ? 1.5 // Medium frequency
                : 1.0; // Low frequency
    
    return basePower * frequencyMultiplier;
  }

  Color _getConsumptionColor(double consumption) {
    if (consumption == 0) return Colors.grey;
    if (consumption < 2) return Colors.green;
    if (consumption < 5) return Colors.orange;
    return Colors.red;
  }

  String _getConsumptionLabel(double consumption) {
    if (consumption == 0) return 'No drain';
    if (consumption < 2) return 'Low';
    if (consumption < 5) return 'Medium';
    if (consumption < 10) return 'High';
    return 'Very High';
  }
}