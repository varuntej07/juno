import 'package:flutter/material.dart';

enum AgentTapBehavior { chatThread, customScreen }

/// Static metadata for one agent tile on the Agents grid.
class Agent {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final AgentTapBehavior tapBehavior;

  const Agent({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.tapBehavior = AgentTapBehavior.chatThread,
  });
}

/// All agents shown on the Agents grid, in display order.
/// Nutrition and Calendar keep their existing custom screens.
/// The four new agents open a per-agent chat thread.
const List<Agent> kAgents = [
  Agent(
    id: 'cricket',
    name: 'CricBolt',
    subtitle: 'Live scores & digests',
    icon: Icons.sports_cricket_rounded,
    color: Color(0xFF1B5E20),
  ),
  Agent(
    id: 'technews',
    name: 'BytePulse',
    subtitle: 'AI & tech news',
    icon: Icons.bolt_rounded,
    color: Color(0xFF0D47A1),
  ),
  Agent(
    id: 'jobs',
    name: 'HuntMode',
    subtitle: 'Job listings',
    icon: Icons.travel_explore_rounded,
    color: Color(0xFFE65100),
  ),
  Agent(
    id: 'posts',
    name: 'PostForge',
    subtitle: 'Draft your tweets',
    icon: Icons.edit_note_rounded,
    color: Color(0xFF4A148C),
  ),
  Agent(
    id: 'nutrition',
    name: 'Nutrition',
    subtitle: 'Scan & track food',
    icon: Icons.camera_alt_rounded,
    color: Color(0xFF00695C),
    tapBehavior: AgentTapBehavior.customScreen,
  ),
  Agent(
    id: 'calendar',
    name: 'Calendar',
    subtitle: 'Google Calendar sync',
    icon: Icons.calendar_month_rounded,
    color: Color(0xFF283593),
    tapBehavior: AgentTapBehavior.customScreen,
  ),
];
