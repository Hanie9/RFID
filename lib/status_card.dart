import 'package:flutter/material.dart';
import 'main.dart';

class StatusCard extends StatelessWidget {
  final String deviceStatus;
  final String readingStatus;
  final AppConfig appConfig;

  const StatusCard({
    super.key,
    required this.deviceStatus,
    required this.readingStatus,
    required this.appConfig,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blueGrey[50],
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device status row
            Row(
              children: [
                Icon(
                  deviceStatus.contains('Failed') ||
                          deviceStatus.contains('Error')
                      ? Icons.error_outline
                      : deviceStatus.contains('initialized')
                      ? Icons.check_circle_outline
                      : Icons.usb,
                  color:
                      deviceStatus.contains('Failed') ||
                          deviceStatus.contains('Error')
                      ? Colors.red
                      : deviceStatus.contains('initialized')
                      ? Colors.green
                      : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device: $deviceStatus',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Tooltip(
                  message: 'Shows the connection status of the RFID device.',
                  child: const Icon(Icons.info_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Reading status row
            Row(
              children: [
                Icon(
                  readingStatus == 'Reading...'
                      ? Icons.play_circle_fill
                      : Icons.pause_circle_filled,
                  color: readingStatus == 'Reading...'
                      ? Colors.blue
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Reading: $readingStatus')),
                Tooltip(
                  message: 'Shows if the app is actively reading tags.',
                  child: const Icon(Icons.info_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Antenna status chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Antennas: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...List.generate(appConfig.antennaCount, (i) => i + 1).map((
                    ant,
                  ) {
                    final isConfigured = appConfig.isAntennaConfigured(ant);
                    final config = appConfig.antennaConfigs[ant];
                    final lastStatus = config != null
                        ? config['lastStatus'] as String? ?? 'Idle'
                        : 'Not Configured';
                    final lastTag = config != null
                        ? config['lastTag'] as String? ?? ''
                        : '';
                    Color chipColor;
                    IconData chipIcon;
                    if (!isConfigured) {
                      chipColor = Colors.red[200]!;
                      chipIcon = Icons.cancel;
                    } else if (lastStatus == 'Success') {
                      chipColor = Colors.green[200]!;
                      chipIcon = Icons.check_circle;
                    } else if (lastStatus == 'Failure') {
                      chipColor = Colors.orange[200]!;
                      chipIcon = Icons.error;
                    } else if (lastStatus == 'Reading') {
                      chipColor = Colors.blue[200]!;
                      chipIcon = Icons.play_arrow;
                    } else {
                      chipColor = Colors.grey[300]!;
                      chipIcon = Icons.radio_button_unchecked;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Chip(
                            avatar: Icon(
                              chipIcon,
                              color: Colors.black54,
                              size: 18,
                            ),
                            label: Text('Antenna $ant'),
                            backgroundColor: chipColor,
                          ),
                          Text(
                            isConfigured
                                ? 'Status: $lastStatus'
                                : 'Not Configured',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (lastTag.isNotEmpty)
                            Text(
                              'Tag: $lastTag',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
