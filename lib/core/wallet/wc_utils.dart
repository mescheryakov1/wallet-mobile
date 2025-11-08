String? sessionTopic(dynamic e) {
  try {
    return (e as dynamic).session.topic as String;
  } catch (_) {}
  try {
    return (e as dynamic).topic as String;
  } catch (_) {}
  return null;
}
