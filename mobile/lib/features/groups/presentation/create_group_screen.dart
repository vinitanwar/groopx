import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final name = TextEditingController();
  final description = TextEditingController();
  bool private = true;
  final selected = <String>{};
  List<UserOption> members = const [];
  Timer? debounce;
  bool loading = false;
  bool searching = false;
  String? searchError;
  @override
  void dispose() { debounce?.cancel(); name.dispose(); description.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Create Group', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)), actions: [TextButton(onPressed: loading ? null : _create, child: Text(loading ? 'Creating…' : 'Create'))]),
    body: GroopXBackground(child:ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 30), children: [
      Center(child:Container(width:82,height:82,decoration:BoxDecoration(color:const Color(0xFFEEE9FF),borderRadius:BorderRadius.circular(27)),child:const Icon(Icons.groups_rounded,color:authPurple,size:42))),
      const SizedBox(height: 10), const Center(child: Text('New GroopX group', style: TextStyle(color: authInk,fontSize:19,fontWeight:FontWeight.w800))),
      const SizedBox(height: 4), const Center(child: Text('Group icon members ke initials se automatically banega.', style: TextStyle(fontSize: 11, color: authMuted))),
      const SizedBox(height: 18),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _label('Group Name'), TextField(controller: name, maxLength: 50, decoration: _input('Enter group name').copyWith(prefixIcon:const Icon(Icons.group_outlined))),
      _label('Group Description (Optional)'), TextField(controller: description, maxLength: 200, maxLines: 2, decoration: _input('Add a description for your group').copyWith(prefixIcon:const Icon(Icons.notes_outlined),alignLabelWithHint:true)),
      _label('Privacy'),
      _PrivacyTile(title: 'Private Group', subtitle: 'Only invited members can join and see the group.', icon: Icons.lock, selected: private, onTap: () => setState(() => private = true)),
      const SizedBox(height: 6),
      _PrivacyTile(title: 'Public Group', subtitle: 'Anyone can find the group and join.', icon: Icons.public, selected: !private, onTap: () => setState(() => private = false)),
      ]))),
      const SizedBox(height: 14),
      Row(children: [const Text('Add Members', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)), const Spacer(), Text('${selected.length} Selected', style: const TextStyle(fontSize: 11, color: authPurple))]),
      const SizedBox(height: 8),
      TextField(onChanged: _search, decoration: _input('Search by name, username or phone').copyWith(prefixIcon: const Icon(Icons.search))),
      if(searching)const LinearProgressIndicator(minHeight:2),
      if(searchError!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(searchError!,textAlign:TextAlign.center,style:const TextStyle(color:Colors.red))),
      if (members.isEmpty&&!searching&&searchError==null) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: Text('Search for GroopX members', style: TextStyle(color: authMuted)))),
      ...List.generate(members.length, (i) {
        final member = members[i];
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          secondary: GroopXAvatar(label:member.name),
          title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(member.username.isEmpty ? member.phone : '@${member.username}'),
          value: selected.contains(member.id),
          activeColor: authPurple,
          onChanged: (_) => setState(() => selected.contains(member.id) ? selected.remove(member.id) : selected.add(member.id)),
        );
      }),
    ])),
  );

  InputDecoration _input(String hint) => InputDecoration(hintText: hint, counterStyle: const TextStyle(fontSize: 10), enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFDDE0E8)), borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: authPurple), borderRadius: BorderRadius.circular(8)));
  Widget _label(String value) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 7), child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: authInk)));
  void _search(String value) {
    debounce?.cancel();
    final query=value.trim();
    if(query.length<2){setState((){members=const[];searching=false;searchError=null;});return;}
    debounce = Timer(const Duration(milliseconds: 350), () async {
      if(mounted)setState((){searching=true;searchError=null;});
      try {
        final results = await SocialApi.instance.searchUsers(query);
        if (mounted) setState(() => members = results);
      } catch (_) {
        if (mounted) setState(() {members = const [];searchError='Members search nahi hue. Retry karein.';});
      }finally{if(mounted)setState(()=>searching=false);}
    });
  }

  Future<void> _create() async {
    if (name.text.trim().isEmpty || selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a group name and select at least one member'))); return;
    }
    setState(() => loading = true);
    try {
      final id = await SocialApi.instance.createGroup(name: name.text.trim(), description: description.text.trim(), privacy: private ? 'private' : 'public', memberIds: selected.toList());
      if (mounted) context.go('/groups/$id');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group could not be created')));
    } finally { if (mounted) setState(() => loading = false); }
  }
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile({required this.title, required this.subtitle, required this.icon, required this.selected, required this.onTap});
  final String title, subtitle; final IconData icon; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: selected ? authPurple : const Color(0xFFE0E2E9)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? authPurple : authMuted), const SizedBox(width: 12), CircleAvatar(backgroundColor: const Color(0xFFF2EDFF), child: Icon(icon, color: authPurple)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), Text(subtitle, style: const TextStyle(fontSize: 10, color: authMuted))]))])));
}
