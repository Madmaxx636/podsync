import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/player.dart';
import 'common.dart';

/// Sleep timer choices shared by the toolbar, the Controls menu and the phone player.
const sleepChoices = <String, Duration>{
  '15 minutes': Duration(minutes: 15),
  '30 minutes': Duration(minutes: 30),
  '45 minutes': Duration(minutes: 45),
  '1 hour': Duration(hours: 1),
  '90 minutes': Duration(minutes: 90),
};

/// "12:30" or "1:05:00".
String fmtSleep(Duration d) => fmtDuration(d);

void applySleepChoice(PlayerController player, String choice) {
  switch (choice) {
    case 'off':
      player.cancelSleepTimer();
    case 'end':
      player.sleepAfterEpisode();
    case 'plus':
      player.extendSleepTimer(const Duration(minutes: 10));
    default:
      player.startSleepTimer(sleepChoices[choice]!);
  }
}

String sleepStatus(PlayerController player) {
  if (player.sleepAtEpisodeEnd) return 'Stops after this episode';
  final left = player.sleepRemaining;
  return left == null ? 'Off' : '${fmtSleep(left)} left';
}

/// The moon button: shows the countdown while a timer runs, and opens the choices.
class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return PopupMenuButton<String>(
      tooltip: player.sleepActive
          ? 'Sleep timer: ${sleepStatus(player)}'
          : 'Sleep timer',
      onSelected: (v) => applySleepChoice(player, v),
      itemBuilder: (c) => [
        if (player.sleepActive)
          PopupMenuItem(enabled: false, child: Text(sleepStatus(player))),
        for (final k in sleepChoices.keys)
          PopupMenuItem(value: k, child: Text(k)),
        const PopupMenuItem(value: 'end', child: Text('End of episode')),
        if (player.sleepRemaining != null)
          const PopupMenuItem(value: 'plus', child: Text('Add 10 minutes')),
        if (player.sleepActive)
          const PopupMenuItem(value: 'off', child: Text('Turn off')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              player.sleepActive ? Icons.bedtime : Icons.bedtime_outlined,
              size: 22,
            ),
            if (player.sleepRemaining != null)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(
                  fmtSleep(player.sleepRemaining!),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (player.sleepAtEpisodeEnd)
              const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Text('end', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}
