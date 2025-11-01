import 'package:flutter/material.dart';

import 'main.dart' show WalletController;
import 'network_config.dart';
import 'wallet_connect_pair_page.dart';
import 'wallet_connect_service.dart';
import 'wc_request_approval_page.dart';

class WalletConnectPage extends StatefulWidget {
  const WalletConnectPage({
    required this.walletController,
    super.key,
  });

  final WalletController walletController;

  @override
  State<WalletConnectPage> createState() => _WalletConnectPageState();
}

class _WalletConnectPageState extends State<WalletConnectPage> {
  late final WalletConnectService service;
  bool _isReviewRouteActive = false;
  int? _lastOpenedRequestId;

  @override
  void initState() {
    super.initState();
    service = WalletConnectService(walletApi: widget.walletController)
      ..addListener(_handleServiceUpdate);
    service.init();
  }

  @override
  void dispose() {
    service.removeListener(_handleServiceUpdate);
    service.dispose();
    super.dispose();
  }

  void _handleServiceUpdate() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _maybeOpenReview();
  }

  void _maybeOpenReview() {
    final pending = service.pendingRequest;
    if (pending != null && !_isReviewRouteActive) {
      if (_lastOpenedRequestId == pending.requestId) {
        return;
      }
      _lastOpenedRequestId = pending.requestId;
      _isReviewRouteActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _openReviewRoute();
      });
    } else if (pending == null && !_isReviewRouteActive) {
      _lastOpenedRequestId = null;
    }
  }

  void _openReviewRoute() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WcRequestApprovalPage(
          service: service,
        ),
      ),
    ).whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _isReviewRouteActive = false;
        if (service.pendingRequest == null) {
          _lastOpenedRequestId = null;
        }
      });
    });
  }

  void _openPairScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalletConnectPairPage(service: service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = service.primarySessionInfo;
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
    final peer = service.currentPeerMetadata;
    final chains = service.getApprovedChains();
    final methods = service.getApprovedMethods();
    final activity = service.lastActivityEntry;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConnectedDappSection(context, peer, session),
        const SizedBox(height: 16),
        _buildPermissionsSection(context, chains, methods),
        const SizedBox(height: 16),
        _buildActivitySection(context, activity),
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
    final statusLabel = activity.success ? 'Success' : 'Error';
    final statusColor =
        activity.success ? theme.colorScheme.primary : theme.colorScheme.error;

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
