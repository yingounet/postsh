import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

/// SSH 服务，用于建立连接并执行命令。
class SshService {
  /// 测试连接：连接目标主机并执行 echo test。
  /// 用于验证 dartssh2 集成是否正常。
  static Future<String> runEchoTest(
    String host,
    int port,
    String username, {
    String? password,
  }) async {
    final socket = await SSHSocket.connect(host, port);
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: password != null && password.isNotEmpty
          ? () => password
          : null,
    );

    try {
      await client.authenticated;
      final output = await client.run('echo test');
      return utf8.decode(output);
    } finally {
      client.close();
    }
  }
}
