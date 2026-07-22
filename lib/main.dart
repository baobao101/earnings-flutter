// Whenever you update main.dart or any Flutter file: cd to earnings-app (root folder) and run these commands on the terminal:
// flutter pub get (only if new import or modified pub yaml)
// flutter doctor
// flutter analyze
// git add .
// git commit -m "Update frontend"
// git push

// flutter clean
// flutter pub get
// flutter run

import 'package:pluto_grid/pluto_grid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:add_2_calendar/add_2_calendar.dart';

Future<void> saveToCalendar(EarningsRow row) async {
  final date = row.date;

  final event = Event(
    title: "${row.ticker} Earnings",
    description: "Earnings date for ${row.ticker}",
    startDate: date,
    endDate: date.add(Duration(hours: 1)),
  );

  Add2Calendar.addEvent2Cal(event);
}

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
  final DateTime date;
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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const EarningsPage(),
    );
  }
}

// ------------------------------------------------------------
// MAIN PAGE
// ------------------------------------------------------------

class EarningsPage extends StatefulWidget {
  const EarningsPage({super.key});

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
  PlutoGridStateManager? stateManager;

  List<PlutoRow> cachedPlutoRows = [];

  final TextEditingController searchController = TextEditingController();
  String tickerSearch = "";

  void applyCombinedFilter() {
    if (stateManager != null) {
      stateManager!.setFilter((row) {
        final d = DateTime.tryParse(row.cells['date']!.value);
        final score = row.cells['volatility']!.value as double;
        final ticker = row.cells['ticker']!.value.toString().toLowerCase();

        final today = DateTime.now();
        final startOfToday = DateTime(today.year, today.month, today.day);
        final cutoff = startOfToday.add(Duration(days: 4));

        final passesNearTerm =
            !showNearTermOnly ||
            (d != null && !d.isBefore(startOfToday) && d.isBefore(cutoff));

        final passesHighVol = !showHighVolOnly || score >= 60;

        final passesSearch =
            tickerSearch.isEmpty || ticker.contains(tickerSearch);

        return passesNearTerm && passesHighVol && passesSearch;
      });
    }
  }

  List<EarningsRow> filtered = [];
  void recomputeFilteredRows() {
    List<EarningsRow> list = rows;

    list.sort((a, b) {
      final da = a.date;
      final db = b.date;

      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;

      return b.volatilityScore.compareTo(a.volatilityScore);
    });

    filtered = list;

    cachedPlutoRows = filtered.map((row) {
      return PlutoRow(
        cells: {
          'date': PlutoCell(value: row.date.toString().split(' ')[0]),
          'ticker': PlutoCell(value: row.ticker),
          'volatility': PlutoCell(value: row.volatilityScore),
          'source': PlutoCell(value: row.source),
        },
      );
    }).toList();
    if (stateManager != null) {}
  }

  List<PlutoColumn> get plutoColumns => [
    PlutoColumn(
      title: 'Date',
      field: 'date',
      type: PlutoColumnType.text(),
      enableSorting: true,
      enableFilterMenuItem: true,
      enableColumnDrag: true,
      frozen: PlutoColumnFrozen.start,
    ),

    PlutoColumn(
      title: 'Ticker',
      field: 'ticker',
      type: PlutoColumnType.text(),
      enableSorting: true,
      enableFilterMenuItem: true,
      enableColumnDrag: true,

      renderer: (context) {
        final ticker = context.cell.value.toString();

        final row = rows.firstWhere(
          (r) =>
              r.ticker == ticker &&
              r.date.toString().split(' ')[0] ==
                  context.row.cells['date']!.value,
        );

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => openTickerSmart(ticker),
                child: Text(
                  ticker,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.event, size: 18),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => saveToCalendar(row),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.notifications, size: 18),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => scheduleReminder(row),
                ),
              ],
            ),
          ],
        );
      },
    ),

    PlutoColumn(
      title: 'Volatility',
      field: 'volatility',
      type: PlutoColumnType.number(),
      enableSorting: true,
      enableFilterMenuItem: true,
      enableColumnDrag: true,
    ),

    PlutoColumn(
      title: 'Source',
      field: 'source',
      type: PlutoColumnType.text(),
      enableSorting: true,
      enableFilterMenuItem: true,
      enableColumnDrag: true,
    ),
  ];

  FinanceSource? preferredSource;
  List<EarningsRow> rows = [];

  bool showNearTermOnly = false;
  bool showHighVolOnly = false;
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  void initNotifications() {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    notifications.initialize(settings);
  }

  @override
  void initState() {
    super.initState();
    initNotifications();
    _loadPreferredSource();
    _loadEarnings();
  }

  List<EarningsRow> parseRows(String jsonStr) {
    final List data = jsonDecode(jsonStr);
    return data.map((row) {
      return EarningsRow(
        ticker: row["ticker"],
        date: DateTime.parse(row["date"]),

        source: row["source"],
        volatilityScore: (row["volatility_score"] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  // ------------------------------------------------------------
  // FETCH EARNINGS.JSON FROM GITHUB
  // ------------------------------------------------------------

  bool isValidJson(String body) {
    if (body.isEmpty) return false;
    if (body.startsWith("<")) return false; // HTML error page
    try {
      jsonDecode(body);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<EarningsRow>> fetchEarnings() async {
    const jsDelivrUrl =
        "https://cdn.jsdelivr.net/gh/baobao101/earnings-data/earnings.json";

    const rawGithubUrl =
        "https://raw.githubusercontent.com/baobao101/earnings-data/main/earnings.json";

    // Try jsDelivr first
    try {
      final response = await http.get(Uri.parse(jsDelivrUrl));
      if (response.statusCode == 200 && isValidJson(response.body)) {
        return parseRows(response.body);
      }
    } catch (_) {}

    // Fallback to raw GitHub
    try {
      final response = await http.get(Uri.parse(rawGithubUrl));
      if (response.statusCode == 200 && isValidJson(response.body)) {
        return parseRows(response.body);
      }
    } catch (_) {}

    return [];
  }

  Future<void> _loadEarnings() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString("cached_earnings");

    final last = prefs.getInt("last_refresh") ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final oneDay = Duration(days: 1).inMilliseconds;

    final shouldRefresh = (now - last) > oneDay;

    // Use cached data only if valid AND not expired
    if (cached != null && cached.isNotEmpty && !shouldRefresh) {
      rows = parseRows(cached);
      recomputeFilteredRows();
      setState(() {});
      return;
    }

    // Otherwise fetch fresh data
    final fresh = await fetchEarnings();
    if (fresh.isNotEmpty) {
      prefs.setInt("last_refresh", now);

      prefs.setString(
        "cached_earnings",
        jsonEncode(
          fresh
              .map(
                (e) => {
                  "ticker": e.ticker,
                  "date": e.date.toIso8601String(),

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

  //-scheduler
  Future<void> scheduleReminder(EarningsRow row) async {
    final date = row.date; // Already a DateTime
    final reminderTime = date.subtract(Duration(days: 1));

    await notifications.zonedSchedule(
      row.ticker.hashCode,
      "${row.ticker} earnings tomorrow",
      "Tap to view details",
      tz.TZDateTime.from(reminderTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'earnings_channel',
          'Earnings Alerts',
          importance: Importance.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
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
      final key = row.date.toString().split(' ')[0];
      map.putIfAbsent(key, () => []);
      map[key]!.add(row);
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
        ],
      ),
      subtitle: Text(row.date.toString().split(' ')[0]),

      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.event),
            onPressed: () => saveToCalendar(row),
          ),
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: () => scheduleReminder(row),
          ),
        ],
      ),
      onTap: () => openTickerSmart(row.ticker),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Earnings Viewer"),
        actions: [
          IconButton(icon: Icon(Icons.settings), onPressed: showSourceSelector),
        ],
      ),

      body: cachedPlutoRows.isEmpty
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
                    mode: PlutoGridMode.select,
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
