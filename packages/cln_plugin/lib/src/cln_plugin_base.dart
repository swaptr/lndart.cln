// TODO: Put public facing types in this file.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:cln_plugin/src/json_rpc/error.dart';
import 'package:cln_plugin/src/json_rpc/request.dart';
import 'package:cln_plugin/src/json_rpc/response.dart';
import 'package:cln_plugin/src/rpc_method/builtin/get_manifest.dart';
import 'package:cln_plugin/src/rpc_method/builtin/init.dart';
import 'package:cln_plugin/src/rpc_method/rpc_command.dart';
import 'package:cln_plugin/src/rpc_method/types/option.dart';

import 'icln_plugin_base.dart';
import 'json_rpc/response.dart';

class Plugin implements CLNPlugin {
  /// List of methods exposed
  HashMap<String, RPCCommand> rpcMethods = HashMap();

  /// List of Subscriptions
  List<String> subscriptions = [];

  /// List of Options
  List<Option> options = [];

  /// List of Hooks
  Set<String> hooks = {};

  /// FeatureBits for announcements of featurebits in protocol
  HashMap<String, Object> features = HashMap();

  /// Boolean to mark dynamic management of plugin
  bool dynamic;

  /// Custom notifications map
  HashMap<String, RPCCommand> notifications = HashMap();

  Plugin({this.dynamic = false});

  @override
  void registerFeature({required String name, required String value}) {
    features[name] = value;
  }

  @override
  void registerOption(
      {required String name,
      required String type,
      required String def,
      required String description,
      required bool deprecated}) {
    options = Option(
        name: name,
        type: type,
        def: def,
        description: description,
        deprecated: deprecated) as List<Option>;
  }

  @override
  void registerRPCMethod(
      {required String name,
      required String usage,
      required String description,
      required Future<Map<String, Object>> Function(Plugin, Map<String, Object>)
          callback}) {
    rpcMethods[name] = RPCCommand(
        name: name, usage: usage, description: description, callback: callback);
  }

  @override
  void registerSubscriptions({required String event}) {
    subscriptions.add(event);
  }

  @override
  void registerHook({required String name}) {
    hooks.add(name);
  }

  @override
  void registerNotification(
      {required String event,
      required Future<Map<String, Object>> Function(Plugin, Map<String, Object>)
          onEvent}) {
    notifications["event"] =
        RPCCommand(name: "", usage: "", description: "", callback: onEvent);
  }

  /// get manifest method used to communicate the plugin configuration
  /// to core lightning.
  Future<Map<String, Object>> getManifest(
      Plugin plugin, Map<String, Object> request) {
    // TODO: add some unit test to check if the format it is correct!
    var response = HashMap<String, Object>();
    response["options"] = plugin.options.map((opt) => opt.toMap()).toList();
    response["rpcmethods"] = plugin.rpcMethods.values
        .where((rpc) => rpc.name != "init" && rpc.name != "getmanifest")
        .map((rpc) => rpc.toMap())
        .toList();
    response["subscriptions"] = plugin.subscriptions;
    response["hooks"] = plugin.hooks.toList();
    response["notifications"] = [];
    response["dynamic"] = plugin.dynamic;
    return Future.value(response);
  }

  /// init method used to answer to configure the plugin with the core lightning
  /// configuration.
  Future<Map<String, Object>> init(Plugin plugin, Map<String, Object> request) {
    ///
    return Future.value({});
  }

  // init plugin used to register the rpc method required by the plugin
  // life cycle
  void _initPlugin() {
    rpcMethods["getmanifest"] =
        GetManifest(callback: (Plugin plugin, Map<String, Object> request) {
      return getManifest(plugin, request);
    });
    rpcMethods["init"] = InitMethod(
        callback: (Plugin plugin, Map<String, Object> request) =>
            init(plugin, request));
  }

  Future<Map<String, Object>> _call(
      String name, Map<String, Object> request) async {
    if (rpcMethods.containsKey(name)) {
      var method = rpcMethods[name]!;
      return await method.call(this, request);
    }
    throw Exception("Method with name $name not found!");
  }

  @override
  void start() async {
    _initPlugin();
    try {
      String? messageSocket;
      while ((messageSocket = stdin.readLineSync()) != null) {
        // Already checked is stdin is not null, why trim and check again??
        if (messageSocket!.trim().isEmpty) {
          continue;
        }
        var jsonRequest = Request.fromJson(jsonDecode(messageSocket));
        try {
          HashMap<String, Object> param;
          if (jsonRequest.params is Map) {
            param = HashMap<String, Object>.from(jsonRequest.params);
          } else {
            param = HashMap();
          }
          var response = await _call(jsonRequest.method, param);
          stdout.write(Response(id: jsonRequest.id, result: response).toJson());
        } catch (ex) {
          var response = Response(
              id: jsonRequest.id,
              error: Error(code: -1, message: ex.toString()))
              .toJson();
          stdout.write(response);
        }
      }
    } catch (error, stacktrace) {
      stderr.write(stacktrace);
      stderr.write(error);
    }
  }
}
