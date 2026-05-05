import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? conversationId;
  const ChatScreen({super.key, this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _api = ApiClient();

  List<Map<String, String>> _messages = [];
  bool _loading = false;
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (_conversationId != null) _loadConversation();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    try {
      final res = await _api.get('/ai/conversations/$_conversationId');
      final msgs =
          List<Map<String, dynamic>>.from(res.data['data']['messages']);
      setState(() {
        _messages = msgs
            .map((m) => {
                  'role': m['role'] as String,
                  'content': m['content'] as String
                })
            .toList();
      });
      _scrollToBottom();
    } catch (_) {}
  }

  Future<void> _send() async {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': msg});
      _loading = true;
    });
    _scrollToBottom();

    try {
      final res = await _api.post('/ai/chat',
          data: {'message': msg, 'conversationId': _conversationId});
      final data = res.data['data'];
      setState(() {
        _conversationId = data['conversationId'];
        _messages
            .add({'role': 'assistant', 'content': data['message']['content']});
      });
    } catch (e) {
      setState(() => _messages
          .add({'role': 'assistant', 'content': '❌ Có lỗi xảy ra: $e'}));
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Chat'), actions: [
        IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              setState(() {
                _messages = [];
                _conversationId = null;
              });
            }),
      ]),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.auto_awesome,
                          size: 56, color: AppTheme.primary),
                      SizedBox(height: 12),
                      Text('Bắt đầu cuộc trò chuyện',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Gõ tin nhắn bên dưới',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13)),
                    ]))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_loading && i == _messages.length) {
                      return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)));
                    }
                    final msg = _messages[i];
                    final isUser = msg['role'] == 'user';
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(ctx).size.width * 0.75),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUser
                              ? AppTheme.primary
                              : AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isUser ? 18 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 18),
                          ),
                          border: isUser
                              ? null
                              : Border.all(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(msg['content']!,
                            style: const TextStyle(fontSize: 14, height: 1.6)),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: AppTheme.bgPaper,
              border: Border(
                  top: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.15)))),
          child: Row(children: [
            Expanded(
                child: TextField(
              controller: _ctrl,
              maxLines: null,
              decoration: const InputDecoration(
                  hintText: 'Nhập tin nhắn...',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                        colors: [AppTheme.primary, Color(0xFF5B21B6)])),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
