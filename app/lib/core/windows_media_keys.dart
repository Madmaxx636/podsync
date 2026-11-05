import 'dart:ffi';
import 'dart:io';

/// Windows: sees the media keys (Play/Pause, Next, Previous, Stop) system-wide, which is what a
/// headphone button or keyboard media key turns into. A low-level keyboard hook, because the
/// system's media-session routing hands the keys to whichever app it prefers, which is often a
/// browser. [handle] returns true when PodSync used the key (it is then not passed on).
class WindowsMediaKeys {
  WindowsMediaKeys(this.handle);

  /// 'playpause', 'next', 'previous' or 'stop'. Return true to swallow the key.
  final bool Function(String command) handle;

  Pointer<Void>? _hook;
  NativeCallable<_HookProc>? _callback;

  bool get active => _hook != null && _hook!.address != 0;

  static const _hcAction = 0;
  static const _wmKeyDown = 0x0100;
  static const _wmSysKeyDown = 0x0104;
  static const _whKeyboardLl = 13;

  static const _vkMediaNext = 0xB0;
  static const _vkMediaPrev = 0xB1;
  static const _vkMediaStop = 0xB2;
  static const _vkMediaPlayPause = 0xB3;

  bool start() {
    if (!Platform.isWindows || active) return active;
    final user32 = DynamicLibrary.open('user32.dll');
    final setHook = user32
        .lookupFunction<
          Pointer<Void> Function(
            Int32,
            Pointer<NativeFunction<_HookProc>>,
            Pointer<Void>,
            Uint32,
          ),
          Pointer<Void> Function(
            int,
            Pointer<NativeFunction<_HookProc>>,
            Pointer<Void>,
            int,
          )
        >('SetWindowsHookExW');
    final next = user32
        .lookupFunction<
          IntPtr Function(Pointer<Void>, Int32, IntPtr, IntPtr),
          int Function(Pointer<Void>, int, int, int)
        >('CallNextHookEx');

    // The hook runs on this (the UI) thread while it pumps messages, so the callback may use
    // the app normally. It must be quick; the work is handed to the event loop.
    _callback = NativeCallable<_HookProc>.isolateLocal((
      int code,
      int wParam,
      int lParam,
    ) {
      if (code == _hcAction &&
          (wParam == _wmKeyDown || wParam == _wmSysKeyDown)) {
        final vk = Pointer<Uint32>.fromAddress(lParam).value;
        final command = switch (vk) {
          _vkMediaPlayPause => 'playpause',
          _vkMediaNext => 'next',
          _vkMediaPrev => 'previous',
          _vkMediaStop => 'stop',
          _ => null,
        };
        if (command != null && handle(command)) {
          return 1; // used: do not pass it on
        }
      }
      return next(nullptr, code, wParam, lParam);
    }, exceptionalReturn: 0);

    _hook = setHook(_whKeyboardLl, _callback!.nativeFunction, nullptr, 0);
    if (!active) {
      _callback?.close();
      _callback = null;
      return false;
    }
    return true;
  }

  void stop() {
    final hook = _hook;
    if (hook != null && hook.address != 0 && Platform.isWindows) {
      DynamicLibrary.open('user32.dll').lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('UnhookWindowsHookEx')(hook);
    }
    _hook = null;
    _callback?.close();
    _callback = null;
  }
}

typedef _HookProc = IntPtr Function(Int32 code, IntPtr wParam, IntPtr lParam);
