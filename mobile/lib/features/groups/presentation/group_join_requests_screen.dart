import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../notifications/data/notification_api.dart';

class GroupJoinRequestsScreen extends StatefulWidget {
  const GroupJoinRequestsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  State<GroupJoinRequestsScreen> createState() => _GroupJoinRequestsScreenState();
}

class _GroupJoinRequestsScreenState extends State<GroupJoinRequestsScreen> {
  List<GroupJoinRequest> requests = const [];
  final busy = <String>{};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final items = await SocialApi.instance.groupJoinRequests(widget.groupId);
      if (mounted) setState(() { requests = items; loading = false; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Join requests load nahi hui.'; });
    }
  }

  Future<void> _review(GroupJoinRequest request, bool approve) async {
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reject join request?'),
          content: Text('${request.name} group join nahi kar payenge.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reject', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() => busy.add(request.id));
    try {
      await SocialApi.instance.reviewGroupJoinRequest(widget.groupId, request.id, approve: approve);
      await NotificationCenter.instance.refresh();
      if (!mounted) return;
      setState(() => requests = requests.where((item) => item.id != request.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? '${request.name} added to the group.' : '${request.name} request rejected.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request update nahi hui. Retry karein.')));
    } finally {
      if (mounted) setState(() => busy.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: Text(requests.isEmpty ? 'Join Requests' : 'Join Requests (${requests.length})')),
    body: GroopXBackground(
      child: loading
          ? const Center(child: CircularProgressIndicator(color: authPurple))
          : error != null
              ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: authPurple,
                  child: requests.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          GroopXEmptyState(icon: Icons.how_to_reg_outlined, title: 'No pending requests', message: 'New invite-link requests yahan dikhai denge.'),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                          itemCount: requests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final request = requests[index];
                            final working = busy.contains(request.id);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    GroopXAvatar(label: request.name, imageUrl: request.avatarUrl, radius: 23),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(request.name, style: const TextStyle(fontWeight: FontWeight.w700, color: authInk)),
                                      Text(request.username.isEmpty ? 'GroopX user' : '@${request.username}', style: const TextStyle(color: authMuted, fontSize: 12)),
                                    ])),
                                    Text(_time(request.requestedAt), style: const TextStyle(color: authMuted, fontSize: 10)),
                                  ]),
                                  const SizedBox(height: 14),
                                  Row(children: [
                                    Expanded(child: OutlinedButton(onPressed: working ? null : () => _review(request, false), child: const Text('Reject', style: TextStyle(color: Colors.red)))),
                                    const SizedBox(width: 10),
                                    Expanded(child: FilledButton.icon(
                                      onPressed: working ? null : () => _review(request, true),
                                      icon: working ? const SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 18),
                                      label: Text(working ? 'Updating…' : 'Approve'),
                                    )),
                                  ]),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
    ),
  );

  String _time(DateTime value) {
    final now = DateTime.now();
    if (now.difference(value).inDays == 0) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  }
}
