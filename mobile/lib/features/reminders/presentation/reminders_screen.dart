import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../../chat/data/chat_api.dart';
import '../../notifications/data/notification_api.dart';
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
  bool calendarView = false;
  late DateTime selectedDate;
  late DateTime visibleMonth;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    selectedDate = DateTime(today.year, today.month, today.day);
    visibleMonth = DateTime(today.year, today.month);
    _load();
  }

  Future<void> _load() async {
    final selectedFilter = filter;
    try {
      if (mounted) setState(() { loading = true; error = null; });
      final apiStatus = selectedFilter == 'overdue' || selectedFilter == 'meetings' ? 'upcoming' : selectedFilter;
      var items = await ReminderApi.instance.list(apiStatus, itemType: selectedFilter == 'meetings' ? 'meeting' : '');
      if (selectedFilter == 'overdue') items = items.where((item) => item.scheduledAt.isBefore(DateTime.now())).toList();
      if (mounted && filter == selectedFilter) setState(() { reminders = items; loading = false; });
    } catch (_) { if (mounted && filter == selectedFilter) setState(() { loading = false; error = 'Unable to load reminders'; }); }
  }

  Future<void> _setFilter(String value) async { setState(() => filter = value); await _load(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: Colors.white,
      leading: IconButton(onPressed: () => context.go('/chats'), icon: const Icon(Icons.arrow_back)),
      title: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)),
      actions: [
        IconButton(
          tooltip: calendarView ? 'List view' : 'Calendar view',
          onPressed: () => setState(() => calendarView = !calendarView),
          icon: Icon(calendarView ? Icons.view_agenda_outlined : Icons.calendar_month_outlined, color: authPurple),
        ),
        PopupMenuButton<String>(
          tooltip: 'Create',
          icon: const Icon(Icons.add_circle_outline, color: authPurple),
          onSelected: (value) => _showCreate(initialType: value, initialDate: calendarView ? _selectedCreationTime() : null),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'reminder', child: ListTile(leading: Icon(Icons.notifications_none, color: authPurple), title: Text('New reminder'))),
            PopupMenuItem(value: 'meeting', child: ListTile(leading: Icon(Icons.video_call_outlined, color: authPurple), title: Text('New meeting'))),
          ],
        ),
      ],
    ),
    body: GroopXBackground(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18,14,18,10), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [('upcoming','Upcoming'),('meetings','Meetings'),('overdue','Overdue'),('completed','Completed'),('all','All')].map((item) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(item.$2), selected: filter == item.$1, onSelected: (_) => _setFilter(item.$1), selectedColor: const Color(0xFFF0EBFF), labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: filter == item.$1 ? authPurple : authMuted), side: const BorderSide(color: Color(0xFFE7E5ED))))).toList()))),
      Expanded(child: _buildContent()),
    ])),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _showCreate(initialDate: calendarView ? _selectedCreationTime() : null),
      backgroundColor: authPurple,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: Text(calendarView ? 'New Schedule' : 'New Reminder'),
    ),
  );

  Widget _buildContent() {
    if (loading) return const Center(child: CircularProgressIndicator(color: authPurple));
    if (error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        color: authPurple,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          const SizedBox(height: 100),
          GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: 'Schedule load nahi hua.', actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load),
        ]),
      );
    }
    if (calendarView) {
      return _ScheduleCalendarView(
        items: reminders,
        selectedDate: selectedDate,
        visibleMonth: visibleMonth,
        onRefresh: _load,
        onChanged: _load,
        onDateSelected: (date) => setState(() {
          selectedDate = DateTime(date.year, date.month, date.day);
          visibleMonth = DateTime(date.year, date.month);
        }),
        onMonthChanged: _changeMonth,
        onToday: _showToday,
        onCreate: () => _showCreate(initialType: filter == 'meetings' ? 'meeting' : 'reminder', initialDate: _selectedCreationTime()),
      );
    }
    if (reminders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: authPurple,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          const SizedBox(height: 100),
          GroopXEmptyState(
            icon: filter == 'meetings' ? Icons.video_call_outlined : Icons.event_available_outlined,
            title: filter == 'meetings' ? 'No meetings scheduled' : 'No reminders found',
            message: filter == 'meetings' ? 'Direct ya group chat ke saath audio/video meeting schedule karein.' : 'Meeting, follow-up ya important task ke liye reminder create karein.',
            actionLabel: filter == 'meetings' ? 'Schedule Meeting' : 'New Reminder',
            onAction: () => _showCreate(initialType: filter == 'meetings' ? 'meeting' : 'reminder'),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: authPurple,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
        itemCount: reminders.length,
        itemBuilder: (_, index) => _ReminderCard(item: reminders[index], onChanged: _load),
      ),
    );
  }

  void _changeMonth(int delta) {
    final target = DateTime(visibleMonth.year, visibleMonth.month + delta);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    final day = selectedDate.day > lastDay ? lastDay : selectedDate.day;
    setState(() {
      visibleMonth = target;
      selectedDate = DateTime(target.year, target.month, day);
    });
  }

  void _showToday() {
    final now = DateTime.now();
    setState(() {
      selectedDate = DateTime(now.year, now.month, now.day);
      visibleMonth = DateTime(now.year, now.month);
    });
  }

  DateTime _selectedCreationTime() {
    final now = DateTime.now();
    final selected = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 9);
    if (_sameDay(selectedDate, now) || selected.isBefore(now)) return now.add(const Duration(hours: 1));
    return selected;
  }

  Future<void> _showCreate({String initialType = 'reminder', DateTime? initialDate}) async {
    final createdType = await showModalBottomSheet<String>(context: context, isScrollControlled: true, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (_) => _CreateReminderSheet(initialType: initialType, initialDate: initialDate));
    if (createdType != null) { filter = createdType == 'meeting' ? 'meetings' : 'upcoming'; await _load(); }
  }
}

class _ScheduleCalendarView extends StatelessWidget {
  const _ScheduleCalendarView({required this.items, required this.selectedDate, required this.visibleMonth, required this.onRefresh, required this.onChanged, required this.onDateSelected, required this.onMonthChanged, required this.onToday, required this.onCreate});
  final List<ReminderItem> items;
  final DateTime selectedDate;
  final DateTime visibleMonth;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onChanged;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<int> onMonthChanged;
  final VoidCallback onToday;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final selectedItems = items.where((item) => _sameDay(item.scheduledAt, selectedDate)).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: authPurple,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _CalendarPanel(items: items, selectedDate: selectedDate, visibleMonth: visibleMonth, onDateSelected: onDateSelected, onMonthChanged: onMonthChanged, onToday: onToday)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 18, 8),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_agendaDateLabel(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: authInk)),
                const SizedBox(height: 2),
                Text('${selectedItems.length} ${selectedItems.length == 1 ? 'item' : 'items'} scheduled', style: const TextStyle(fontSize: 12, color: authMuted)),
              ])),
              TextButton.icon(onPressed: onCreate, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
            ]),
          )),
          if (selectedItems.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 26, 18, 0),
              child: GroopXEmptyState(icon: Icons.event_available_outlined, title: 'Nothing scheduled', message: 'Is date ke liye reminder ya meeting add karein.', actionLabel: 'Add to schedule', actionIcon: Icons.add, onAction: onCreate),
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((_, index) => _ReminderCard(item: selectedItems[index], onChanged: onChanged), childCount: selectedItems.length)),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({required this.items, required this.selectedDate, required this.visibleMonth, required this.onDateSelected, required this.onMonthChanged, required this.onToday});
  final List<ReminderItem> items;
  final DateTime selectedDate;
  final DateTime visibleMonth;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<int> onMonthChanged;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final dates = List<DateTime>.generate(42, (index) => gridStart.add(Duration(days: index)));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8E7EE)), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 12)]),
      child: Column(children: [
        Row(children: [
          IconButton(tooltip: 'Previous month', onPressed: () => onMonthChanged(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(_monthLabel(visibleMonth), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: authInk))),
          TextButton(onPressed: onToday, child: const Text('Today')),
          IconButton(tooltip: 'Next month', onPressed: () => onMonthChanged(1), icon: const Icon(Icons.chevron_right)),
        ]),
        const Row(children: [
          _WeekdayLabel('Mon'), _WeekdayLabel('Tue'), _WeekdayLabel('Wed'), _WeekdayLabel('Thu'), _WeekdayLabel('Fri'), _WeekdayLabel('Sat'), _WeekdayLabel('Sun'),
        ]),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: .95),
          itemCount: dates.length,
          itemBuilder: (_, index) {
            final date = dates[index];
            final dayItems = items.where((item) => _sameDay(item.scheduledAt, date)).toList();
            return _CalendarDay(date: date, inMonth: date.month == visibleMonth.month && date.year == visibleMonth.year, selected: _sameDay(date, selectedDate), today: _sameDay(date, DateTime.now()), items: dayItems, onTap: () => onDateSelected(date));
          },
        ),
      ]),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: authMuted))));
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({required this.date, required this.inMonth, required this.selected, required this.today, required this.items, required this.onTap});
  final DateTime date;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<ReminderItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dots = items.take(3).map((item) => Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? Colors.white : item.status == 'completed' ? const Color(0xFF17BFAE) : item.status == 'cancelled' ? Colors.redAccent : item.meeting ? const Color(0xFF2563EB) : authPurple))).toList();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: selected ? authPurple : Colors.transparent, borderRadius: BorderRadius.circular(12), border: today && !selected ? Border.all(color: authPurple) : null),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${date.day}', style: TextStyle(fontSize: 12, fontWeight: selected || today ? FontWeight.w800 : FontWeight.w500, color: selected ? Colors.white : inMonth ? authInk : const Color(0xFFB7BAC5))),
          const SizedBox(height: 3),
          SizedBox(height: 5, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: dots)),
        ]),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.item, required this.onChanged});
  final ReminderItem item;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final overdue = item.status == 'upcoming' && item.scheduledAt.isBefore(DateTime.now());
    final completed = item.status == 'completed';
    final cancelled = item.status == 'cancelled';
    final meeting = item.meeting;
    final canJoin = meeting && item.status == 'upcoming' && (item.isOrganizer || item.inviteStatus == 'accepted');
    final accent = completed ? const Color(0xFF17BFAE) : cancelled ? Colors.redAccent : overdue ? const Color(0xFFE05A47) : meeting ? const Color(0xFF2563EB) : authPurple;
    final icon = completed ? Icons.check : cancelled ? Icons.event_busy_outlined : overdue ? Icons.notification_important_outlined : meeting ? (item.callKind == 'audio' ? Icons.phone_in_talk_outlined : Icons.videocam_outlined) : Icons.notifications_none;
    final meetingLabel = meeting ? '${item.callKind == 'audio' ? 'Audio' : 'Video'} meeting · ' : '';
    final repeatLabel = item.repeatLabel.isEmpty ? '' : ' · ${item.repeatLabel}';
    final callPath = '/call/${item.callKind == 'audio' ? 'audio' : 'video'}/${item.conversationId}?meeting=${Uri.encodeComponent(item.id)}&title=${Uri.encodeComponent(item.title)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: overdue ? const Color(0xFFF1B8AF) : const Color(0xFFE8E7EE)), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10)]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(backgroundColor: accent.withValues(alpha: .12), child: Icon(icon, color: accent)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, color: authInk)),
          const SizedBox(height: 6),
          Text('$meetingLabel${overdue ? 'Overdue · ' : ''}${_dateLabel(item.scheduledAt)}$repeatLabel', style: TextStyle(fontSize: 11, color: overdue ? accent : authMuted, fontWeight: overdue ? FontWeight.w700 : FontWeight.w400)),
          if (item.invited && item.organizerName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('Host: ${item.organizerName}', style: const TextStyle(fontSize: 11, color: authInk, fontWeight: FontWeight.w600))),
          if (item.isOrganizer && meeting && item.invitedCount > 0) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () => _openResponses(context),
              icon: const Icon(Icons.groups_2_outlined, size: 16),
              label: Text('${item.acceptedCount} accepted · ${item.pendingCount} pending${item.declinedCount > 0 ? ' · ${item.declinedCount} declined' : ''}'),
            ),
          ),
          if (item.conversationTitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('Chat: ${item.conversationTitle}', style: const TextStyle(fontSize: 11, color: authPurple, fontWeight: FontWeight.w600))),
          if (item.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(item.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: authMuted))),
          if (item.invited && item.status == 'upcoming') Padding(padding: const EdgeInsets.only(top: 10), child: _MeetingRsvp(item: item, onChanged: onChanged)),
          if (canJoin) Padding(padding: const EdgeInsets.only(top: 5), child: TextButton.icon(style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0,30), tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: () => context.push(callPath), icon: Icon(item.callKind == 'audio' ? Icons.call_outlined : Icons.video_call_outlined, size: 17), label: Text(item.isOrganizer ? (item.callKind == 'audio' ? 'Start audio call' : 'Start video call') : (item.callKind == 'audio' ? 'Join audio call' : 'Join video call')))),
        ])),
        PopupMenuButton<String>(onSelected: (value) async {
      if (value == 'edit') {
        final changed=await showModalBottomSheet<String>(context:context,isScrollControlled:true,backgroundColor:Colors.white,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(_)=>_CreateReminderSheet(item:item));
        if(changed!=null)await onChanged();
        return;
      }
      if (value == 'snooze') { await _snooze(context); return; }
      if (value == 'responses') { _openResponses(context); return; }
      if (value == 'chat' && item.conversationId.isNotEmpty) { context.push('/chat/${item.conversationId}'); return; }
      if (value == 'call' && item.meeting && item.conversationId.isNotEmpty) { context.push(callPath); return; }
      if (value == 'delete') { await ReminderApi.instance.delete(item.id); } else { await ReminderApi.instance.updateStatus(item.id, value); }
      await onChanged();
    }, itemBuilder: (_) => item.isOrganizer
      ? [const PopupMenuItem(value:'edit',child:Text('Edit / reschedule')),if(item.meeting&&item.invitedCount>0)const PopupMenuItem(value:'responses',child:Text('View participant responses')),if(item.status=='upcoming')PopupMenuItem(value:'snooze',child:Text(item.meeting?'Snooze alert':'Snooze reminder')),if(canJoin)PopupMenuItem(value:'call',child:Text(item.callKind=='audio'?'Start audio call':'Start video call')),if(item.conversationId.isNotEmpty)const PopupMenuItem(value:'chat',child:Text('Open linked chat')),if(item.status!='completed')PopupMenuItem(value:'completed',child:Text(item.repeatRule=='none'?'Mark completed':'Stop repeating & complete')),if(item.status!='cancelled')PopupMenuItem(value:'cancelled',child:Text(item.repeatRule=='none'?'Cancel':'Stop repeating & cancel')),const PopupMenuItem(value:'delete',child:Text('Delete'))]
      : [if(canJoin)PopupMenuItem(value:'call',child:Text(item.callKind=='audio'?'Join audio call':'Join video call')),if(item.conversationId.isNotEmpty)const PopupMenuItem(value:'chat',child:Text('Open linked chat'))]),
      ]),
    );
  }

  void _openResponses(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _MeetingAttendeesSheet(meetingId: item.id, meetingTitle: item.title),
    );
  }

  Future<void> _snooze(BuildContext context) async {
    final now = DateTime.now();
    final tenMinutes = now.add(const Duration(minutes: 10));
    final oneHour = now.add(const Duration(hours: 1));
    final tomorrow = DateTime(now.year, now.month, now.day + 1, item.scheduledAt.hour, item.scheduledAt.minute);
    final selected = await showModalBottomSheet<DateTime>(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Snooze reminder', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Choose when you want to be reminded again')),
      ListTile(leading: const Icon(Icons.timer_outlined, color: authPurple), title: const Text('In 10 minutes'), subtitle: Text(_dateLabel(tenMinutes)), onTap: () => Navigator.pop(sheetContext, tenMinutes)),
      ListTile(leading: const Icon(Icons.schedule_outlined, color: authPurple), title: const Text('In 1 hour'), subtitle: Text(_dateLabel(oneHour)), onTap: () => Navigator.pop(sheetContext, oneHour)),
      ListTile(leading: const Icon(Icons.wb_sunny_outlined, color: authPurple), title: const Text('Tomorrow'), subtitle: Text(_dateLabel(tomorrow)), onTap: () => Navigator.pop(sheetContext, tomorrow)),
      const SizedBox(height: 8),
    ])));
    if (selected == null || !context.mounted) return;
    try {
      await ReminderApi.instance.snooze(item.id, selected);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reminder snoozed until ${_dateLabel(selected)}')));
      await onChanged();
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder snooze nahi hua. Retry karein.')));
    }
  }
}

class _MeetingAttendeesSheet extends StatefulWidget {
  const _MeetingAttendeesSheet({required this.meetingId, required this.meetingTitle});
  final String meetingId;
  final String meetingTitle;

  @override
  State<_MeetingAttendeesSheet> createState() => _MeetingAttendeesSheetState();
}

class _MeetingAttendeesSheetState extends State<_MeetingAttendeesSheet> {
  late Future<List<MeetingAttendee>> request;

  @override
  void initState() {
    super.initState();
    request = ReminderApi.instance.attendees(widget.meetingId);
  }

  Future<void> _reload() async {
    final next = ReminderApi.instance.attendees(widget.meetingId);
    setState(() => request = next);
    try { await next; } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .72,
    child: FutureBuilder<List<MeetingAttendee>>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: authPurple));
        }
        if (snapshot.hasError) {
          return GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Responses unavailable', message: 'Participant responses load nahi hue.', actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: () => _reload());
        }
        final attendees = snapshot.data ?? const [];
        final accepted = attendees.where((item) => item.response == 'accepted').length;
        final pending = attendees.where((item) => item.response == 'pending').length;
        final declined = attendees.where((item) => item.response == 'declined').length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 12, 12),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Participant responses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: authInk)),
                const SizedBox(height: 3),
                Text(widget.meetingTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: authMuted)),
              ])),
              IconButton(tooltip: 'Refresh', onPressed: () => _reload(), icon: const Icon(Icons.refresh, color: authPurple)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(spacing: 8, runSpacing: 7, children: [
              _responseChip('$accepted accepted', const Color(0xFF16876F), Icons.check_circle_outline),
              _responseChip('$pending pending', const Color(0xFFB26A00), Icons.schedule_outlined),
              _responseChip('$declined declined', const Color(0xFFC14444), Icons.cancel_outlined),
            ]),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: attendees.isEmpty
                ? const GroopXEmptyState(icon: Icons.group_off_outlined, title: 'No participants invited', message: 'Meeting edit karke chat participants ko invite karein.')
                : RefreshIndicator(
                    onRefresh: _reload,
                    color: authPurple,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: attendees.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                      itemBuilder: (_, index) {
                        final attendee = attendees[index];
                        final responseTime = attendee.respondedAt == null ? 'Response saved' : 'Responded ${_dateLabel(attendee.respondedAt!)}';
                        final subtitle = attendee.response == 'pending'
                            ? (attendee.username.isEmpty ? 'Awaiting response' : '@${attendee.username} · Awaiting response')
                            : '${attendee.username.isEmpty ? '' : '@${attendee.username} · '}$responseTime';
                        return ListTile(
                          leading: GroopXAvatar(label: attendee.name, imageUrl: attendee.avatarUrl, radius: 22),
                          title: Text(attendee.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: authInk)),
                          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: _responseBadge(attendee.response),
                        );
                      },
                    ),
                  ),
          ),
        ]);
      },
    ),
  );

  Widget _responseChip(String label, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(18)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: color), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))]),
  );

  Widget _responseBadge(String response) {
    final color = response == 'accepted' ? const Color(0xFF16876F) : response == 'declined' ? const Color(0xFFC14444) : const Color(0xFFB26A00);
    final label = response == 'accepted' ? 'Accepted' : response == 'declined' ? 'Declined' : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _MeetingRsvp extends StatelessWidget {
  const _MeetingRsvp({required this.item, required this.onChanged});
  final ReminderItem item;
  final Future<void> Function() onChanged;

  Future<void> _respond(BuildContext context, String response) async {
    try {
      await ReminderApi.instance.respond(item.id, response);
      await NotificationCenter.instance.refresh();
      await onChanged();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response == 'accepted' ? 'Meeting accepted' : 'Meeting declined')));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meeting response save nahi hua. Retry karein.')));
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
    OutlinedButton.icon(
      onPressed: item.inviteStatus == 'accepted' ? null : () => _respond(context, 'accepted'),
      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF16876F), backgroundColor: item.inviteStatus == 'accepted' ? const Color(0xFFE5F8F3) : null, side: const BorderSide(color: Color(0xFF7DD3C7)), visualDensity: VisualDensity.compact),
      icon: const Icon(Icons.check_circle_outline, size: 17),
      label: Text(item.inviteStatus == 'accepted' ? 'Accepted' : 'Accept'),
    ),
    OutlinedButton.icon(
      onPressed: item.inviteStatus == 'declined' ? null : () => _respond(context, 'declined'),
      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC14444), backgroundColor: item.inviteStatus == 'declined' ? const Color(0xFFFFEEEE) : null, side: const BorderSide(color: Color(0xFFF2AAAA)), visualDensity: VisualDensity.compact),
      icon: const Icon(Icons.cancel_outlined, size: 17),
      label: Text(item.inviteStatus == 'declined' ? 'Declined' : 'Decline'),
    ),
    if (item.inviteStatus == 'pending') const Text('Response pending', style: TextStyle(fontSize: 11, color: authMuted)),
  ]);
}

class _CreateReminderSheet extends StatefulWidget {
  const _CreateReminderSheet({this.item, this.initialType = 'reminder', this.initialDate});
  final ReminderItem? item;
  final String initialType;
  final DateTime? initialDate;
  @override
  State<_CreateReminderSheet> createState() => _CreateReminderSheetState();
}

class _CreateReminderSheetState extends State<_CreateReminderSheet> {
  late final TextEditingController title;
  late final TextEditingController notes;
  late DateTime scheduledAt;
  late String conversationId;
  late String conversationTitle;
  late String itemType;
  late String callKind;
  late String repeatRule;
  bool sendInvite = true;
  bool saving = false;
  bool loadingChats = false;

  @override
  void initState() {
    super.initState();
    title=TextEditingController(text:widget.item?.title??'');
    notes=TextEditingController(text:widget.item?.notes??'');
    scheduledAt=widget.item?.scheduledAt??widget.initialDate??DateTime.now().add(const Duration(hours:1));
    conversationId=widget.item?.conversationId??'';
    conversationTitle=widget.item?.conversationTitle??'';
    itemType=widget.item?.itemType??widget.initialType;
    callKind=widget.item?.callKind.isNotEmpty==true?widget.item!.callKind:'video';
    repeatRule=widget.item?.repeatRule??'none';
    sendInvite=widget.item==null||!widget.item!.meeting||widget.item!.invitedCount>0;
  }

  @override
  void dispose() { title.dispose(); notes.dispose(); super.dispose(); }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, initialDate: scheduledAt, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(scheduledAt));
    if (time != null) setState(() => scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickConversation() async {
    if (loadingChats || saving) return;
    setState(() => loadingChats = true);
    try {
      final chats = await ChatApi.instance.conversations();
      if (!mounted) return;
      final allowNone = itemType != 'meeting';
      final selected = await showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .68,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 14), child: Text('Link a chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: authInk))),
            const Divider(height: 1),
            Expanded(child: chats.isEmpty ? const GroopXEmptyState(icon:Icons.forum_outlined,title:'No chats found',message:'Meeting schedule karne se pehle direct ya group chat create karein.') : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: chats.length + (allowNone ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, index) {
                if (allowNone && index == 0) {
                  return ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFFF0EBFF), child: Icon(Icons.link_off, color: authPurple)),
                    title: const Text('No linked chat', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Keep this reminder separate'),
                    trailing: conversationId.isEmpty ? const Icon(Icons.check_circle, color: authPurple) : null,
                    onTap: () => Navigator.pop(sheetContext, <String, String>{'id':'','title':''}),
                  );
                }
                final chat = chats[index - (allowNone ? 1 : 0)];
                final subtitle = chat.displayPreview.isEmpty ? (chat.group ? 'Group' : 'Direct chat') : chat.displayPreview;
                return ListTile(
                  leading: CircleAvatar(backgroundColor: Color(chat.color).withValues(alpha: .12), child: Icon(chat.group ? Icons.groups_outlined : Icons.person_outline, color: Color(chat.color))),
                  title: Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: conversationId == chat.id ? const Icon(Icons.check_circle, color: authPurple) : null,
                  onTap: () => Navigator.pop(sheetContext, <String, String>{'id':chat.id,'title':chat.name}),
                );
              },
            )),
          ]),
        ),
      );
      if (!mounted || selected == null) return;
      setState(() {
        conversationId = selected['id'] ?? '';
        conversationTitle = selected['title'] ?? '';
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chats load nahi hui. Retry karein.')));
    } finally {
      if (mounted) setState(() => loadingChats = false);
    }
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a title'))); return; }
    if (scheduledAt.isBefore(DateTime.now())) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a future date and time'))); return; }
    if (itemType == 'meeting' && conversationId.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meeting ke liye direct ya group chat select karein.'))); return; }
    try {
      setState(() => saving = true);
      if(widget.item==null){
        await ReminderApi.instance.create(title:title.text.trim(),scheduledAt:scheduledAt,notes:notes.text.trim(),conversationId:conversationId,itemType:itemType,callKind:itemType=='meeting'?callKind:'',repeatRule:repeatRule,inviteParticipants:itemType=='meeting'&&sendInvite);
        if(itemType=='meeting'&&sendInvite){
          try{await ChatApi.instance.sendMessage(conversationId,_meetingInviteText());}
          catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Meeting save ho gayi, lekin chat invite send nahi hua.')));}
        }
      }
      else{await ReminderApi.instance.update(widget.item!.id,title:title.text.trim(),scheduledAt:scheduledAt,notes:notes.text.trim(),conversationId:conversationId,itemType:itemType,callKind:itemType=='meeting'?callKind:'',repeatRule:repeatRule,inviteParticipants:itemType=='meeting'&&sendInvite);}
      if (mounted) Navigator.pop(context, itemType);
    } catch (_) { if (mounted) { setState(() => saving = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder save nahi hua. Retry karein.'))); } }
  }

  String _meetingInviteText() {
    final mode = callKind == 'audio' ? 'Audio' : 'Video';
    final repeat = _repeatLabel(repeatRule);
    return '📅 $mode meeting: ${title.text.trim()}\n${_dateLabel(scheduledAt)}${repeat.isEmpty ? '' : '\nRepeats $repeat'}\nOpen this chat at the scheduled time to join.';
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Center(child: Text(widget.item==null?(itemType=='meeting'?'Schedule Meeting':'Create Reminder'):(itemType=='meeting'?'Edit Meeting':'Edit Reminder'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: authInk))), const SizedBox(height: 18),
    SizedBox(width:double.infinity,child:SegmentedButton<String>(segments:const[ButtonSegment(value:'reminder',icon:Icon(Icons.notifications_none),label:Text('Reminder')),ButtonSegment(value:'meeting',icon:Icon(Icons.video_call_outlined),label:Text('Meeting'))],selected:{itemType},onSelectionChanged:saving?null:(values)=>setState(()=>itemType=values.first))),const SizedBox(height:18),
    TextField(controller: title, maxLength: 160, decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title))), const SizedBox(height: 8),
    InkWell(onTap: _pickDateTime, child: InputDecorator(decoration: const InputDecoration(labelText: 'Date & Time', prefixIcon: Icon(Icons.calendar_month)), child: Text(_dateLabel(scheduledAt)))), const SizedBox(height: 12),
    DropdownButtonFormField<String>(value:repeatRule,decoration:const InputDecoration(labelText:'Repeat',prefixIcon:Icon(Icons.repeat)),items:const[DropdownMenuItem(value:'none',child:Text("Doesn't repeat")),DropdownMenuItem(value:'daily',child:Text('Every day')),DropdownMenuItem(value:'weekly',child:Text('Every week')),DropdownMenuItem(value:'monthly',child:Text('Every month'))],onChanged:saving?null:(value)=>setState(()=>repeatRule=value??'none')),const SizedBox(height:12),
    if(itemType=='meeting')...[const Text('Call type',style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:authMuted)),const SizedBox(height:8),Row(children:[Expanded(child:ChoiceChip(avatar:Icon(Icons.call_outlined,size:18,color:callKind=='audio'?Colors.white:authPurple),label:const Text('Audio'),selected:callKind=='audio',onSelected:saving?null:(_)=>setState(()=>callKind='audio'),selectedColor:authPurple,labelStyle:TextStyle(color:callKind=='audio'?Colors.white:authInk))),const SizedBox(width:10),Expanded(child:ChoiceChip(avatar:Icon(Icons.videocam_outlined,size:18,color:callKind=='video'?Colors.white:authPurple),label:const Text('Video'),selected:callKind=='video',onSelected:saving?null:(_)=>setState(()=>callKind='video'),selectedColor:authPurple,labelStyle:TextStyle(color:callKind=='video'?Colors.white:authInk)))]),const SizedBox(height:12)],
    InkWell(
      onTap: _pickConversation,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: itemType == 'meeting' ? 'Meeting chat (required)' : 'Linked chat (optional)',
          prefixIcon: const Icon(Icons.forum_outlined),
          suffixIcon: loadingChats ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: authPurple))) : const Icon(Icons.arrow_drop_down),
        ),
        child: Text(conversationId.isEmpty ? (itemType=='meeting'?'Select participants chat':'No chat selected') : conversationTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ), const SizedBox(height: 12),
    TextField(controller: notes, maxLines: 2, maxLength: 1000, decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes))), const SizedBox(height: 12),
    if(itemType=='meeting')SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,value:sendInvite,onChanged:saving?null:(value)=>setState(()=>sendInvite=value),secondary:const Icon(Icons.how_to_reg_outlined,color:authPurple),title:const Text('Invite chat participants'),subtitle:const Text('Participants ke Schedule mein invite aur Accept/Decline option dikhega')),if(itemType=='meeting')const SizedBox(height:8),
    PurpleButton(label: saving ? 'Saving...' : widget.item==null?(itemType=='meeting'?'Schedule Meeting':'Create Reminder'):'Save Changes', onPressed: saving ? null : _save),
  ])));
}

String _repeatLabel(String value) => switch (value) {
  'daily' => 'every day',
  'weekly' => 'every week',
  'monthly' => 'every month',
  _ => '',
};

bool _sameDay(DateTime first, DateTime second) => first.year == second.year && first.month == second.month && first.day == second.day;

String _monthLabel(DateTime value) {
  const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  return '${months[value.month - 1]} ${value.year}';
}

String _agendaDateLabel(DateTime value) {
  const weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  return '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
}

String _dateLabel(DateTime value) {
  final hour = value.hour == 0 ? 12 : value.hour > 12 ? value.hour - 12 : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}
