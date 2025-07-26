import 'package:rfid_project/main.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('rfid_channel');

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
