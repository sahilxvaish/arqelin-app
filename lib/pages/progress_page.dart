import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A day counts toward a streak when completion >= this fraction.
/// 1.0 = every task done. Change this ONE constant to move the rule
/// everywhere: heatmap "success", current streak, best streak, KPIs.
const double kStreakThreshold = 1.0;

/// Arqelin accent, same as the auth gradient and the home background blob.
const Color kArqelinBlue = Color(0xFF2B44FF);

// =============================================================================
// MODEL
// =============================================================================
class DayStat {
  final DateTime date;
  final int total;
  final int completed;

  const DayStat({
    required this.date,
    required this.total,
    required this.completed,
  });

  /// 0.0 – 1.0
  double get fraction => total == 0 ? 0 : completed / total;

  int get percent => (fraction * 100).round();

  bool get isSuccess => total > 0 && fraction >= kStreakThreshold;
}

class HistoryEntry {
  final String title;
  final bool completed;

  const HistoryEntry({required this.title, required this.completed});
}

// =============================================================================
// DATE HELPERS — local calendar dates only, never UTC.
// =============================================================================
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

const List<String> kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> kMonthShort = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

const List<String> kWeekdayShort = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

String prettyDate(DateTime d) =>
    '${kWeekdayShort[d.weekday - 1]}, ${kMonthShort[d.month - 1]} ${d.day}';

String longDate(DateTime d) =>
    '${d.day} ${kMonthNames[d.month - 1].toUpperCase()} ${d.year}';

// =============================================================================
// PAGE
// =============================================================================
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final supabase = Supabase.instance.client;

  // Whole history, keyed by 'YYYY-MM-DD'. ONE query fills this.
  final Map<String, DayStat> _byDate = {};
  List<DayStat> _allDays = [];

  List<HistoryEntry> _dayDetail = [];

  bool _loading = true;
  bool _detailLoading = false;
  String? _error;

  late DateTime _today;
  late DateTime _selectedDate;
  late int _heatmapYear;
  late int _heatmapMonth;

  bool _yearlyView = false;
  int _chartRange = 7; // 7 | 30 | 90

  @override
  void initState() {
    super.initState();
    _today = dateOnly(DateTime.now());
    _selectedDate = _today;
    _heatmapYear = _today.year;
    _heatmapMonth = _today.month;
    _loadAll();
  }

  // ---------------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------------

  Future<void> _loadAll() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Session expired.\nPlease sign in again.';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // ONE query for the entire history: one row per active day.
      final rows = await supabase
          .from('daily_progress')
          .select('progress_date, total_tasks, completed_tasks')
          .eq('user_id', user.id)
          .order('progress_date', ascending: true);

      final map = <String, DayStat>{};
      for (final r in (rows as List)) {
        final raw = r['progress_date']?.toString();
        if (raw == null) continue;
        final parsed = DateTime.tryParse(raw);
        if (parsed == null) continue;
        final d = DateTime(parsed.year, parsed.month, parsed.day);
        map[ymd(d)] = DayStat(
          date: d,
          total: (r['total_tasks'] as num?)?.toInt() ?? 0,
          completed: (r['completed_tasks'] as num?)?.toInt() ?? 0,
        );
      }

      if (!mounted) return;
      setState(() {
        _byDate
          ..clear()
          ..addAll(map);
        _allDays = map.values.toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        _loading = false;
        _error = null;
      });

      await _loadDayDetail(_selectedDate);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load your progress.";
      });
    }
  }

  Future<void> _loadDayDetail(DateTime date) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (mounted) setState(() => _detailLoading = true);

    try {
      final rows = await supabase
          .from('task_completion_history')
          .select('task_title, completed')
          .eq('user_id', user.id)
          .eq('completion_date', ymd(date))
          .order('created_at', ascending: true);

      final list = <HistoryEntry>[];
      for (final r in (rows as List)) {
        list.add(HistoryEntry(
          title: r['task_title']?.toString() ?? '',
          completed: r['completed'] == true,
        ));
      }

      if (!mounted) return;
      setState(() {
        _dayDetail = list;
        _detailLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dayDetail = [];
        _detailLoading = false;
      });
    }
  }

  Future<void> _selectDate(DateTime date) async {
    final d = dateOnly(date);
    if (d.isAfter(_today)) return; // never navigate into the future
    setState(() {
      _selectedDate = d;
      _heatmapYear = d.year;
      _heatmapMonth = d.month;
    });
    await _loadDayDetail(d);
  }

  Future<void> _pickDate() async {
    final first = _allDays.isEmpty
        ? DateTime(_today.year - 1, 1, 1)
        : _allDays.first.date;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(first.year, 1, 1),
      lastDate: _today,
    );
    if (picked != null) await _selectDate(picked);
  }

  // ---------------------------------------------------------------------------
  // DERIVED METRICS — all computed from _byDate, zero extra queries.
  // ---------------------------------------------------------------------------

  DayStat? get _selectedStat => _byDate[ymd(_selectedDate)];

  int get _currentStreak {
    // Start at today. If today isn't a success yet the day may still be in
    // progress, so the streak is measured from yesterday instead of breaking.
    DateTime cursor = _today;
    if (!(_byDate[ymd(cursor)]?.isSuccess ?? false)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (_byDate[ymd(cursor)]?.isSuccess ?? false) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int get _bestStreak {
    final successDays = _allDays.where((d) => d.isSuccess).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (successDays.isEmpty) return 0;

    int best = 1;
    int run = 1;
    for (int i = 1; i < successDays.length; i++) {
      final gap = successDays[i].date
          .difference(successDays[i - 1].date)
          .inDays;
      if (gap == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
    }
    return best;
  }

  int get _totalCompleted =>
      _allDays.fold<int>(0, (sum, d) => sum + d.completed);

  int get _averagePercent {
    final active = _allDays.where((d) => d.total > 0).toList();
    if (active.isEmpty) return 0;
    final sum = active.fold<double>(0, (s, d) => s + d.fraction);
    return ((sum / active.length) * 100).round();
  }

  List<int> get _availableYears {
    final years = <int>{_today.year};
    for (final d in _allDays) {
      years.add(d.date.year);
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Last [_chartRange] days ending today, oldest first. Missing days are 0.
  List<DayStat> get _chartSeries {
    final out = <DayStat>[];
    for (int i = _chartRange - 1; i >= 0; i--) {
      final d = _today.subtract(Duration(days: i));
      out.add(_byDate[ymd(d)] ?? DayStat(date: d, total: 0, completed: 0));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    if (_loading) return _buildLoading(isDark, textColor);
    if (_error != null) return _buildError(isDark, textColor);

    final hasHistory = _allDays.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _buildHeader(isDark, textColor),
            const SizedBox(height: 20),
            _buildDateNav(isDark, textColor),
            const SizedBox(height: 28),

            if (!hasHistory) ...[
              _buildEmptyState(isDark, textColor),
            ] else ...[
              _buildHeatmapSection(isDark, textColor),
              const SizedBox(height: 28),
              _buildKpiGrid(isDark, textColor),
              const SizedBox(height: 28),
              _buildTrendChart(isDark, textColor),
              const SizedBox(height: 20),
              _buildVolumeChart(isDark, textColor),
              const SizedBox(height: 28),
              _buildDayDetail(isDark, textColor),
            ],
          ],
        ),
      ),
    );
  }

  // --- states ---------------------------------------------------------------

  Widget _buildLoading(bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          _buildHeader(isDark, textColor),
          const SizedBox(height: 40),
          _Shimmer(isDark: isDark, height: 190),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _Shimmer(isDark: isDark, height: 88)),
              const SizedBox(width: 14),
              Expanded(child: _Shimmer(isDark: isDark, height: 88)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Shimmer(isDark: isDark, height: 88)),
              const SizedBox(width: 14),
              Expanded(child: _Shimmer(isDark: isDark, height: 88)),
            ],
          ),
          const SizedBox(height: 20),
          _Shimmer(isDark: isDark, height: 150),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark, Color textColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: textColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadAll,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: kArqelinBlue.withValues(alpha: 0.15),
                  border:
                      Border.all(color: kArqelinBlue.withValues(alpha: 0.4)),
                ),
                child: Text('Retry',
                    style: GoogleFonts.outfit(
                        color: textColor, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color textColor) {
    return _GlassCard(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
        child: Column(
          children: [
            Icon(Icons.auto_graph_rounded,
                size: 44, color: kArqelinBlue.withValues(alpha: 0.7)),
            const SizedBox(height: 20),
            Text(
              'Your journey starts here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: textColor, fontSize: 22, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Text(
              'Complete your first task\nto build your progress history.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: textColor.withValues(alpha: 0.55),
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- header ---------------------------------------------------------------

  Widget _buildHeader(bool isDark, Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your',
                style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    color: textColor)),
            Text('Progress.',
                style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
          ],
        ),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(Icons.calendar_today_rounded,
                size: 20, color: textColor.withValues(alpha: 0.8)),
          ),
        ),
      ],
    );
  }

  Widget _buildDateNav(bool isDark, Color textColor) {
    final canGoForward = _selectedDate.isBefore(_today);

    return _GlassCard(
      isDark: isDark,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavArrow(
            icon: Icons.chevron_left_rounded,
            enabled: true,
            color: textColor,
            onTap: () => _selectDate(
                _selectedDate.subtract(const Duration(days: 1))),
          ),
          Text(
            prettyDate(_selectedDate),
            style: GoogleFonts.outfit(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
            ),
          ),
          _NavArrow(
            icon: Icons.chevron_right_rounded,
            enabled: canGoForward,
            color: textColor,
            onTap: canGoForward
                ? () => _selectDate(
                    _selectedDate.add(const Duration(days: 1)))
                : null,
          ),
        ],
      ),
    );
  }

  // --- heatmap --------------------------------------------------------------

  Widget _buildHeatmapSection(bool isDark, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('HEATMAP',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: isDark ? Colors.white54 : Colors.black54)),
            _SegmentedToggle(
              isDark: isDark,
              textColor: textColor,
              left: 'Monthly',
              right: 'Yearly',
              rightSelected: _yearlyView,
              onChanged: (yearly) => setState(() => _yearlyView = yearly),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            if (!_yearlyView) ...[
              Expanded(
                child: _PickerChip(
                  isDark: isDark,
                  textColor: textColor,
                  label: kMonthNames[_heatmapMonth - 1],
                  values: List.generate(12, (i) => i + 1),
                  labels: kMonthNames,
                  selected: _heatmapMonth,
                  onSelected: (v) => setState(() => _heatmapMonth = v),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _PickerChip(
                isDark: isDark,
                textColor: textColor,
                label: '$_heatmapYear',
                values: _availableYears,
                labels: _availableYears.map((y) => '$y').toList(),
                selected: _heatmapYear,
                onSelected: (v) => setState(() => _heatmapYear = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _GlassCard(
          isDark: isDark,
          child: _yearlyView
              ? _buildYearlyHeatmap(isDark, textColor)
              : _buildMonthlyHeatmap(isDark, textColor),
        ),
        const SizedBox(height: 12),
        _buildLegend(isDark, textColor),
      ],
    );
  }

  Color _cellColor(DayStat? s, bool isDark) {
    final emptyColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    if (s == null || s.total == 0) return emptyColor;

    final p = s.fraction;
    double a;
    if (p <= 0) {
      a = 0.14; // tasks existed, none completed
    } else if (p <= 0.25) {
      a = 0.30;
    } else if (p <= 0.50) {
      a = 0.48;
    } else if (p <= 0.75) {
      a = 0.66;
    } else if (p < 1.0) {
      a = 0.84;
    } else {
      a = 1.0;
    }
    return kArqelinBlue.withValues(alpha: a);
  }

  Widget _buildMonthlyHeatmap(bool isDark, Color textColor) {
    final firstOfMonth = DateTime(_heatmapYear, _heatmapMonth, 1);
    final daysInMonth =
        DateTime(_heatmapYear, _heatmapMonth + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - 1; // Monday = 0

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cell = (constraints.maxWidth - gap * 6) / 7;
        final totalCells = leadingBlanks + daysInMonth;
        final rows = (totalCells / 7).ceil();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${kMonthNames[_heatmapMonth - 1]} $_heatmapYear',
              style: GoogleFonts.outfit(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            Row(
              children: List.generate(7, (i) {
                return SizedBox(
                  width: cell,
                  child: Text(
                    kWeekdayShort[i][0],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: textColor.withValues(alpha: 0.35),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            for (int r = 0; r < rows; r++) ...[
              Row(
                children: List.generate(7, (c) {
                  final cellIndex = r * 7 + c;
                  final dayNum = cellIndex - leadingBlanks + 1;
                  final isBlank = dayNum < 1 || dayNum > daysInMonth;

                  Widget child;
                  if (isBlank) {
                    child = SizedBox(width: cell, height: cell);
                  } else {
                    final date =
                        DateTime(_heatmapYear, _heatmapMonth, dayNum);
                    child = _HeatCell(
                      size: cell,
                      radius: 8,
                      color: _cellColor(_byDate[ymd(date)], isDark),
                      isSelected: date == _selectedDate,
                      isFuture: date.isAfter(_today),
                      label: '$dayNum',
                      textColor: textColor,
                      onTap: date.isAfter(_today)
                          ? null
                          : () => _selectDate(date),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.only(right: c == 6 ? 0 : gap),
                    child: child,
                  );
                }),
              ),
              if (r != rows - 1) const SizedBox(height: gap),
            ],
          ],
        );
      },
    );
  }

  Widget _buildYearlyHeatmap(bool isDark, Color textColor) {
    final jan1 = DateTime(_heatmapYear, 1, 1);
    final dec31 = DateTime(_heatmapYear, 12, 31);
    final leading = jan1.weekday - 1;
    final totalDays = dec31.difference(jan1).inDays + 1;
    final weeks = ((leading + totalDays) / 7).ceil();

    const cell = 13.0;
    const gap = 3.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_heatmapYear',
          style: GoogleFonts.outfit(
              color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // month ruler
              SizedBox(
                height: 16,
                width: weeks * (cell + gap),
                child: Stack(
                  children: List.generate(12, (m) {
                    final first = DateTime(_heatmapYear, m + 1, 1);
                    final offsetDays =
                        first.difference(jan1).inDays + leading;
                    final weekIndex = offsetDays ~/ 7;
                    return Positioned(
                      left: weekIndex * (cell + gap),
                      top: 0,
                      child: Text(
                        kMonthShort[m],
                        style: GoogleFonts.outfit(
                          color: textColor.withValues(alpha: 0.35),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(weeks, (w) {
                  return Padding(
                    padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
                    child: Column(
                      children: List.generate(7, (d) {
                        final dayOffset = w * 7 + d - leading;
                        final isOutside =
                            dayOffset < 0 || dayOffset >= totalDays;

                        if (isOutside) {
                          return const Padding(
                            padding: EdgeInsets.only(bottom: gap),
                            child: SizedBox(width: cell, height: cell),
                          );
                        }

                        final date = jan1.add(Duration(days: dayOffset));
                        final future = date.isAfter(_today);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: gap),
                          child: _HeatCell(
                            size: cell,
                            radius: 3,
                            color: future
                                ? Colors.transparent
                                : _cellColor(_byDate[ymd(date)], isDark),
                            isSelected: date == _selectedDate,
                            isFuture: future,
                            textColor: textColor,
                            onTap: future ? null : () => _selectDate(date),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(bool isDark, Color textColor) {
    final levels = <double>[0.0, 0.14, 0.30, 0.48, 0.66, 0.84, 1.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less',
            style: GoogleFonts.outfit(
                color: textColor.withValues(alpha: 0.4), fontSize: 11)),
        const SizedBox(width: 8),
        for (final a in levels) ...[
          Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: a == 0.0
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05))
                  : kArqelinBlue.withValues(alpha: a),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Text('More',
            style: GoogleFonts.outfit(
                color: textColor.withValues(alpha: 0.4), fontSize: 11)),
      ],
    );
  }

  // --- KPIs -----------------------------------------------------------------

  Widget _buildKpiGrid(bool isDark, Color textColor) {
    final s = _selectedStat;
    final isToday = _selectedDate == _today;

    final cards = <Widget>[
      _KpiCard(
        isDark: isDark,
        textColor: textColor,
        value: s == null ? '—' : '${s.percent}%',
        label: isToday ? 'Completion today' : 'Completion',
        accent: true,
      ),
      _KpiCard(
        isDark: isDark,
        textColor: textColor,
        value: s == null ? '0 / 0' : '${s.completed} / ${s.total}',
        label: 'Completed',
      ),
      _KpiCard(
        isDark: isDark,
        textColor: textColor,
        value: '$_currentStreak',
        label: _currentStreak == 1 ? 'Day streak' : 'Day streak',
      ),
      _KpiCard(
        isDark: isDark,
        textColor: textColor,
        value: '$_bestStreak',
        label: 'Best streak',
      ),
      _KpiCard(
        isDark: isDark,
        textColor: textColor,
        value: '$_totalCompleted',
        label: 'Tasks completed',
      ),
      _KpiCard(
        isDark: isDark,
        textColor: textColor,
        value: '$_averagePercent%',
        label: 'Average',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards
              .map((c) => SizedBox(width: cardWidth, child: c))
              .toList(),
        );
      },
    );
  }

  // --- charts ---------------------------------------------------------------

  Widget _buildRangeToggle(bool isDark, Color textColor) {
    const ranges = [7, 30, 90];
    return Row(
      children: ranges.map((r) {
        final selected = _chartRange == r;
        return GestureDetector(
          onTap: () => setState(() => _chartRange = r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(left: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? kArqelinBlue.withValues(alpha: 0.25)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03)),
              border: Border.all(
                color: selected
                    ? kArqelinBlue.withValues(alpha: 0.6)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              '${r}D',
              style: GoogleFonts.outfit(
                color: selected
                    ? textColor
                    : textColor.withValues(alpha: 0.45),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTrendChart(bool isDark, Color textColor) {
    final series = _chartSeries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('COMPLETION TREND',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: isDark ? Colors.white54 : Colors.black54)),
            _buildRangeToggle(isDark, textColor),
          ],
        ),
        const SizedBox(height: 14),
        _GlassCard(
          isDark: isDark,
          child: SizedBox(
            height: 160,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final i = _indexFromX(
                        details.localPosition.dx,
                        constraints.maxWidth,
                        series.length);
                    if (i >= 0 && i < series.length) {
                      _selectDate(series[i].date);
                    }
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 160),
                    painter: _TrendPainter(
                      series: series,
                      selected: _selectedDate,
                      isDark: isDark,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeChart(bool isDark, Color textColor) {
    final series = _chartSeries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TASKS COMPLETED',
            style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: isDark ? Colors.white54 : Colors.black54)),
        const SizedBox(height: 14),
        _GlassCard(
          isDark: isDark,
          child: SizedBox(
            height: 140,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final i = _indexFromX(
                        details.localPosition.dx,
                        constraints.maxWidth,
                        series.length);
                    if (i >= 0 && i < series.length) {
                      _selectDate(series[i].date);
                    }
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 140),
                    painter: _VolumePainter(
                      series: series,
                      selected: _selectedDate,
                      isDark: isDark,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  int _indexFromX(double dx, double width, int count) {
    if (count <= 0 || width <= 0) return -1;
    final step = width / count;
    return (dx / step).floor().clamp(0, count - 1);
  }

  // --- daily detail ---------------------------------------------------------

  Widget _buildDayDetail(bool isDark, Color textColor) {
    final s = _selectedStat;
    final done = _dayDetail.where((e) => e.completed).toList();
    final pending = _dayDetail.where((e) => !e.completed).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(longDate(_selectedDate),
            style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: isDark ? Colors.white54 : Colors.black54)),
        const SizedBox(height: 14),
        _GlassCard(
          isDark: isDark,
          child: _detailLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          s == null ? '—' : '${s.percent}%',
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            s == null
                                ? 'no activity'
                                : '${s.completed} of ${s.total} completed',
                            style: GoogleFonts.outfit(
                              color: textColor.withValues(alpha: 0.55),
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_dayDetail.isEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'No tasks recorded for this day.',
                        style: GoogleFonts.outfit(
                          color: textColor.withValues(alpha: 0.4),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _detailLabel('COMPLETED', textColor),
                      const SizedBox(height: 10),
                      for (final e in done)
                        _detailRow(e.title, true, textColor),
                    ],
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _detailLabel('INCOMPLETE', textColor),
                      const SizedBox(height: 10),
                      for (final e in pending)
                        _detailRow(e.title, false, textColor),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _detailLabel(String text, Color textColor) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: textColor.withValues(alpha: 0.35),
        ),
      );

  Widget _detailRow(String title, bool done, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? kArqelinBlue : Colors.transparent,
              border: Border.all(
                color: done
                    ? kArqelinBlue
                    : textColor.withValues(alpha: 0.3),
                width: 1.6,
              ),
            ),
            child: done
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                color: done
                    ? textColor.withValues(alpha: 0.85)
                    : textColor.withValues(alpha: 0.5),
                fontSize: 15,
                fontWeight: FontWeight.w300,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: textColor.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SHARED WIDGETS — same glass language as the tasks page
// =============================================================================

class _GlassCard extends StatelessWidget {
  final bool isDark;
  final Widget child;
  final EdgeInsets padding;

  const _GlassCard({
    required this.isDark,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final Color color;
  final VoidCallback? onTap;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 40,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 24,
          color: color.withValues(alpha: enabled ? 0.75 : 0.18),
        ),
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  const _SegmentedToggle({
    required this.isDark,
    required this.textColor,
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(left, !rightSelected, () => onChanged(false)),
          _segment(right, rightSelected, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: selected
              ? kArqelinBlue.withValues(alpha: 0.28)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: selected
                ? textColor
                : textColor.withValues(alpha: 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PickerChip<T> extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final String label;
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  const _PickerChip({
    required this.isDark,
    required this.textColor,
    required this.label,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      color: isDark ? const Color(0xFF1B1B29) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      itemBuilder: (context) => [
        for (int i = 0; i < values.length; i++)
          PopupMenuItem<T>(
            value: values[i],
            child: Text(
              labels[i],
              style: GoogleFonts.outfit(
                color: values[i] == selected ? kArqelinBlue : textColor,
                fontWeight: values[i] == selected
                    ? FontWeight.w600
                    : FontWeight.w300,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: textColor.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  final double size;
  final double radius;
  final Color color;
  final bool isSelected;
  final bool isFuture;
  final String? label;
  final Color textColor;
  final VoidCallback? onTap;

  const _HeatCell({
    required this.size,
    required this.radius,
    required this.color,
    required this.isSelected,
    required this.isFuture,
    required this.textColor,
    this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: isSelected
              ? Border.all(color: textColor.withValues(alpha: 0.85), width: 1.6)
              : null,
        ),
        alignment: Alignment.center,
        child: label == null
            ? null
            : Text(
                label!,
                style: GoogleFonts.outfit(
                  fontSize: size > 30 ? 11 : 9,
                  fontWeight: FontWeight.w500,
                  color: textColor.withValues(alpha: isFuture ? 0.18 : 0.7),
                ),
              ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final String value;
  final String label;
  final bool accent;

  const _KpiCard({
    required this.isDark,
    required this.textColor,
    required this.value,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: accent
                ? kArqelinBlue.withValues(alpha: isDark ? 0.18 : 0.10)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.02)),
            border: Border.all(
              color: accent
                  ? kArqelinBlue.withValues(alpha: 0.45)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: textColor.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final bool isDark;
  final double height;

  const _Shimmer({required this.isDark, required this.height});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final a = 0.03 + (_c.value * 0.05);
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: widget.isDark
                ? Colors.white.withValues(alpha: a)
                : Colors.black.withValues(alpha: a * 0.8),
          ),
        );
      },
    );
  }
}

// =============================================================================
// PAINTERS — no chart package needed
// =============================================================================

class _TrendPainter extends CustomPainter {
  final List<DayStat> series;
  final DateTime selected;
  final bool isDark;

  _TrendPainter({
    required this.series,
    required this.selected,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    const leftPad = 30.0;
    const topPad = 10.0;
    const bottomPad = 20.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - topPad - bottomPad;

    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 1;

    final labelStyle = TextStyle(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.32),
      fontSize: 9,
    );

    // gridlines at 0 / 50 / 100
    for (final pct in [0.0, 0.5, 1.0]) {
      final y = topPad + chartH * (1 - pct);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: '${(pct * 100).toInt()}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    final step = chartW / series.length;
    double xAt(int i) => leftPad + step * i + step / 2;
    double yAt(double f) => topPad + chartH * (1 - f);

    // line + fill
    final path = Path();
    final fill = Path();
    for (int i = 0; i < series.length; i++) {
      final x = xAt(i);
      final y = yAt(series[i].fraction);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, topPad + chartH);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(xAt(series.length - 1), topPad + chartH);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            kArqelinBlue.withValues(alpha: 0.35),
            kArqelinBlue.withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = kArqelinBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // points, with the selected day emphasised
    for (int i = 0; i < series.length; i++) {
      final isSel = dateOnly(series[i].date) == dateOnly(selected);
      final x = xAt(i);
      final y = yAt(series[i].fraction);

      if (isSel) {
        canvas.drawLine(
          Offset(x, topPad),
          Offset(x, topPad + chartH),
          Paint()
            ..color = kArqelinBlue.withValues(alpha: 0.35)
            ..strokeWidth = 1.2,
        );
        canvas.drawCircle(Offset(x, y), 5.5,
            Paint()..color = isDark ? Colors.white : Colors.black87);
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = kArqelinBlue);
      } else if (series.length <= 14) {
        canvas.drawCircle(
            Offset(x, y), 2.6, Paint()..color = kArqelinBlue);
      }
    }

    // x labels: first, middle, last
    final marks = <int>{0, series.length ~/ 2, series.length - 1};
    for (final i in marks) {
      if (i < 0 || i >= series.length) continue;
      final d = series[i].date;
      final tp = TextPainter(
        text: TextSpan(
            text: '${d.day} ${kMonthShort[d.month - 1]}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (xAt(i) - tp.width / 2)
          .clamp(leftPad, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - bottomPad + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.series != series || old.selected != selected || old.isDark != isDark;
}

class _VolumePainter extends CustomPainter {
  final List<DayStat> series;
  final DateTime selected;
  final bool isDark;

  _VolumePainter({
    required this.series,
    required this.selected,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    const leftPad = 24.0;
    const topPad = 10.0;
    const bottomPad = 20.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - topPad - bottomPad;

    int maxVal = 1;
    for (final s in series) {
      if (s.completed > maxVal) maxVal = s.completed;
    }

    final labelStyle = TextStyle(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.32),
      fontSize: 9,
    );

    // baseline
    canvas.drawLine(
      Offset(leftPad, topPad + chartH),
      Offset(size.width, topPad + chartH),
      Paint()
        ..color =
            (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
        ..strokeWidth = 1,
    );

    final maxTp = TextPainter(
      text: TextSpan(text: '$maxVal', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    maxTp.paint(canvas, Offset(leftPad - maxTp.width - 6, topPad - 2));

    final step = chartW / series.length;
    final barW = math.min(step * 0.6, 16.0);

    for (int i = 0; i < series.length; i++) {
      final s = series[i];
      final isSel = dateOnly(s.date) == dateOnly(selected);
      final h = maxVal == 0 ? 0.0 : chartH * (s.completed / maxVal);
      final cx = leftPad + step * i + step / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, topPad + chartH - h, barW,
            h < 2 ? 2 : h),
        const Radius.circular(4),
      );

      canvas.drawRRect(
        rect,
        Paint()
          ..color = isSel
              ? kArqelinBlue
              : kArqelinBlue.withValues(alpha: s.completed == 0 ? 0.12 : 0.45),
      );
    }

    final marks = <int>{0, series.length ~/ 2, series.length - 1};
    for (final i in marks) {
      if (i < 0 || i >= series.length) continue;
      final d = series[i].date;
      final tp = TextPainter(
        text: TextSpan(
            text: '${d.day} ${kMonthShort[d.month - 1]}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (leftPad + step * i + step / 2 - tp.width / 2)
          .clamp(leftPad, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - bottomPad + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _VolumePainter old) =>
      old.series != series || old.selected != selected || old.isDark != isDark;
}