import 'dart:async';

import 'package:flutter/material.dart';

import '../api/roblox_api.dart';
import '../bootstrap_stub.dart'
    if (dart.library.io) '../bootstrap_io.dart';
import '../render/avatar_view.dart';
import '../render/glb_parser.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.api});

  final RobloxApi? api;

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _FetchState { idle, loading, ready, error }

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final RobloxApi _api = widget.api ?? RobloxApi();

  _FetchState _state = _FetchState.idle;
  String _status = 'Enter a Roblox username';
  AvatarModel? _model;
  String? _displayName;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _controller.text = 'builderman';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    final username = _controller.text.trim();
    if (username.isEmpty) {
      setState(() {
        _state = _FetchState.idle;
        _status = 'Enter a Roblox username';
      });
      return;
    }
    _focus.unfocus();
    final local = username.endsWith('.glb');
    setState(() {
      _state = _FetchState.loading;
      _model = null;
      _status = local ? 'Loading local model...' : 'Resolving $username...';
    });
    try {
      final AvatarModel model;
      String label;
      if (local) {
        final bytes = await readLocalFile(username) ??
            (throw AvatarFetchException('Could not read $username'));
        model = await GlbParser().parse(bytes);
        label = username.split('/').last;
        _userId = username.hashCode;
      } else {
        final result = await _api.fetchAvatar(
          username,
          onStatus: (s) {
            if (mounted) setState(() => _status = s);
          },
        );
        model = result.model;
        label = '${result.username} (#${result.userId})';
        _userId = result.userId;
      }
      if (!mounted) return;
      setState(() {
        _state = _FetchState.ready;
        _model = model;
        _displayName = username;
        _status = label;
      });
    } on AvatarFetchException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _FetchState.error;
        _status = e.message;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _state = _FetchState.error;
        _status = 'Request timed out. Check your connection or proxy.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _FetchState.error;
        _status = 'Failed to load avatar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _render(),
                      decoration: const InputDecoration(
                        hintText: 'Roblox username or /path/model.glb',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _state == _FetchState.loading ? null : _render,
                    child: const Text('Render'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_state) {
                _FetchState.ready when _model != null =>
                  AvatarView(key: ValueKey(_userId), model: _model!),
                _FetchState.loading => const Center(
                    child: CircularProgressIndicator(),
                  ),
                _ => Center(
                    child: Icon(
                      _state == _FetchState.error
                          ? Icons.error_outline
                          : Icons.person_outline,
                      size: 64,
                      color: const Color(0xFF3A3A4F),
                    ),
                  ),
              },
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _displayName != null && _state == _FetchState.ready
                    ? _status
                    : _status,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _state == _FetchState.error
                          ? const Color(0xFFFF7A7A)
                          : const Color(0xFF8A8AA0),
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
