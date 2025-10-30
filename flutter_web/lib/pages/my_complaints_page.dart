import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});
  @override State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

class _MyComplaintsPageState extends State<MyComplaintsPage> {
  List<dynamic> items = []; bool busy=false;

  Future<void> load() async {
    setState(()=>busy=true);
    items = await widget.api.myComplaints();
    setState(()=>busy=false);
  }

  @override void initState(){ super.initState(); load(); }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (busy) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return Center(child: Text(t.none_complaints));
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i){
        final c = items[i] as Map<String,dynamic>;
        final status = c['status']?.toString() ?? '';
        return ListTile(
          title: Text('${c['ticket']} – ${c['data']['article']}'),
          subtitle: Text(t.status(status)),
        );
      },
    );
  }
}
