import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_web_auth_2_platform_interface/flutter_web_auth_2_platform_interface.dart';

class FlutterWebAuth2WebViewPlugin extends FlutterWebAuth2Platform {
  _AuthInAppBrowser? _browser;

  @override
  Future<String> authenticate({
    required String url,
    required String callbackUrlScheme,
    required Map<String, dynamic> options,
  }) async {
    final parsedOptions = FlutterWebAuth2Options.fromJson(options);

    await _browser?.close();
    _browser = null;

    final completer = Completer<String>();

    _browser = _AuthInAppBrowser(
      callbackUrlScheme: callbackUrlScheme,
      options: parsedOptions,
      onResult: (resultUrl) {
        if (!completer.isCompleted) {
          completer.complete(resultUrl);
        }
      },
      onCancel: () {
        if (!completer.isCompleted) {
          completer.completeError(
            PlatformException(
              code: 'CANCELED',
              message: 'User canceled',
            ),
          );
        }
      },
    );

    await _browser!.openUrlRequest(
      urlRequest: URLRequest(
        url: WebUri(url),
      ),
      settings: InAppBrowserClassSettings(
        browserSettings: InAppBrowserSettings(
          hideUrlBar: true,
          hideToolbarTop: false,
        ),
      ),
    );

    return completer.future;
  }

  @override
  Future<void> clearAllDanglingCalls() async {
    await _browser?.close();
    _browser = null;
  }
}

class _AuthInAppBrowser extends InAppBrowser {
  final String callbackUrlScheme;
  final FlutterWebAuth2Options options;
  final void Function(String url) onResult;
  final VoidCallback onCancel;

  bool _completed = false;

  _AuthInAppBrowser({
    required this.callbackUrlScheme,
    required this.options,
    required this.onResult,
    required this.onCancel,
  });

  @override
  Future<NavigationActionPolicy> shouldOverrideUrlLoading(
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null) {
      return NavigationActionPolicy.ALLOW;
    }

    final isCallback = uri.scheme == callbackUrlScheme &&
        (options.httpsHost == null || uri.host == options.httpsHost) &&
        (options.httpsPath == null || uri.path == options.httpsPath);

    if (isCallback && !_completed) {
      _completed = true;
      onResult(uri.toString());
      if (!Platform.isLinux) {
        await close(); // not implemented for linux yet
      }

      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  @override
  void onUpdateVisitedHistory(WebUri? url, bool? isReload) {
    super.onUpdateVisitedHistory(url, isReload);
    if (url != null) {
      final uri = Uri.parse(url.toString());
      final isCallback = uri.scheme == callbackUrlScheme &&
          (options.httpsHost == null || uri.host == options.httpsHost) &&
          (options.httpsPath == null || uri.path == options.httpsPath);

      if (isCallback && !_completed) {
        _completed = true;
        onResult(uri.toString());
        if (!Platform.isLinux) {
          close(); // not implemented for linux yet
        }
      }
    }
  }

  @override
  void onExit() {
    if (!_completed) {
      _completed = true;
      onCancel();
    }
    super.onExit();
  }
}
