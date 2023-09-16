import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool openWifi = false;
  StreamController<List<WifiNetwork>> wifiStreamController = StreamController<List<WifiNetwork>>.broadcast();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: openWifi
            ? Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  StreamBuilder<List<WifiNetwork>>(
                    stream: wifiStreamController.stream,
                    builder: (context, AsyncSnapshot snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        print("--------------${snapshot.error}");
                        return Text("Error: ${snapshot.error}");
                      } else if (snapshot.hasData) {
                        List<WifiNetwork>? ssidPrefixList = snapshot.data;
                        return Expanded(
                          child: ListView.builder(
                              itemCount: ssidPrefixList?.length,
                              itemBuilder: (_, index) {
                                return Text('----${ssidPrefixList![index].ssid}');
                              }),
                        );
                      } else {
                        return const SizedBox();
                      }
                    },
                  ),
                ],
              )
            : const SizedBox(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          setState(() {
            openWifi = !openWifi;
          });
          if (openWifi) {
            Map<Permission, PermissionStatus> statuses = await [
              Permission.locationWhenInUse,
              // Permission.nearbyWifiDevices,
            ].request();

            PermissionStatus locationWhenInUseStatus = statuses[Permission.locationWhenInUse]!;
            //PermissionStatus nearbyWifiDevicesStatus = statuses[Permission.nearbyWifiDevices]!;
            if (locationWhenInUseStatus.isDenied /*|| nearbyWifiDevicesStatus.isDenied*/) {
              await Permission.locationWhenInUse.request();
              //await Permission.nearbyWifiDevices.request();
            } else if (locationWhenInUseStatus.isPermanentlyDenied /*|| nearbyWifiDevicesStatus.isPermanentlyDenied*/) {
              openAppSettings();
            } else if (locationWhenInUseStatus.isGranted /*|| nearbyWifiDevicesStatus.isGranted*/) {
              startWifiScan(wifiStreamController);
            }
          }
        },
        child: const Text('wifi scan'),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  @pragma('vm:entry-point')
  static void startWifiScan(StreamController<List<WifiNetwork>?> wifiStreamController) async {
    final ReceivePort wifiReceivePort = ReceivePort();
    await FlutterIsolate.spawn(
      wifiScanIsolate,
      wifiReceivePort.sendPort,
    );
    wifiReceivePort.listen((data) {
      if (data is List && data.isNotEmpty) {
        final wifiList = data.map((serializedWifi) => WifiNetwork.fromJson(serializedWifi)).toList();
        wifiStreamController.add(wifiList);
      }
    });
  }

  static void wifiScanIsolate(SendPort wifiSendPort) async {
    const Duration interval = Duration(seconds: 5);
    const String prefix = "";
    await for (var wifiList in scanWifiNetworks(interval, prefix)) {
      final serializedList = wifiList.map((wifi) => wifi.toJson()).toList();
      if (serializedList.isNotEmpty) {
        wifiSendPort.send(serializedList);
      } else {
        FlutterIsolate.current.kill();
      }
    }
  }

  static Stream<List<WifiNetwork>> scanWifiNetworks(Duration interval, String prefix) async* {
    while (true) {
      List<WifiNetwork> wifiList = await WiFiForIoTPlugin.loadWifiList();
      Set<WifiNetwork> ssidSet = <WifiNetwork>{};
      for (var element in wifiList) {
        if (element.ssid.toString().contains(prefix)) {
          ssidSet.add(element);
        }
      }
      yield ssidSet.toList();
      await Future.delayed(interval);
    }
  }
}
