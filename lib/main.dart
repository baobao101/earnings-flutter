// Whenever you update main.dart or any Flutter file: cd to earnings-app (root folder) and run these commands on the terminal:

// git add .
// git commit -m "Update frontend"
// git push
import 'package:pluto_grid/pluto_grid.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

enum FinanceSource { yahoo, google, tradingview, marketwatch, nasdaq }

FinanceSource preferredSource = FinanceSource.tradingview;
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
  final TextEditingController searchController = TextEditingController();
  String tickerSearch = "";
  List<PlutoRow> cachedPlutoRows = [];

  void applyCombinedFilter() {
    stateManager.setFilter((row) {
      final d = DateTime.tryParse(row.cells['date']!.value);
      final score = row.cells['volatility']!.value as double;
      final ticker = row.cells['ticker']!.value.toString().toLowerCase();

      final now = DateTime.now();
      final cutoff = now.add(Duration(days: 4));

      final passesNearTerm =
          !showNearTermOnly ||
          (d != null && d.isAfter(now) && d.isBefore(cutoff));

      final passesHighVol = !showHighVolOnly || score >= 60;

      final passesSearch =
          tickerSearch.isEmpty || ticker.contains(tickerSearch.toLowerCase());

      return passesNearTerm && passesHighVol && passesSearch;
    });
  }

  late PlutoGridStateManager stateManager;

  List<EarningsRow> filtered = [];
  void recomputeFilteredRows() {
    List<EarningsRow> list = rows;

    // Sort once
    list.sort((a, b) {
      final da = DateTime.tryParse(a.date);
      final db = DateTime.tryParse(b.date);

      if (da != null && db != null) {
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
      }

      return b.volatilityScore.compareTo(a.volatilityScore);
    });

    filtered = list;
    cachedPlutoRows = filtered.map((row) {
      return PlutoRow(
        cells: {
          'date': PlutoCell(value: row.date),
          'ticker': PlutoCell(value: row.ticker),
          'volatility': PlutoCell(value: row.volatilityScore),
          'source': PlutoCell(value: row.source),
        },
      );
    }).toList();
  }

  List<PlutoColumn> get plutoColumns => [
    PlutoColumn(
      title: 'Ticker',
      field: 'ticker',
      type: PlutoColumnType.text(),
      enableSorting: true,
      enableFilterMenuItem: true,
      enableColumnDrag: true,

      renderer: (rendererContext) {
        final ticker = rendererContext.cell.value.toString();

        return InkWell(
          onTap: () => openTickerSmart(ticker),
          child: Text(
            ticker,
            style: const TextStyle(
              color: Colors.blue,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    ),
  ];

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

  List<EarningsRow> parseRows(String jsonStr) {
    final List data = jsonDecode(jsonStr);

    return data.map((row) {
      return EarningsRow(
        ticker: row["ticker"],
        date: row["date"],
        source: row["source"],
        volatilityScore: (row["volatility_score"] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  // ------------------------------------------------------------
  // FETCH EARNINGS.JSON FROM GITHUB
  // ------------------------------------------------------------

  Future<List<EarningsRow>> fetchEarnings() async {
    final url =
        "https://cdn.jsdelivr.net/gh/baobao101/earnings-data/earnings.json";
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) return [];

    return parseRows(response.body);
  }

  Future<void> _loadEarnings() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString("cached_earnings");

    // --- 24-hour auto-refresh check ---
    final last = prefs.getInt("last_refresh") ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final oneDay = Duration(days: 1).inMilliseconds;

    final shouldRefresh = (now - last) > oneDay;

    // --- Instant load from cache ---
    if (cached != null && !shouldRefresh) {
      rows = parseRows(cached);
      recomputeFilteredRows();
      setState(() {});
    }

    // --- Always fetch fresh if cache missing OR 24h passed ---
    final fresh = await fetchEarnings();
    if (fresh.isNotEmpty) {
      // Save timestamp
      prefs.setInt("last_refresh", now);

      // Save fresh JSON
      prefs.setString(
        "cached_earnings",
        jsonEncode(
          fresh
              .map(
                (e) => {
                  "ticker": e.ticker,
                  "date": e.date,
                  "source": e.source,
                  "volatility_score": e.volatilityScore,
                },
              )
              .toList(),
        ),
      );

      rows = fresh;
      recomputeFilteredRows();

      setState(() {});
    }
  }

  // ------------------------------------------------------------
  // PREFERRED SOURCE STORAGE
  // ------------------------------------------------------------

  Future<void> _loadPreferredSource() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString("preferred_source");

    if (name != null) {
      preferredSource = FinanceSource.values.firstWhere(
        (s) => s.name == name,
        orElse: () => FinanceSource.tradingview,
      );
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
    final source = preferredSource ?? FinanceSource.tradingview;

    final uri = Uri.parse(urlForSource(source, ticker));

    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    // final grouped = groupByDate(filteredRows);

    return Scaffold(
      appBar: AppBar(
        title: Text("Earnings Viewer"),
        actions: [
          IconButton(icon: Icon(Icons.settings), onPressed: showSourceSelector),
        ],
      ),

      body: rows.isEmpty
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search ticker...",
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: tickerSearch.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setState(() {
                                  tickerSearch = "";
                                  applyCombinedFilter();
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        tickerSearch = value;
                        applyCombinedFilter();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: PlutoGrid(
                    onLoaded: (event) {
                      stateManager = event.stateManager;
                    },
                    columns: plutoColumns,
                    rows: cachedPlutoRows,
                    mode: PlutoGridMode.readOnly,
                    configuration: PlutoGridConfiguration(
                      columnSize: PlutoGridColumnSizeConfig(
                        autoSizeMode: PlutoAutoSizeMode.scale,
                      ),
                      style: PlutoGridStyleConfig(
                        gridBorderColor: Colors.grey.shade300,
                        gridBackgroundColor: Colors.white,
                        activatedColor: Colors.blue.shade50,
                        activatedBorderColor: Colors.blue.shade200,
                        cellTextStyle: TextStyle(fontSize: 14),
                        columnTextStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
                  onChanged: (v) {
                    setState(() {
                      showNearTermOnly = v;
                      applyCombinedFilter();
                    });
                  },
                ),
                Text("Near-term only"),
              ],
            ),
            Row(
              children: [
                Switch(
                  value: showHighVolOnly,
                  onChanged: (v) {
                    setState(() {
                      showHighVolOnly = v;
                      applyCombinedFilter();
                    });
                  },
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
