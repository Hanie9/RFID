import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rfid_project/gpio_output.dart';
import 'package:rfid_project/main.dart';

Future<bool> getLimitSwitchState(int group, String type) async {
  // type: 'input' or 'output'
  // Read group config to get the correct limit switch index
  final prefs = await SharedPreferences.getInstance();
  final groupsJson = prefs.getString('config_groups');
  if (groupsJson == null) return false;
  final List<dynamic> decoded = jsonDecode(groupsJson);
  final groupConfig = decoded.cast<Map<String, dynamic>>().firstWhere(
    (g) => g['inputAntenna'] == group || g['outputAntenna'] == group,
    orElse: () => {},
  );
  int? switchIndex;
  if (type == 'input') {
    switchIndex = groupConfig['inputLimitSwitch'];
  } else if (type == 'output') {
    switchIndex = groupConfig['outputLimitSwitch'];
  }
  if (switchIndex == null) return false;
  try {
    const platform = MethodChannel('rfid_channel');
    final Map<dynamic, dynamic>? gpioStates = await platform
        .invokeMethod<Map<dynamic, dynamic>>('readGpioValues');
    if (gpioStates != null && gpioStates.containsKey('gpio$switchIndex')) {
      return gpioStates['gpio$switchIndex'] == true;
    }
  } catch (_) {}
  return false;
}

Future<void> onTagRead(String tagId, int antenna) async {
  final config = appConfig.antennaConfigs[antenna];
  if (config == null) return;
  final group = config['group'] as int?;
  if (group == null) return;
  final allowedIds = appConfig.groupAllowedIds[group] ?? {};
  final isValid = allowedIds.contains(tagId);
  final apiAddress = config['url'] as String?;
  // Get group config for output duration and alarmOutput
  final prefs = await SharedPreferences.getInstance();
  final groupsJson = prefs.getString('config_groups');
  int groupOutputDuration = 120;
  Map<String, dynamic> groupConfig = {};
  if (groupsJson != null) {
    final List<dynamic> decoded = jsonDecode(groupsJson);
    groupConfig = decoded.cast<Map<String, dynamic>>().firstWhere(
      (g) => g['inputAntenna'] == antenna || g['outputAntenna'] == antenna,
      orElse: () => {},
    );
    groupOutputDuration = groupConfig['groupOutputDuration'] ?? 120;
  }
  // Read limit switch states
  final outputLimitActive = await getLimitSwitchState(group, 'output');
  final inputLimitActive = await getLimitSwitchState(group, 'input');
  // Scenario 1
  if (outputLimitActive) {
    await setGroupOutputsActive(appConfig, group, false);
    if (groupConfig['alarmOutput'] != null) {
      await activateAlarmOutput(groupConfig['alarmOutput']);
    }
    if (apiAddress != null && apiAddress.isNotEmpty) {
      final payload = {
        'tag': tagId,
        'antenna': antenna,
        'signalType': 'not valid',
      };
      try {
        await http.post(
          Uri.parse(apiAddress),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (e) {
        //
      }
    }
    return;
  }
  // Scenario 2
  if (!outputLimitActive && inputLimitActive) {
    await setGroupOutputsActive(appConfig, group, true);
    if (apiAddress != null && apiAddress.isNotEmpty) {
      final payload = {'tag': tagId, 'antenna': antenna, 'signalType': 'valid'};
      try {
        await http.post(
          Uri.parse(apiAddress),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (e) {
        //
      }
    }
    return;
  }
  // Scenario 3
  if (!outputLimitActive && !inputLimitActive) {
    await setGroupOutputsActive(appConfig, group, false);
    if (groupConfig['alarmOutput'] != null) {
      await activateAlarmOutput(groupConfig['alarmOutput']);
    }
    if (apiAddress != null && apiAddress.isNotEmpty) {
      final payload = {
        'tag': tagId,
        'antenna': antenna,
        'signalType': 'not valid',
      };
      try {
        await http.post(
          Uri.parse(apiAddress),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (e) {
        //
      }
    }
    return;
  }
  // Scenario 4: Input antenna reads a valid tag (from JSON), activate group output for groupOutputDuration seconds, no request
  if (isValid && config['inputAntenna'] == antenna) {
    await setGroupOutputsActive(appConfig, group, true);
    if (groupConfig['alarmOutput'] != null) {
      await activateAlarmOutput(groupConfig['alarmOutput']);
    }
    Future.delayed(Duration(seconds: groupOutputDuration), () async {
      await setGroupOutputsActive(appConfig, group, false);
    });
    return;
  }
}
