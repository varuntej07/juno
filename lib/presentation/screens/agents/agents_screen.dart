import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/agent.dart';
import '../../viewmodels/connectors_viewmodel.dart';
import '../../viewmodels/dietary_profile_viewmodel.dart';
import '../connectors/connectors_screen.dart';
import '../nutrition/dietary_onboarding_screen.dart';
import '../nutrition/nutrition_scan_screen.dart';

class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectorsViewModel>().load();
      context.read<DietaryProfileViewModel>().load();
    });
  }

  void _handleAgentTap(BuildContext context, Agent agent) {
    if (agent.tapBehavior == AgentTapBehavior.chatThread) {
      context.push('/agents/${agent.id}');
      return;
    }

    // Custom screens for Nutrition and Calendar
    switch (agent.id) {
      case 'nutrition':
        final profileVm = context.read<DietaryProfileViewModel>();
        if (!profileVm.nutritionAgentEnabled) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const DietaryOnboardingScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NutritionScanScreen()),
          );
        }
      case 'calendar':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConnectorsScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Agents',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF00D4AA),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 28,
            crossAxisSpacing: 16,
            childAspectRatio: 0.82,
          ),
          itemCount: kAgents.length,
          itemBuilder: (context, i) {
            final agent = kAgents[i];
            return _AgentTile(
              agent: agent,
              onTap: () => _handleAgentTap(context, agent),
            );
          },
        ),
      ),
    );
  }
}

// ── Agent tile ────────────────────────────────────────────────────────────────

class _AgentTile extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;

  const _AgentTile({required this.agent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: 'agent-icon-${agent.id}',
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: agent.color,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: agent.color.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(agent.icon, color: Colors.white, size: 34),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            agent.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
