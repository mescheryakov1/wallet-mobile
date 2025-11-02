import 'package:flutter/material.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_service.dart';

class WalletConnectPairPage extends StatefulWidget {
  const WalletConnectPairPage({super.key});

  @override
  State<WalletConnectPairPage> createState() => _WalletConnectPairPageState();
}

class _WalletConnectPairPageState extends State<WalletConnectPairPage> {
  late final TextEditingController _uriController;
  final WalletConnectManager _manager = WalletConnectManager.instance;
  WalletConnectService get _service => _manager.service;

  @override
  void initState() {
    super.initState();
    _uriController = TextEditingController();
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final uri = _uriController.text.trim();
    if (uri.isEmpty || _service.pairingInProgress) {
      return;
    }

    try {
      await _service.startPairing(uri);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pair: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        <Listenable>[
          _service,
          _manager,
          _manager.requestQueue,
        ],
      ),
      builder: (BuildContext context, Widget? _) {
        final bool isPairing = _service.pairingInProgress;
        final String? error = _service.pairingError;
        final WalletSessionInfo? session = _service.primarySessionInfo;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Connect via URI'),
          ),
          body: session != null
              ? _buildConnectedBody(context, session)
              : _buildConnectForm(isPairing: isPairing, error: error),
        );
      },
    );
  }

  Widget _buildConnectForm({
    required bool isPairing,
    required String? error,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste the WalletConnect URI provided by the dApp.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _uriController,
            decoration: const InputDecoration(
              labelText: 'wc:',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isPairing ? null : _pair,
              child: isPairing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ),
          if (isPairing) ...[
            const SizedBox(height: 16),
            Row(
              children: const <Widget>[
                SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Waiting for session proposal...'),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectedBody(
    BuildContext context,
    WalletSessionInfo session,
  ) {
    final WalletConnectPeerMetadata? peer = _service.currentPeerMetadata;
    final List<String> chains = _service.getApprovedChains();
    final List<String> methods = _service.getApprovedMethods();
    final String? displayUrl = peer?.url ?? session.dappUrl;
    final String? displayDescription = peer?.description ?? session.dappDescription;
    final List<Widget> subtitleChildren = <Widget>[];
    if (displayUrl != null && displayUrl.isNotEmpty) {
      subtitleChildren.add(Text(displayUrl));
    }
    if (displayDescription != null && displayDescription.isNotEmpty) {
      subtitleChildren.add(Text(displayDescription));
    }
    final Widget? subtitleWidget = subtitleChildren.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: subtitleChildren,
          );
    final List<Widget> chainWidgets = chains.isEmpty
        ? const <Widget>[Text('No chains approved')]
        : chains.map((chain) => Text(chain)).toList();
    final List<Widget> methodWidgets = methods.isEmpty
        ? const <Widget>[Text('No methods approved')]
        : methods.map((method) => Text(method)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          context,
          'Connected dApp',
          [
            ListTile(
              leading: _buildPeerAvatar(peer),
              title: Text(peer?.name ?? session.dappName),
              subtitle: subtitleWidget,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          context,
          'Session permissions',
          [
            const Text(
              'Chains',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...chainWidgets,
            const SizedBox(height: 16),
            const Text(
              'Methods',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...methodWidgets,
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              await _service.disconnectSession(session.topic);
            },
            child: const Text('Disconnect'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPeerAvatar(WalletConnectPeerMetadata? peer) {
    final iconUrl = peer?.icons.isNotEmpty == true ? peer!.icons.first : null;
    if (iconUrl == null || iconUrl.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.link));
    }
    return CircleAvatar(
      backgroundImage: NetworkImage(iconUrl),
    );
  }
}
