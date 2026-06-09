class LamportClock {
  int _counter;

  LamportClock([this._counter = 0]);

  int get value => _counter;

  /// Increment the clock before sending a message.
  int tick() {
    _counter++;
    return _counter;
  }

  /// Update the clock upon receiving a message with a remote timestamp.
  /// L(e) = max(local_clock, remote_clock) + 1
  void update(int remoteValue) {
    _counter = (_counter > remoteValue ? _counter : remoteValue) + 1;
  }

  @override
  String toString() => 'LamportClock($_counter)';
}
