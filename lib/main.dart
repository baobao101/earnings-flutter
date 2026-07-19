// Whenever you update main.dart or any Flutter file: cd to earnings-app (root folder) and run these commands on the terminal:

// git add .
// git commit -m "Update frontend"
// git push

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

enum FinanceSource { yahoo, google, tradingview, marketwatch, nasdaq }

// ------------------------------------------------------------
// URL HELPERS
// ------------------------------------------------------------

String urlForSource(FinanceSource source, String ticker) {
  switch (source) {
    case FinanceSource.yahoo:
      return "https://finance.yahoo.com/quote/$ticker";
    case FinanceSource.google:
      return "https://www.google.com/finance/quote/$ticker:NASDAQ";
    case FinanceSource.tradingview:
      return "https://www.tradingview.com/symbols/$ticker";
    case FinanceSource.marketwatch:
      return "https://www.marketwatch.com/investing/stock/$ticker";
    case FinanceSource.nasdaq:
      return "https://www.nasdaq.com/market-activity/stocks/$ticker";
  }
}

String iconForSource(FinanceSource source) {
  switch (source) {
    case FinanceSource.yahoo:
      return "🟣 Y!";
    case FinanceSource.google:
      return "🔵 G";
    case FinanceSource.tradingview:
      return "🟢 TV";
    case FinanceSource.marketwatch:
      return "🟡 MW";
    case FinanceSource.nasdaq:
      return "⚪ NQ";
  }
}

// ------------------------------------------------------------
// MODEL
// ------------------------------------------------------------

class EarningsRow {
  final String ticker;
  final String date;
  final String source;
  final double volatilityScore;

  EarningsRow({
    required this.ticker,
    required this.date,
    required this.source,
    required this.volatilityScore,
  });
}

// ------------------------------------------------------------
// APP ROOT
// ------------------------------------------------------------

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: EarningsPage());
  }
}

// ------------------------------------------------------------
// MAIN PAGE
// ------------------------------------------------------------

class EarningsPage extends StatefulWidget {
  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
  FinanceSource? preferredSource;
  List<EarningsRow> rows = [];

  bool showNearTermOnly = false;
  bool showHighVolOnly = false;

  @override
  void initState() {
    super.initState();
    _loadPreferredSource();
    _loadEarnings();
  }

  // ------------------------------------------------------------
  // FETCH EARNINGS.JSON FROM GITHUB
  // ------------------------------------------------------------

  Future<List<EarningsRow>> fetchEarnings() async {
    final url = "https://baobao101.github.io/earnings-data/earnings.json";

    final response = await http.get(Uri.parse(url));
    final List data = jsonDecode(response.body);

    return data.map((row) {
      return EarningsRow(
        ticker: row["ticker"],
        date: row["date"],
        source: row["source"],
        volatilityScore: row["volatility_score"] ?? 0,
      );
    }).toList();
  }

  Future<void> _loadEarnings() async {
    rows = await fetchEarnings();
    setState(() {});
  }

  // ------------------------------------------------------------
  // PREFERRED SOURCE STORAGE
  // ------------------------------------------------------------

  Future<void> _loadPreferredSource() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString("preferred_source");
    if (name != null) {
      preferredSource = FinanceSource.values.firstWhere((s) => s.name == name);
    }
    setState(() {});
  }

  Future<void> setPreferredSource(FinanceSource source) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("preferred_source", source.name);
    setState(() {
      preferredSource = source;
    });
  }

  // ------------------------------------------------------------
  // SMART URL LAUNCHER
  // ------------------------------------------------------------

  Future<void> openTickerSmart(String ticker) async {
    final sources = FinanceSource.values.toList();

    if (preferredSource != null) {
      sources.remove(preferredSource);
      sources.insert(0, preferredSource!);
    }

    for (final source in sources) {
      final url = urlForSource(source, ticker);
      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Unable to open financial info right now")),
    );
  }

  // ------------------------------------------------------------
  // BOTTOM SHEET SELECTOR
  // ------------------------------------------------------------

  void showSourceSelector() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: FinanceSource.values.map((source) {
            return ListTile(
              title: Text(
                "${iconForSource(source)}  ${source.name.toUpperCase()}",
              ),
              onTap: () {
                setPreferredSource(source);
                Navigator.pop(context);
              },
            );
          }).toList(),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // VOLATILITY BADGE
  // ------------------------------------------------------------

  Widget volatilityBadge(double score) {
    Color color;
    if (score >= 70) {
      color = Colors.redAccent;
    } else if (score >= 40) {
      color = Colors.orangeAccent;
    } else {
      color = Colors.green;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        "⚡ $score",
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ------------------------------------------------------------
  // FILTERING + SORTING + GROUPING
  // ------------------------------------------------------------
  List<EarningsRow> get filteredRows {
    List<EarningsRow> list = rows;

    // Near-term filter (next 10 days)
    if (showNearTermOnly) {
      final today = DateTime.now();
      final cutoff = today.add(Duration(days: 10));

      list = list.where((row) {
        final d = DateTime.tryParse(row.date);
        if (d == null) return false;
        return d.isAfter(today) && d.isBefore(cutoff);
      }).toList();
    }

    // High-vol filter
    if (showHighVolOnly) {
      list = list.where((row) => row.volatilityScore >= 60).toList();
    }

    // Sort by date first, then volatility
    list.sort((a, b) {
      final da = DateTime.tryParse(a.date);
      final db = DateTime.tryParse(b.date);

      if (da != null && db != null) {
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
      }

      return b.volatilityScore.compareTo(a.volatilityScore);
    });

    return list;
  }

  Map<String, List<EarningsRow>> groupByDate(List<EarningsRow> list) {
    final map = <String, List<EarningsRow>>{};
    for (final row in list) {
      map.putIfAbsent(row.date, () => []);
      map[row.date]!.add(row);
    }
    return map;
  }

  // ------------------------------------------------------------
  // ROW BUILDER
  // ------------------------------------------------------------

  Widget buildRow(EarningsRow row) {
    return ListTile(
      title: Row(
        children: [
          Text(row.ticker, style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          volatilityBadge(row.volatilityScore),
          SizedBox(width: 8),
          if (preferredSource != null)
            Text(
              iconForSource(preferredSource!),
              style: TextStyle(fontSize: 16),
            ),
        ],
      ),
      subtitle: Text(row.date),
      onTap: () => openTickerSmart(row.ticker),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final grouped = groupByDate(filteredRows);

    return Scaffold(
      appBar: AppBar(
        title: Text("Earnings Viewer"),
        actions: [
          IconButton(icon: Icon(Icons.settings), onPressed: showSourceSelector),
        ],
      ),

      body: rows.isEmpty
          ? Center(child: CircularProgressIndicator())
          : ListView(
              children: grouped.entries.map((entry) {
                final date = entry.key;
                final items = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      color: Colors.grey.shade200,
                      padding: EdgeInsets.all(8),
                      child: Text(
                        date,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...items.map(buildRow).toList(),
                  ],
                );
              }).toList(),
            ),

      bottomNavigationBar: Container(
        color: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Switch(
                  value: showNearTermOnly,
                  onChanged: (v) => setState(() => showNearTermOnly = v),
                ),
                Text("Near-term only"),
              ],
            ),
            Row(
              children: [
                Switch(
                  value: showHighVolOnly,
                  onChanged: (v) => setState(() => showHighVolOnly = v),
                ),
                Text("High-vol only"),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
