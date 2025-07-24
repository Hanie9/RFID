import 'package:flutter/material.dart';
import 'package:rfid_project/main.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class GPIOConfigPage extends StatefulWidget {
  final AppConfig appConfig;
  const GPIOConfigPage({super.key, required this.appConfig});

  @override
  State<GPIOConfigPage> createState() => _GPIOConfigPageState();
}

class _GPIOConfigPageState extends State<GPIOConfigPage> {
  List<int> get allInputs =>
      List.generate(widget.appConfig.antennaCount, (i) => i + 1);
  List<int> get allOutputs =>
      List.generate(widget.appConfig.antennaCount, (i) => i + 1);
  final List<String> logicTypes = ['AND', 'OR', 'NAND', 'NOR'];

  late TextEditingController _jsonUrlController;
  late TextEditingController _outputDurationController;

  @override
  void initState() {
    super.initState();
    _jsonUrlController = TextEditingController(text: widget.appConfig.jsonUrl);
    _outputDurationController = TextEditingController(
      text: widget.appConfig.outputDuration.toString(),
    );
  }

  @override
  void dispose() {
    _jsonUrlController.dispose();
    _outputDurationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Global Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _jsonUrlController,
          decoration: const InputDecoration(
            labelText: 'JSON URL (for allowed IDs)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          onChanged: (v) => widget.appConfig.setJsonUrl(v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _outputDurationController,
          decoration: const InputDecoration(
            labelText: 'Output Duration (seconds)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.timer),
          ),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final seconds = int.tryParse(v) ?? 2;
            widget.appConfig.setOutputDuration(seconds);
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Configure Inputs for Each Group',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        ...List.generate(widget.appConfig.antennaCount, (i) => i + 1).map((
          group,
        ) {
          final selectedInputs = widget.appConfig.groupInputs[group] ?? [];
          final selectedOutputs = widget.appConfig.groupOutputs[group] ?? [];
          final selectedLogic =
              widget.appConfig.groupInputLogic[group] ?? 'AND';
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Group $group',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('Select Inputs:'),
                  Wrap(
                    spacing: 8,
                    children: allInputs.map((input) {
                      final isSelected = selectedInputs.contains(input);
                      return FilterChip(
                        label: Text('Input $input'),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            final newInputs = List<int>.from(selectedInputs);
                            if (selected && !newInputs.contains(input)) {
                              newInputs.add(input);
                            } else if (!selected && newInputs.contains(input)) {
                              newInputs.remove(input);
                            }
                            widget.appConfig.setGroupInputs(group, newInputs);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text('Select Outputs:'),
                  Wrap(
                    spacing: 8,
                    children: allOutputs.map((output) {
                      final isSelected = selectedOutputs.contains(output);
                      return FilterChip(
                        label: Text('Output $output'),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            final newOutputs = List<int>.from(selectedOutputs);
                            if (selected && !newOutputs.contains(output)) {
                              newOutputs.add(output);
                            } else if (!selected &&
                                newOutputs.contains(output)) {
                              newOutputs.remove(output);
                            }
                            widget.appConfig.setGroupOutputs(group, newOutputs);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: selectedLogic,
                    items: logicTypes
                        .map(
                          (logic) => DropdownMenuItem(
                            value: logic,
                            child: Text('Logic: $logic'),
                          ),
                        )
                        .toList(),
                    onChanged: (logic) {
                      if (logic != null) {
                        setState(() {
                          widget.appConfig.setGroupInputLogic(group, logic);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

bool evaluateLogic(List<bool> inputStates, String logic) {
  switch (logic) {
    case 'AND':
      return inputStates.every((v) => v);
    case 'OR':
      return inputStates.any((v) => v);
    case 'NAND':
      return !inputStates.every((v) => v);
    case 'NOR':
      return !inputStates.any((v) => v);
    default:
      return false;
  }
}

class GPIOMonitorPage extends StatefulWidget {
  final AppConfig appConfig;
  const GPIOMonitorPage({super.key, required this.appConfig});

  @override
  State<GPIOMonitorPage> createState() => _GPIOMonitorPageState();
}

class _GPIOMonitorPageState extends State<GPIOMonitorPage> {
  late Map<int, bool> inputStates;
  Map<int, bool> groupActive = {};

  static const platform = MethodChannel('rfid_channel');
  bool isMonitoring = false;
  Timer? monitorTimer;

  @override
  void initState() {
    super.initState();
    inputStates = {
      for (var i = 1; i <= widget.appConfig.antennaCount; i++) i: false,
    };
  }

  Future<void> _readInputs() async {
    try {
      final Map<dynamic, dynamic>? gpioStates = await platform
          .invokeMethod<Map<dynamic, dynamic>>('readGpioValues');
      if (gpioStates != null) {
        setState(() {
          for (var i = 1; i <= widget.appConfig.antennaCount; i++) {
            inputStates[i] = gpioStates['gpio$i'] == true;
          }
        });
      }
    } catch (_) {}
  }

  void _startMonitoring() {
    setState(() => isMonitoring = true);
    monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _readInputs();
      for (var group = 1; group <= widget.appConfig.antennaCount; group++) {
        final inputs = widget.appConfig.groupInputs[group] ?? [];
        final logic = widget.appConfig.groupInputLogic[group] ?? 'AND';
        final states = inputs.map((i) => inputStates[i] ?? false).toList();
        final active = evaluateLogic(states, logic);
        setState(() {
          groupActive[group] = active;
        });
        // Optionally, control antenna power:
        await platform.invokeMethod('setRfPower', {
          'antenna': group,
          'enabled': active,
        });
      }
    });
  }

  void _stopMonitoring() {
    monitorTimer?.cancel();
    setState(() => isMonitoring = false);
  }

  @override
  void dispose() {
    monitorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: isMonitoring ? null : _startMonitoring,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Monitoring'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: isMonitoring ? _stopMonitoring : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Monitoring'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Input States:', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: 12,
          children: List.generate(widget.appConfig.antennaCount, (i) {
            final idx = i + 1;
            return Chip(
              label: Text(
                'Input $idx: ${inputStates[idx]! ? 'Active' : 'Inactive'}',
              ),
              backgroundColor: inputStates[idx]!
                  ? Colors.green[200]
                  : Colors.grey[300],
            );
          }),
        ),
        const SizedBox(height: 16),
        Text(
          'Group Antenna States:',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ...List.generate(widget.appConfig.antennaCount, (i) => i + 1).map((
          group,
        ) {
          final active = groupActive[group] ?? false;
          return ListTile(
            title: Text('Group $group'),
            subtitle: Text('Antenna is ${active ? 'ACTIVE' : 'INACTIVE'}'),
            leading: Icon(
              active ? Icons.check_circle : Icons.cancel,
              color: active ? Colors.green : Colors.red,
            ),
          );
        }),
      ],
    );
  }
}
