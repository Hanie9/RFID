import 'package:rfid_project/main.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('rfid_channel');

// Remove GPIOOutputConfigPage and GPIOOutputMonitorPage classes
// Keep only utility functions if used elsewhere

Future<void> setGroupOutputsActive(
  AppConfig appConfig,
  int group,
  bool active,
) async {
  final outputs = appConfig.groupOutputs[group] ?? [];
  for (final output in outputs) {
    await platform.invokeMethod(
      active ? 'output${output}On' : 'output${output}Off',
    );
  }
}

final prohibitedTags = {'TAG123', 'TAG456'};

Future<void> onTagRead(String tagId) async {
  if (prohibitedTags.contains(tagId)) {
    // For example, use output 1 for the alarm
    await activateAlarmOutput(1, durationSeconds: 2);
  }
}

Future<void> activateAlarmOutput(
  int outputNumber, {
  int? durationSeconds,
}) async {
  // Turn ON the output (alarm)
  await platform.invokeMethod('output${outputNumber}On');
  // Turn OFF after a delay
  Future.delayed(
    Duration(seconds: durationSeconds ?? appConfig.outputDuration),
    () async {
      await platform.invokeMethod('output${outputNumber}Off');
    },
  );
}
