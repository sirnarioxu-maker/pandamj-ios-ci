import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const gold = Color(0xFFE4C27A);
const background = Color(0xFF0E1412);
const panel = Color(0xFF171E1B);
const line = Color(0xFF2C3832);
const good = Color(0xFF8ED9A8);
const bad = Color(0xFFF0A394);
const bundledAdminUsername = String.fromEnvironment('PANDAMJ_ADMIN_USER');
const bundledAdminPassword = String.fromEnvironment('PANDAMJ_ADMIN_PASSWORD');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PandaAdminApp());
}

class BackendConfig {
  const BackendConfig(this.name, this.baseUrl);
  final String name;
  final String baseUrl;
}

const backends = <BackendConfig>[
  BackendConfig('老后台', 'http://74.82.221.117:8787'),
  BackendConfig('新后台', 'http://102.134.34.160:8787'),
];

class SavedLogin {
  const SavedLogin({
    required this.username,
    required this.password,
    required this.backendIndex,
  });
  final String username;
  final String password;
  final int backendIndex;

  SavedLogin copyWith({
    String? username,
    String? password,
    int? backendIndex,
  }) => SavedLogin(
    username: username ?? this.username,
    password: password ?? this.password,
    backendIndex: backendIndex ?? this.backendIndex,
  );
}

class LoginStore {
  static const int _credentialRevision = 1;

  static Future<SavedLogin> load() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getInt('credential_revision') ?? 0) < _credentialRevision) {
      const migrated = SavedLogin(
        username: bundledAdminUsername,
        password: bundledAdminPassword,
        backendIndex: 1,
      );
      await save(migrated);
      return migrated;
    }

    return SavedLogin(
      username: prefs.getString('admin_username') ?? bundledAdminUsername,
      password: prefs.getString('admin_password') ?? bundledAdminPassword,
      backendIndex: (prefs.getInt('backend_index') ?? 1).clamp(
        0,
        backends.length - 1,
      ),
    );
  }

  static Future<void> save(SavedLogin value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('admin_username', value.username),
      prefs.setString('admin_password', value.password),
      prefs.setInt('backend_index', value.backendIndex),
      prefs.setInt('credential_revision', _credentialRevision),
    ]);
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class AdminApi {
  AdminApi(this.backend);
  final BackendConfig backend;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  String _cookie = '';

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('${backend.baseUrl}$path'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    if (_cookie.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, _cookie);
    }
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final setCookie = response.headers.value(HttpHeaders.setCookieHeader);
    if (setCookie != null && setCookie.isNotEmpty) {
      _cookie = setCookie.split(';').first;
    }
    final text = await utf8.decoder.bind(response).join();
    Map<String, dynamic> json = <String, dynamic>{};
    if (text.trim().isNotEmpty) {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) json = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        (json['error'] ?? '请求失败 ${response.statusCode}').toString(),
        statusCode: response.statusCode,
      );
    }
    return json;
  }

  Future<void> login(String username, String password, String code) async {
    await _request(
      '/admin/login',
      method: 'POST',
      body: {'username': username, 'password': password, 'code': code},
    );
  }

  Future<void> logout() async {
    try {
      await _request('/admin/logout', method: 'POST', body: {});
    } finally {
      _cookie = '';
    }
  }

  Future<DashboardData> loadDashboard() async {
    final values = await Future.wait([
      _request('/admin/api/totals'),
      _request('/admin/api/issued'),
      _request('/admin/api/requests'),
      _request('/admin/api/pools?limit=80'),
      _request('/admin/api/results?limit=80'),
      _request('/admin/api/pool-members'),
      _request('/admin/api/scan'),
    ]);
    return DashboardData(
      totals: values[0],
      issued: itemsOf(values[1]),
      requests: itemsOf(values[2]),
      pools: itemsOf(values[3]),
      results: itemsOf(values[4]),
      poolMembers: itemsOf(values[5]),
      scan: values[6],
    );
  }

  Future<void> issue({
    required String uid,
    String note = '',
    bool? enabled,
    bool noteOnly = false,
  }) async {
    await _request(
      '/admin/api/issued',
      method: 'POST',
      body: {
        'uid': uid,
        'note': note,
        'enabled': ?enabled,
        if (noteOnly) 'noteOnly': true,
      },
    );
  }

  Future<void> clearScores(String uid, String password) => _request(
    '/admin/api/scores/clear',
    method: 'POST',
    body: {'uid': uid, 'password': password},
  );

  Future<void> updatePoolMember(String uid, {bool delete = false}) => _request(
    '/admin/api/pool-members',
    method: 'POST',
    body: {'uid': uid, if (delete) 'delete': true},
  );

  Future<Map<String, dynamic>> poolDetail(String id) =>
      _request('/admin/api/pools/${Uri.encodeComponent(id)}');
  void close() => _client.close(force: true);
}

List<Map<String, dynamic>> itemsOf(Map<String, dynamic> value) {
  final raw = value['items'];
  if (raw is! List) return [];
  return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

class DashboardData {
  const DashboardData({
    required this.totals,
    required this.issued,
    required this.requests,
    required this.pools,
    required this.results,
    required this.poolMembers,
    required this.scan,
  });
  final Map<String, dynamic> totals;
  final List<Map<String, dynamic>> issued;
  final List<Map<String, dynamic>> requests;
  final List<Map<String, dynamic>> pools;
  final List<Map<String, dynamic>> results;
  final List<Map<String, dynamic>> poolMembers;
  final Map<String, dynamic> scan;
}

class PandaAdminApp extends StatefulWidget {
  const PandaAdminApp({super.key, this.autoLogin = true});
  final bool autoLogin;
  @override
  State<PandaAdminApp> createState() => _PandaAdminAppState();
}

class _PandaAdminAppState extends State<PandaAdminApp> {
  SavedLogin? saved;
  AdminApi? api;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    var login = await LoginStore.load();
    login = login.copyWith(backendIndex: 1);
    await LoginStore.save(login);
    if (!widget.autoLogin) {
      if (mounted) setState(() => saved = login);
      return;
    }

    final client = AdminApi(backends[login.backendIndex]);
    try {
      await client.login('', '', '000000');
      if (!mounted) {
        client.close();
        return;
      }
      setState(() {
        saved = login;
        api = client;
      });
    } catch (_) {
      client.close();
      if (mounted) setState(() => saved = login);
    }
  }

  @override
  void dispose() {
    api?.close();
    super.dispose();
  }

  void loggedIn(AdminApi value, SavedLogin login) {
    api?.close();
    LoginStore.save(login);
    setState(() {
      api = value;
      saved = login;
    });
  }

  void loggedOut([SavedLogin? replacement]) {
    api?.close();
    setState(() {
      api = null;
      if (replacement != null) saved = replacement;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '熊猫麻将后台',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: gold,
        brightness: Brightness.dark,
        primary: gold,
        surface: panel,
        error: bad,
      ),
      useMaterial3: true,
      cardTheme: const CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF0D1210),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF111815),
        indicatorColor: gold,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
      ),
    ),
    home: saved == null
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : api == null
        ? LoginPage(saved: saved!, onLoggedIn: loggedIn)
        : DashboardPage(api: api!, saved: saved!, onLoggedOut: loggedOut),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.saved, required this.onLoggedIn});
  final SavedLogin saved;
  final void Function(AdminApi api, SavedLogin saved) onLoggedIn;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late SavedLogin saved;
  final code = TextEditingController();
  final focus = FocusNode();
  bool loading = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    saved = widget.saved;
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  void dispose() {
    code.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final value = code.text.trim();
    if (loading || value.length != 6) return;
    setState(() {
      loading = true;
      error = '';
    });
    final api = AdminApi(backends[saved.backendIndex]);
    try {
      await api.login(saved.username, saved.password, value);
      if (mounted) widget.onLoggedIn(api, saved);
    } catch (e) {
      api.close();
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
        code.clear();
      });
      focus.requestFocus();
    }
  }

  Future<void> editCredentials() async {
    final user = TextEditingController(text: saved.username);
    final password = TextEditingController(text: saved.password);
    final result = await showDialog<SavedLogin>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改记住的账号密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: user,
              decoration: const InputDecoration(labelText: '账号'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              saved.copyWith(
                username: user.text.trim(),
                password: password.text,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    user.dispose();
    password.dispose();
    if (result != null) {
      await LoginStore.save(result);
      if (mounted) setState(() => saved = result);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CircleAvatar(
                      radius: 31,
                      backgroundColor: gold,
                      child: Icon(
                        Icons.pets_rounded,
                        size: 36,
                        color: Color(0xFF241B0C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '熊猫麻将后台',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '账号和密码已记住，只需输入谷歌验证码',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 22),
                    SegmentedButton<int>(
                      segments: List.generate(
                        backends.length,
                        (i) => ButtonSegment(
                          value: i,
                          label: Text(backends[i].name),
                        ),
                      ),
                      selected: {saved.backendIndex},
                      onSelectionChanged: (value) async {
                        final next = saved.copyWith(backendIndex: value.first);
                        await LoginStore.save(next);
                        if (mounted) setState(() => saved = next);
                      },
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: code,
                      focusNode: focus,
                      enabled: !loading,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        letterSpacing: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: '谷歌验证码',
                        hintText: '000000',
                        counterText: '',
                        prefixIcon: Icon(Icons.security_rounded),
                      ),
                      onChanged: (value) {
                        if (value.length == 6) submit();
                      },
                      onSubmitted: (_) => submit(),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        error,
                        style: const TextStyle(color: bad),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: loading ? null : submit,
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(loading ? '登录中' : '登录'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: loading ? null : editCredentials,
                      icon: const Icon(Icons.key_rounded, size: 18),
                      label: Text('${saved.username} · 已记住账号密码'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.api,
    required this.saved,
    required this.onLoggedOut,
  });
  final AdminApi api;
  final SavedLogin saved;
  final void Function([SavedLogin? replacement]) onLoggedOut;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardData? data;
  Timer? timer;
  bool loading = true;
  bool refreshing = false;
  int tab = 0;
  String error = '';

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => refresh(silent: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    if (refreshing) return;
    refreshing = true;
    if (!silent && mounted) setState(() => loading = data == null);
    try {
      final value = await widget.api.loadDashboard();
      if (mounted) {
        setState(() {
          data = value;
          error = '';
          loading = false;
        });
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        widget.onLoggedOut();
        return;
      }
      if (mounted && !silent) {
        setState(() {
          error = e.message;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> mutate(
    Future<void> Function() action, {
    String success = '已保存',
  }) async {
    try {
      await action();
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> switchBackend(int index) async {
    if (index == widget.saved.backendIndex) return;
    final next = widget.saved.copyWith(backendIndex: index);
    await LoginStore.save(next);
    await widget.api.logout();
    widget.onLoggedOut(next);
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['会员输赢', '每局明细', '发卡', '会员池', '牌序'];
    final current = data;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('熊猫麻将后台', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              '${backends[widget.saved.backendIndex].name} · ${titles[tab]}',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: '切换后台',
            icon: const Icon(Icons.swap_horiz_rounded),
            onSelected: switchBackend,
            itemBuilder: (_) => List.generate(
              backends.length,
              (i) => PopupMenuItem(value: i, child: Text(backends[i].name)),
            ),
          ),
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
          IconButton(
            onPressed: () async {
              await widget.api.logout();
              widget.onLoggedOut();
            },
            icon: const Icon(Icons.logout_rounded),
            tooltip: '退出',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty && current == null
          ? ErrorView(message: error, retry: refresh)
          : current == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: refresh,
              child: IndexedStack(
                index: tab,
                children: [
                  MembersView(
                    data: current,
                    onClear: confirmClear,
                    onEditNote: editNote,
                  ),
                  ResultsView(items: current.results),
                  CardsView(
                    issued: current.issued,
                    requests: current.requests,
                    onIssue: (uid, note) => mutate(
                      () => widget.api.issue(uid: uid, note: note),
                      success: '发卡成功',
                    ),
                    onToggle: (uid, enabled) => mutate(
                      () => widget.api.issue(uid: uid, enabled: enabled),
                      success: enabled ? '已恢复' : '已停用',
                    ),
                    onEditNote: editNote,
                  ),
                  PoolMembersView(
                    scan: current.scan,
                    items: current.poolMembers,
                    onAdd: (uid) => mutate(
                      () => widget.api.updatePoolMember(uid),
                      success: '已加入会员池',
                    ),
                    onDelete: (uid) => mutate(
                      () => widget.api.updatePoolMember(uid, delete: true),
                      success: '已从会员池删除',
                    ),
                  ),
                  PoolsView(
                    items: current.pools,
                    loadDetail: widget.api.poolDetail,
                  ),
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: '会员',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '明细',
          ),
          NavigationDestination(
            icon: Icon(Icons.card_membership_outlined),
            selectedIcon: Icon(Icons.card_membership),
            label: '发卡',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_search_outlined),
            selectedIcon: Icon(Icons.manage_search),
            label: '会员池',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_module_outlined),
            selectedIcon: Icon(Icons.view_module),
            label: '牌序',
          ),
        ],
      ),
    );
  }

  Future<void> confirmClear(String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理输赢'),
        content: Text('会员 $uid 的输赢将从零重新统计。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await mutate(
        () => widget.api.clearScores(uid, widget.saved.password),
        success: '输赢已清理',
      );
    }
  }

  Future<void> editNote(Map<String, dynamic> item) async {
    final controller = TextEditingController(
      text: (item['note'] ?? '').toString(),
    );
    final uid = (item['uid'] ?? '').toString();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改备注 · $uid'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      await mutate(
        () => widget.api.issue(uid: uid, note: value, noteOnly: true),
        success: '备注已更新',
      );
    }
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 52, color: bad),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}

class MembersView extends StatefulWidget {
  const MembersView({
    super.key,
    required this.data,
    required this.onClear,
    required this.onEditNote,
  });
  final DashboardData data;
  final ValueChanged<String> onClear;
  final ValueChanged<Map<String, dynamic>> onEditNote;
  @override
  State<MembersView> createState() => _MembersViewState();
}

class _MembersViewState extends State<MembersView> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final summary =
        (widget.data.totals['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final all = itemsOf(widget.data.totals);
    final items = all
        .where((item) => '${item['uid']} ${item['note'] ?? ''}'.contains(query))
        .toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SummaryCard(label: '已发卡', value: fmtInt(summary['issued'])),
            SummaryCard(label: '有记录会员', value: fmtInt(summary['members'])),
            SummaryCard(label: '已回传局数', value: fmtInt(summary['rounds'])),
            SummaryCard(
              label: '全部净输赢',
              value: money(summary['total']),
              tone: tone(summary['total']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索会员号或备注',
          ),
          onChanged: (value) => setState(() => query = value.trim()),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const EmptyCard('还没有会员记录')
        else
          ...items.map(
            (item) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['uid'] ?? '—'}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        StatusChip(
                          ok: item['enabled'] == true,
                          yes: '永久有效',
                          no: '未发卡',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '备注：${item['note'] ?? '—'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        Text('局数 ${fmtInt(item['rounds'])}'),
                        Text(
                          '胜/负 ${fmtInt(item['wins'])} / ${fmtInt(item['losses'])}',
                        ),
                        Text(
                          '总输赢 ${money(item['total'])}',
                          style: TextStyle(
                            color: tone(item['total']),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '最近 ${when(item['last_at'])}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => widget.onEditNote(item),
                          icon: const Icon(Icons.edit_note),
                          label: const Text('备注'),
                        ),
                        TextButton.icon(
                          onPressed: () => widget.onClear('${item['uid']}'),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('清理输赢'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
    children: items.isEmpty
        ? const [EmptyCard('还没有单局记录')]
        : items
              .map(
                (item) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text('${item['round'] ?? '—'}'),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text('会员 ${item['uid'] ?? '—'}')),
                        Text(
                          money(item['my_score']),
                          style: TextStyle(
                            color: tone(item['my_score']),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '桌 ${item['desk'] ?? '—'} · ${when(item['settled_at'] ?? item['created_at'])}\n四家 ${(item['scores'] is List ? item['scores'] as List : const []).map(money).join(' / ')}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              )
              .toList(),
  );
}

class CardsView extends StatefulWidget {
  const CardsView({
    super.key,
    required this.issued,
    required this.requests,
    required this.onIssue,
    required this.onToggle,
    required this.onEditNote,
  });
  final List<Map<String, dynamic>> issued;
  final List<Map<String, dynamic>> requests;
  final Future<void> Function(String uid, String note) onIssue;
  final Future<void> Function(String uid, bool enabled) onToggle;
  final ValueChanged<Map<String, dynamic>> onEditNote;
  @override
  State<CardsView> createState() => _CardsViewState();
}

class _CardsViewState extends State<CardsView> {
  final uid = TextEditingController();
  final note = TextEditingController();
  @override
  void dispose() {
    uid.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> issue() async {
    if (!RegExp(r'^\d+$').hasMatch(uid.text.trim())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入数字会员号')));
      return;
    }
    if (note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发卡必须填写备注')));
      return;
    }
    await widget.onIssue(uid.text.trim(), note.text.trim());
    uid.clear();
    note.clear();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = widget.requests
        .where((item) => item['allowed'] != true)
        .toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(
                  controller: uid,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '真实会员号'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '备注（必填）'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: issue,
                    icon: const Icon(Icons.card_membership),
                    label: const Text('发卡'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle('已发会员卡'),
        if (widget.issued.isEmpty)
          const EmptyCard('还没有发过卡')
        else
          ...widget.issued.map((item) {
            final enabled = item['enabled'] == true;
            return Card(
              child: ListTile(
                title: Text(
                  '${item['uid'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${item['note'] ?? '—'}\n最后心跳 ${when(item['last_heartbeat'])}',
                ),
                isThreeLine: true,
                leading: Icon(
                  enabled ? Icons.verified_rounded : Icons.pause_circle_rounded,
                  color: enabled ? good : bad,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'note') widget.onEditNote(item);
                    if (value == 'toggle') {
                      widget.onToggle('${item['uid']}', !enabled);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'note', child: Text('修改备注')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(enabled ? '停用' : '恢复'),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SectionTitle('待发卡请求'),
        if (waiting.isEmpty)
          const EmptyCard('没有待发卡的号')
        else
          ...waiting.map(
            (item) => Card(
              child: ListTile(
                title: Text('${item['uid'] ?? '—'}'),
                subtitle: Text(
                  '请求 ${fmtInt(item['hits'])} 次 · ${when(item['created_at'])}',
                ),
                trailing: FilledButton(
                  onPressed: () {
                    uid.text = '${item['uid'] ?? ''}';
                    note.clear();
                  },
                  child: const Text('填写发卡'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PoolMembersView extends StatefulWidget {
  const PoolMembersView({
    super.key,
    required this.scan,
    required this.items,
    required this.onAdd,
    required this.onDelete,
  });
  final Map<String, dynamic> scan;
  final List<Map<String, dynamic>> items;
  final Future<void> Function(String uid) onAdd;
  final Future<void> Function(String uid) onDelete;
  @override
  State<PoolMembersView> createState() => _PoolMembersViewState();
}

class _PoolMembersViewState extends State<PoolMembersView> {
  final uid = TextEditingController();
  @override
  void dispose() {
    uid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final done = num(scan['done']);
    final total = num(scan['total']);
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final running = scan['running'] == true;
    final logs = scan['logs'] is List
        ? (scan['logs'] as List).map((e) => '$e').toList()
        : <String>[];
    final metrics = <(String, String)>[
      ('当前号码', '${scan['current'] ?? '—'}'),
      ('本阶段范围', rangeText(scan['range'])),
      (
        '实时速度',
        '${num(scan['speed']).toStringAsFixed(1)}/秒 · ${fmtInt(scan['perMin'])}/分钟',
      ),
      ('本阶段预计剩余', durationText(scan['etaMin'])),
      ('全程预计剩余', durationText(scan['etaAllMin'])),
      ('全程待测', fmtInt(scan['plan'])),
      ('已跳过记录', fmtInt(scan['skipped'])),
      ('请求重试', fmtInt(scan['retries'])),
      ('失败待重扫', fmtInt(scan['failed'])),
      ('累计命中', fmtInt(scan['hits'])),
      ('本次新进池', fmtInt(scan['added'])),
      ('运行阶段', '${scan['stage'] ?? '—'}'),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: uid,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '撞出来的会员号'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                if (uid.text.trim().isEmpty) return;
                await widget.onAdd(uid.text.trim());
                uid.clear();
              },
              child: const Text('加入'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '撞号实时进度',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    StatusChip(
                      ok: running,
                      yes: '运行中',
                      no: scan['finished'] == true ? '已完成' : '未运行',
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${scan['stage'] ?? ''} ${running ? '正在扫描' : ''}，当前号码 ${scan['current'] ?? '—'}',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 13),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '本阶段 ${fmtInt(done)} / ${fmtInt(total)}（${(progress * 100).toStringAsFixed(2)}%）',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    Text(
                      '剩余 ${fmtInt(total - done)}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 700
                        ? (constraints.maxWidth - 24) / 4
                        : (constraints.maxWidth - 8) / 2;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: metrics
                          .map(
                            (item) => SizedBox(
                              width: width,
                              child: Metric(label: item.$1, value: item.$2),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    '实时运行日志（最近 80 条）',
                    style: TextStyle(color: gold, fontWeight: FontWeight.w800),
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 260),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B100E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(
                          logs.isEmpty ? '暂无运行日志' : logs.take(80).join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SectionTitle('会员池'),
        if (widget.items.isEmpty)
          const EmptyCard('会员池是空的')
        else
          ...widget.items.map(
            (item) => Card(
              child: ListTile(
                title: Text(
                  '${item['uid'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${item['source'] ?? '已有'} · ${item['statusHint'] ?? '—'}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: bad),
                  onPressed: () => widget.onDelete('${item['uid']}'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PoolsView extends StatelessWidget {
  const PoolsView({super.key, required this.items, required this.loadDetail});
  final List<Map<String, dynamic>> items;
  final Future<Map<String, dynamic>> Function(String id) loadDetail;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
    children: items.isEmpty
        ? const [EmptyCard('还没有存下牌序')]
        : items
              .map(
                (item) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.view_module_rounded, color: gold),
                    title: Text(
                      '会员 ${item['real_uid'] ?? '—'} · ${item['pool_count'] ?? 0} 张',
                    ),
                    subtitle: Text(
                      '桌 ${item['desk'] ?? '—'} / 局 ${item['round'] ?? '—'} · 换号 ${item['member_uid'] ?? '—'}\n${when(item['created_at'])}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      try {
                        final detail = await loadDetail('${item['id']}');
                        if (!context.mounted) return;
                        final cards = detail['pool'] is List
                            ? (detail['pool'] as List).join('  ')
                            : '没有牌';
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('牌序 ${detail['real_uid'] ?? ''}'),
                            content: SelectableText(cards),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
                  ),
                ),
              )
              .toList(),
  );
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    this.tone,
  });
  final String label;
  final String value;
  final Color? tone;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 36) / 2,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFF121916),
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.ok,
    required this.yes,
    required this.no,
  });
  final bool ok;
  final String yes;
  final String no;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: (ok ? good : bad).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 7, color: ok ? good : bad),
        const SizedBox(width: 5),
        Text(
          ok ? yes : no,
          style: TextStyle(
            color: ok ? good : bad,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w900),
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(text, style: const TextStyle(color: Colors.white54)),
      ),
    ),
  );
}

double num(dynamic value) => double.tryParse('$value') ?? 0;

String fmtInt(dynamic value) {
  final number = num(value).round();
  final text = number.abs().toString();
  final parts = <String>[];
  for (var end = text.length; end > 0; end -= 3) {
    parts.add(text.substring((end - 3).clamp(0, end), end));
  }
  return '${number < 0 ? '-' : ''}${parts.reversed.join(',')}';
}

String money(dynamic value) {
  final number = num(value);
  final text = number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(1);
  return number > 0 ? '+$text' : text;
}

Color tone(dynamic value) {
  final number = num(value);
  if (number > 0) return good;
  if (number < 0) return bad;
  return Colors.white;
}

String when(dynamic value) {
  final seconds = num(value).round();
  if (seconds <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.month}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

String durationText(dynamic minutes) {
  final total = num(minutes).round();
  if (total <= 0) return '—';
  final days = total ~/ 1440;
  final hours = (total % 1440) ~/ 60;
  final mins = total % 60;
  return [
    if (days > 0) '$days天',
    if (hours > 0) '$hours小时',
    if (days == 0 && mins > 0) '$mins分钟',
  ].join(' ');
}

String rangeText(dynamic value) {
  if (value is List && value.length >= 2) {
    return '${fmtInt(value[0])} – ${fmtInt(value[1])}';
  }
  return value?.toString() ?? '—';
}
