import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Voice Shopping Assistant",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: const ShoppingHome(),
    );
  }
}

class ShoppingHome extends StatefulWidget {
  const ShoppingHome({super.key});

  @override
  State<ShoppingHome> createState() => _ShoppingHomeState();
}

class _ShoppingHomeState extends State<ShoppingHome> {
  SpeechToText speech = SpeechToText();

  bool isListening = false;
  String recognizedText = "";
  String statusMessage = "Press the mic and speak";
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    loadItems();
  }


  Future<void> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList("shopping_list") ?? [];

    items = saved.map((e) {
      final parts = e.split("||");
      return {"item": parts[0], "qty": int.parse(parts[1])};
    }).toList();

    setState(() {});
  }

  Future<void> saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(
      "shopping_list",
      items.map((e) => "${e['item']}||${e['qty']}").toList(),
    );
  }


  Future<void> toggleListening() async {
    var mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => statusMessage = "Microphone permission denied");
      return;
    }

    if (!isListening) {
      bool available = await speech.initialize(
        onStatus: (s) => print("STATUS: $s"),
        onError: (e) => print("ERROR: $e"),
      );

      if (available) {
        setState(() {
          isListening = true;
          recognizedText = "";
          statusMessage = "Listening…";
        });

        speech.listen(
          localeId: "en_US",
          onResult: (val) {
            print("RAW: ${val.recognizedWords}");

            setState(() {
              recognizedText = val.recognizedWords;
            });

            if (val.finalResult) {
              print("FINAL: $recognizedText");
              setState(() {
                isListening = false;
                statusMessage = "Processing… \"$recognizedText\"";
              });
              _processCommand(recognizedText);
            }
          },
        );
      }
    } else {
      speech.stop();
      setState(() => isListening = false);
    }
  }

  

  void _processCommand(String text) {
    String command = text.toLowerCase();

   
    command = command
        .replaceAll("\u200B", "")
        .replaceAll("\u200C", "")
        .replaceAll("\u200D", "")
        .replaceAll("\uFEFF", "")
        .trim();

    print("PROCESSING: $command");

    int qty = 1;
    final match = RegExp(r'\d+').firstMatch(command);
    if (match != null) qty = int.parse(match.group(0)!);

    
    String raw = command.replaceAll(RegExp(r'\d+'), "").trim();

  
    if (command.contains("add") ||
        command.contains("buy") ||
        command.contains("need")) {
      String item = raw
          .replaceAll("add", "")
          .replaceAll("buy", "")
          .replaceAll("need", "")
          .trim();
      _addItem(item, qty);
      return;
    }

    
    if (command.contains("remove") || command.contains("delete")) {
      String item = raw
          .replaceAll("remove", "")
          .replaceAll("delete", "")
          .trim();
      _removeItem(item);
      return;
    }

    
    if (command.contains("find") || command.contains("search")) {
      String item = raw.replaceAll("find", "").replaceAll("search", "").trim();
      _searchItem(item);
      return;
    }

    setState(() {
      statusMessage = "Sorry, I did not understand.";
    });
  }

 

  void _addItem(String item, int qty) {
    if (item.isEmpty) return;

    items.add({"item": item, "qty": qty});
    saveItems();

    setState(() {
      statusMessage = "Added $qty × $item";
    });
  }

  void _removeItem(String item) {
    items.removeWhere((e) => e["item"] == item);
    saveItems();

    setState(() {
      statusMessage = "Removed $item";
    });
  }

  void _searchItem(String item) {
    bool exists = items.any((e) => e["item"] == item);

    setState(() {
      statusMessage = exists ? "$item is in your list" : "$item not found";
    });
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Voice Shopping Assistant")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isListening ? Colors.red : Colors.green,
        onPressed: toggleListening,
        child: Icon(isListening ? Icons.mic : Icons.mic_none),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // status
            Center(
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    statusMessage,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "Your List:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text("Your shopping list is empty"))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final x = items[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(x["qty"].toString()),
                          ),
                          title: Text(x["item"]),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 10),
            const Text(
              'Examples: "Add 2 bottles of water", "Remove milk", "Find apples".',
            ),
          ],
        ),
      ),
    );
  }
}
