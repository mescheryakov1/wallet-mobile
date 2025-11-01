import 'package:flutter/material.dart';

import 'network_config.dart';
import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_pair_page.dart';
import 'wc_request_approval_page.dart';

class WalletConnectPage extends StatefulWidget {
  const WalletConnectPage({super.key});

  @override
  State<WalletConnectPage> createState() => _WalletConnectPageState();
}

class _WalletConnectPageState extends State<WalletConnectPage> {
  late final WalletConnectManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = WalletConnectManager.instance;
    _manager.addListener(_handleManagerUpdate);
  }

  @override
  void dispose() {
    _manager.removeListener(_handleManagerUpdate);
    super.dispose();
  }

  void _handleManagerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openPairScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalletConnectPairPage(service: _manager.service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _manager.service.primarySessionInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalletConnect v2'),
      ),
      body: session == null
          ? _buildDisconnectedBody(context)
          : _buildConnectedBody(context, session),
    );
  }

  Widget _buildDisconnectedBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No active dApp connection',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _openPairScreen,
              child: const Text('Connect via WalletConnect URI'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedBody(BuildContext context, WalletSessionInfo session) {
    final service = _manager.service;
    final peer = service.currentPeerMetadata;
    final chains = service.getApprovedChains();
    final methods = service.getApprovedMethods();
    final activity = service.lastActivityEntry;
    final WalletConnectRequestLogEntry? pendingLog =
        _manager.firstPendingLog;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConnectedDappSection(context, peer, session),
        const SizedBox(height: 16),
        _buildPermissionsSection(context, chains, methods),
        const SizedBox(height: 16),
        _buildActivitySection(context, activity),
        if (pendingLog != null &&
            pendingLog.status == WalletConnectRequestStatus.pending) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WcRequestApprovalPage(
                      requestId: pendingLog.request.requestId,
                      manager: _manager,
                    ),
                    fullscreenDialog: true,
                  ),
                );
              },
              child: const Text('Review pending request'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              await service.disconnectSession(session.topic);
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
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedDappSection(
    BuildContext context,
    WalletConnectPeerMetadata? peer,
    WalletSessionInfo session,
  ) {
    final name = (peer?.name ?? session.dappName).isNotEmpty
        ? (peer?.name ?? session.dappName)
        : 'Connected dApp';
    final description = peer?.description;
    final url = peer?.url ?? session.dappUrl;
    final iconUrl = peer?.iconUrl ?? session.iconUrl;

    return _buildSectionCard(
      context,
      'Connected dApp',
      [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDappAvatar(iconUrl, name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                  if (url != null && url.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      url,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPermissionsSection(
    BuildContext context,
    List<String> chains,
    List<String> methods,
  ) {
    final theme = Theme.of(context);
    final chainWidgets = chains.isNotEmpty
        ? chains
            .map(
              (chain) => Text(
                '• ${_formatChainLabel(chain)}',
                style: theme.textTheme.bodyMedium,
              ),
            )
            .toList()
        : <Widget>[
            Text(
              '• No chains approved',
              style: theme.textTheme.bodyMedium,
            ),
          ];

    final methodWidgets = methods.isNotEmpty
        ? methods
            .map(
              (method) => Text(
                '• $method',
                style: theme.textTheme.bodyMedium,
              ),
            )
            .toList()
        : <Widget>[
            Text(
              '• No methods approved',
              style: theme.textTheme.bodyMedium,
            ),
          ];

    return _buildSectionCard(
      context,
      'Session permissions',
      [
        Text(
          'Chains',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...chainWidgets,
        const SizedBox(height: 12),
        Text(
          'Methods',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...methodWidgets,
      ],
    );
  }

  Widget _buildActivitySection(
    BuildContext context,
    WalletConnectActivityEntry? activity,
  ) {
    if (activity == null) {
      return _buildSectionCard(
        context,
        'Activity',
        const <Widget>[
          Text('No recent activity'),
        ],
      );
    }

    final theme = Theme.of(context);
    late final String statusLabel;
    late final Color statusColor;
    switch (activity.status) {
      case WalletConnectRequestStatus.approved:
        statusLabel = 'Success';
        statusColor = theme.colorScheme.primary;
        break;
      case WalletConnectRequestStatus.rejected:
        statusLabel = 'Error';
        statusColor = theme.colorScheme.error;
        break;
      case WalletConnectRequestStatus.pending:
        statusLabel = 'Pending';
        statusColor = theme.colorScheme.tertiary;
        break;
    }

    return _buildSectionCard(
      context,
      'Activity',
      [
        Text('Last request: ${activity.method}'),
        if (activity.chainId != null) ...[
          const SizedBox(height: 8),
          Text('Chain: ${activity.chainId}'),
        ],
        const SizedBox(height: 8),
        Text(
          'Result: $statusLabel',
          style: theme.textTheme.bodyMedium?.copyWith(color: statusColor),
        ),
        if (activity.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(activity.summary),
        ],
        const SizedBox(height: 8),
        Text(
          'Updated: ${activity.timestamp.toLocal()}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildDappAvatar(String? iconUrl, String name) {
    final displayName = name.trim();
    final initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';

    if (iconUrl == null || iconUrl.isEmpty) {
      return CircleAvatar(
        radius: 28,
        child: Text(initial),
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: Image.network(
          iconUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(child: Text(initial)),
        ),
      ),
    );
  }

  String _formatChainLabel(String chain) {
    final config = findNetworkByCaip2(chain);
    if (config != null) {
      return '${config.name} (${config.chainIdCaip2})';
    }
    return chain;
  }
}
