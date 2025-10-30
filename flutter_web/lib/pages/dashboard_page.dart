import 'package:flutter/material.dart';
import '../api/client.dart';
import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import '../l10n/app_localizations.dart';

class DashboardPage extends StatefulWidget {
  final ApiClient api;
  const DashboardPage({super.key, required this.api});
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override void initState(){ super.initState(); _tab = TabController(length: 2, vsync: this); }
  @override void dispose(){ _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        const SizedBox(height: 8),
        TabBar(controller: _tab, tabs: [Tab(text:t.tab_complaint), Tab(text:t.tab_my_complaints)]),
        Expanded(child: TabBarView(controller: _tab, children: [
          ComplaintFormPage(api: widget.api),
          MyComplaintsPage(api: widget.api),
        ]))
      ],
    );
  }
}
