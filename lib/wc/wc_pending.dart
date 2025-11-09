typedef UriConsumer = Future<bool> Function(String uri);

class WcPendingBuffer {
  final List<String> _queue = <String>[];
  bool clientReady = false;
  bool appResumed = false;
  UriConsumer? _consumer;
  bool _draining = false;

  void bind(UriConsumer consumer) {
    _consumer = consumer;
    _drain();
  }

  void push(String uri) {
    _queue.add(uri);
    _drain();
  }

  void markClientReady() {
    clientReady = true;
    _drain();
  }

  void setAppResumed(bool resumed) {
    appResumed = resumed;
    _drain();
  }

  void notifyReady() {
    _drain();
  }

  Future<void> _drain() async {
    if (_draining) {
      return;
    }
    final UriConsumer? consumer = _consumer;
    if (consumer == null) {
      return;
    }
    if (!clientReady || !appResumed) {
      return;
    }

    _draining = true;
    try {
      while (_queue.isNotEmpty && clientReady && appResumed) {
        final String uri = _queue.removeAt(0);
        final bool accepted = await consumer(uri);
        if (!accepted) {
          _queue.insert(0, uri);
          break;
        }
      }
    } finally {
      _draining = false;
    }
  }
}
