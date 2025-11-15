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
  final SpeechToText _speech = SpeechToText();

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

    final loaded = <Map<String, dynamic>>[];
    for (final e in saved) {
      try {
        final p = e.split("||");
        if (p.length >= 2) {
          final item = p[0];
          final qty = int.tryParse(p[1]) ?? 1;
          loaded.add({"item": item, "qty": qty});
        }
      } catch (_) {
      }
    }

    setState(() {
      items = loaded;
    });
    debugPrint("Loaded ${items.length} items from prefs");
  }

  Future<void> saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    final list = items.map((e) => "${e['item']}||${e['qty']}").toList();
    await prefs.setStringList("shopping_list", list);
    debugPrint("Saved ${list.length} items to prefs");
  }

  Future<void> toggleListening() async {
    var mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => statusMessage = "Microphone permission denied");
      return;
    }

    if (!isListening) {
      bool available = await _speech.initialize(
        onStatus: (s) => debugPrint("STATUS: $s"),
        onError: (e) => debugPrint("ERROR: $e"),
      );

      if (available) {
        setState(() {
          isListening = true;
          recognizedText = "";
          statusMessage = "Listening...";
        });

        _speech.listen(
          localeId: "en_US",
          onResult: (val) {
            if (val.recognizedWords.isNotEmpty) {
              setState(() => recognizedText = val.recognizedWords);
            }

            if (val.finalResult) {
              final finalText = val.recognizedWords;
              setState(() {
                isListening = false;
                statusMessage = 'Processing… "$finalText"';
              });

              debugPrint("FINAL RECOGNIZED: $finalText");
              processCommand(finalText);
            }
          },
        );
      } else {
        setState(() => statusMessage = "Speech recognition unavailable");
      }
    } else {
      await _speech.stop();
      setState(() => isListening = false);
    }
  }

  void processCommand(String text) {
    final raw = text.toLowerCase().trim();
    debugPrint("PROCESSING: '$raw'");

    if (raw.isEmpty) {
      setState(() => statusMessage = "No speech detected");
      return;
    }

    int qty = 1;
    final numMatch = RegExp(r'\b(\d+)\b').firstMatch(raw);
    if (numMatch != null) {
      qty = int.tryParse(numMatch.group(1) ?? "1") ?? 1;
    }

    String cleaned = raw.replaceAll(RegExp(r'[^\w\s]'), " "); 
    cleaned = cleaned.replaceAll(RegExp(r'\b\d+\b'), "").replaceAll(RegExp(r'\s+'), " ").trim();

    String extractItem(String source, List<String> keywords) {
      var s = source;
      for (final k in keywords) {
        s = s.replaceAll(k, "");
      }
      s = s.replaceAll(RegExp(r'\s+'), " ").trim();

      s = s.replaceAll(RegExp(r"""^[\'"]+|[\'"]+$"""), "");
      return s;
    }

    if (raw.contains("add") || raw.contains("buy") || raw.contains("need") || raw.contains("put")) {
      final item = extractItem(cleaned, ["add", "buy", "need", "put", "please", "can i", "i want"]);
      if (item.isEmpty) {
        setState(() => statusMessage = "Please say what to add (e.g. 'Add 2 apples').");
        return;
      }
      addItem(item, qty);
      return;
    }

  
    if (raw.contains("remove") || raw.contains("delete") || raw.contains("take away")) {
      final item = extractItem(cleaned, ["remove", "delete", "take", "away"]);
      if (item.isEmpty) {
        setState(() => statusMessage = "Please say what to remove.");
        return;
      }
      removeItem(item);
      return;
    }

  
    if (raw.contains("find") || raw.contains("search") || raw.contains("is there")) {
      final item = extractItem(cleaned, ["find", "search", "is", "there"]);
      if (item.isEmpty) {
        setState(() => statusMessage = "Please say what to find.");
        return;
      }
      searchItem(item);
      return;
    }

    setState(() => statusMessage = "Sorry, I did not understand.");
  }


  void addItem(String itemRaw, int qty) async {
    final item = itemRaw.trim().toLowerCase(); 
    if (item.isEmpty) return;

    final existingIndex = items.indexWhere((e) => (e['item'] as String).toLowerCase() == item);
    if (existingIndex >= 0) {
      setState(() {
        items[existingIndex]['qty'] = (items[existingIndex]['qty'] as int) + qty;
        statusMessage = "Updated ${items[existingIndex]['qty']} × $item";
      });
      await saveItems();
      return;
    }

    setState(() {
      items.add({"item": item, "qty": qty});
      statusMessage = "Added $qty × $item";
    });

    await saveItems();
    debugPrint("After add: ${items.length} items");
  }

  void removeItem(String itemRaw) async {
    final item = itemRaw.trim().toLowerCase();
    if (item.isEmpty) return;

    final before = items.length;
    setState(() {
      items.removeWhere((e) => (e['item'] as String).toLowerCase() == item);
      statusMessage = "Removed $item";
    });

    if (items.length != before) {
      await saveItems();
      debugPrint("After remove: ${items.length} items");
    } else {
      setState(() => statusMessage = "$item not found in list");
    }
  }

  void searchItem(String itemRaw) {
    final item = itemRaw.trim().toLowerCase();
    if (item.isEmpty) {
      setState(() => statusMessage = "Please specify an item to search");
      return;
    }

    final found = items.firstWhere(
      (e) => (e['item'] as String).toLowerCase() == item,
      orElse: () => {},
    );

    setState(() {
      if (found.isEmpty) {
        statusMessage = "$item not found";
      } else {
        statusMessage = "$item is in your list (${found['qty']})";
      }
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
                        return Dismissible(
                          key: Key("${x['item']}_${x['qty']}_$index"),
                          background: Container(color: Colors.redAccent),
                          onDismissed: (_) async {
                            final removedItem = x['item'] as String;
                            removeItem(removedItem);
                          },
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text((x["qty"] as int).toString()),
                            ),
                            title: Text(x["item"] as String),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Examples: "Add 2 apples", "Remove milk", "Find sugar".',
            ),
            const SizedBox(height: 20),
          
          ],
        ),
      ),
    );
  }
}
