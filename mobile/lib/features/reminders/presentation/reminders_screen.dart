import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../data/reminder_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<ReminderItem> reminders = const [];
  String filter = 'upcoming';
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      if (mounted) setState(() { loading = true; error = null; });
      final items = await ReminderApi.instance.list(filter);
      if (mounted) setState(() { reminders = items; loading = false; });
    } catch (_) { if (mounted) setState(() { loading = false; error = 'Unable to load reminders'; }); }
  }

  Future<void> _setFilter(String value) async { setState(() => filter = value); await _load(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(backgroundColor: Colors.white,leading:IconButton(onPressed:()=>context.go('/chats'),icon:const Icon(Icons.arrow_back)), title: const Text('Reminder / Meeting', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)), actions: [IconButton(onPressed: _showCreate, icon: const Icon(Icons.add_circle_outline, color: authPurple))]),
    body: GroopXBackground(child:Column(children: [
      Padding(padding: const EdgeInsets.all(18), child: Row(children: [('upcoming','Upcoming'),('completed','Completed'),('all','All')].map((item) => Expanded(child: InkWell(onTap: () => _setFilter(item.$1), child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: filter == item.$1 ? const Color(0xFFF0EBFF) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE7E5ED))), child: Text(item.$2, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: filter == item.$1 ? authPurple : authMuted)))))).toList())),
      Expanded(child: RefreshIndicator(onRefresh: _load, color: authPurple, child: loading ? const Center(child: CircularProgressIndicator(color: authPurple)) : error != null ? ListView(children: [const SizedBox(height:100),GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:'Reminders load nahi hue.',actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)]) : reminders.isEmpty ? ListView(children: [const SizedBox(height:100),GroopXEmptyState(icon:Icons.event_available_outlined,title:'No reminders found',message:'Meeting, follow-up ya important task ke liye reminder create karein.',actionLabel:'New Reminder',onAction:_showCreate)]) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 18), itemCount: reminders.length, itemBuilder: (_, i) => _ReminderCard(item: reminders[i], onChanged: _load)))),
    ])),
    floatingActionButton: FloatingActionButton.extended(onPressed: _showCreate, backgroundColor: authPurple, foregroundColor: Colors.white, icon: const Icon(Icons.add), label: const Text('New Reminder')),
  );

  Future<void> _showCreate() async {
    final created = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (_) => const _CreateReminderSheet());
    if (created == true) { filter = 'upcoming'; await _load(); }
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.item, required this.onChanged});
  final ReminderItem item;
  final Future<void> Function() onChanged;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 13), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFE8E7EE)), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10)]), child: Row(children: [
    CircleAvatar(backgroundColor: (item.status == 'completed' ? const Color(0xFF17BFAE) : authPurple).withValues(alpha: .12), child: Icon(item.status == 'completed' ? Icons.check : Icons.notifications_none, color: item.status == 'completed' ? const Color(0xFF17BFAE) : authPurple)), const SizedBox(width: 13),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, color: authInk)), const SizedBox(height: 6), Text(_dateLabel(item.scheduledAt), style: const TextStyle(fontSize: 11, color: authMuted)), if (item.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(item.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: authMuted)))])),
    PopupMenuButton<String>(onSelected: (value) async { if (value == 'delete') { await ReminderApi.instance.delete(item.id); } else { await ReminderApi.instance.updateStatus(item.id, value); } await onChanged(); }, itemBuilder: (_) => [if (item.status != 'completed') const PopupMenuItem(value: 'completed', child: Text('Mark completed')), if (item.status != 'cancelled') const PopupMenuItem(value: 'cancelled', child: Text('Cancel')), const PopupMenuItem(value: 'delete', child: Text('Delete'))]),
  ]));
}

class _CreateReminderSheet extends StatefulWidget {
  const _CreateReminderSheet();
  @override
  State<_CreateReminderSheet> createState() => _CreateReminderSheetState();
}

class _CreateReminderSheetState extends State<_CreateReminderSheet> {
  final title = TextEditingController();
  final notes = TextEditingController();
  DateTime scheduledAt = DateTime.now().add(const Duration(hours: 1));
  bool saving = false;

  @override
  void dispose() { title.dispose(); notes.dispose(); super.dispose(); }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, initialDate: scheduledAt, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(scheduledAt));
    if (time != null) setState(() => scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a title'))); return; }
    if (scheduledAt.isBefore(DateTime.now())) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a future date and time'))); return; }
    try {
      setState(() => saving = true);
      await ReminderApi.instance.create(title: title.text.trim(), scheduledAt: scheduledAt, notes: notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) { if (mounted) { setState(() => saving = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder could not be created'))); } }
  }

  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Center(child: Text('Create Reminder', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: authInk))), const SizedBox(height: 22),
    TextField(controller: title, maxLength: 160, decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title))), const SizedBox(height: 8),
    InkWell(onTap: _pickDateTime, child: InputDecorator(decoration: const InputDecoration(labelText: 'Date & Time', prefixIcon: Icon(Icons.calendar_month)), child: Text(_dateLabel(scheduledAt)))), const SizedBox(height: 12),
    TextField(controller: notes, maxLines: 2, maxLength: 1000, decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes))), const SizedBox(height: 12),
    PurpleButton(label: saving ? 'Saving...' : 'Create Reminder', onPressed: saving ? null : _save),
  ]));
}

String _dateLabel(DateTime value) {
  final hour = value.hour == 0 ? 12 : value.hour > 12 ? value.hour - 12 : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}
