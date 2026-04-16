import 'package:flutter/material.dart';
import 'core/theme/lse_theme.dart';
import 'features/send/presentation/send_page.dart';
import 'features/receive/presentation/receive_page.dart';
import 'shared/services/log_service.dart';
import 'shared/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志
  await LogService.instance.init();

  // 初始化通知
  await NotificationService.instance.init();

  runApp(const LseApp());
}

class LseApp extends StatelessWidget {
  const LseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalSend 企业版',
      debugShowCheckedModeBanner: false,
      theme: LseTheme.lightTheme,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    SendPage(),
    ReceivePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.upload_outlined),
            selectedIcon: Icon(Icons.upload),
            label: '发送',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '接收',
          ),
        ],
      ),
    );
  }
}
