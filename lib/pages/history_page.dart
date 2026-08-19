import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Same accent the rest of Arqelin uses.
const Color _kArqelinBlue = Color(0xFF2B44FF);

const List<String> _kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _kMonthShort = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

const List<String> _kWeekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// =============================================================================
// MODELS
// =============================================================================
class _HistoryTask {
  final String title;
  final bool completed;

  const _HistoryTask({required this.title, required this.completed});
}

class _HistoryDay {
  final DateTime date;
  final List<_HistoryTask> tasks;

  const _HistoryDay({required this.date, required this.tasks});

  int get total => tasks.length;
  int get completed => tasks.where((t) => t.completed).length;
  int get percent => total == 0 ? 0 : ((completed / total) * 100).round();

  List<_HistoryTask> get done =>
      tasks.where((t) => t.completed).toList(growable: false);
  List<_HistoryTask> get pending =>
      tasks.where((t) => !t.completed).toList(growable: false);
}

/// Section heading emitted when the month changes while scrolling.
class _MonthHeader {
  final String label;
  const _MonthHeader(this.label);
}

// =============================================================================
// PAGE
// =============================================================================
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final supabase = Supabase.instance.client;

  /// Flattened render list: _MonthHeader and _HistoryDay entries interleaved.
  List<Object> _items = [];

  bool _loading = true;
  String? _error;

  /// ymd of the currently expanded card. Only one at a time.
  String? _expandedKey;

  /// 0 means "All".
  int _filterYear = 0;
  int _filterMonth = 0;

  List<int> _years = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ---------------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Session expired.\nPlease sign in again.';
      });
      return;
    }

    try {
      // One tiny query: the earliest recorded day tells us the year range.
      final earliest = await supabase
          .from('task_completion_history')
          .select('completion_date')
          .eq('user_id', user.id)
          .order('completion_date', ascending: true)
          .limit(1);

      final nowYear = DateTime.now().year;
      int firstYear = nowYear;

      if ((earliest as List).isNotEmpty) {
        final raw = earliest.first['completion_date']?.toString();
        final parsed = raw == null ? null : DateTime.tryParse(raw);
        if (parsed != null) firstYear = parsed.year;
      }

      final years = <int>[];
      for (int y = nowYear; y >= firstYear; y--) {
        years.add(y);
      }

      if (!mounted) return;
      setState(() => _years = years);
    } catch (_) {
      // Non-fatal: the filter just falls back to the current year.
      if (mounted) setState(() => _years = [DateTime.now().year]);
    }

    await _loadHistory();
  }

  /// ONE range query for the active filter, grouped locally by completion_date.
  Future<void> _loadHistory() async {
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
      var query = supabase
          .from('task_completion_history')
          .select('completion_date, task_title, completed')
          .eq('user_id', user.id);

      // Date-range narrowing happens server-side, never per-card.
      if (_filterYear != 0) {
        final DateTime from;
        final DateTime to;
        if (_filterMonth != 0) {
          from = DateTime(_filterYear, _filterMonth, 1);
          to = DateTime(_filterYear, _filterMonth + 1, 0);
        } else {
          from = DateTime(_filterYear, 1, 1);
          to = DateTime(_filterYear, 12, 31);
        }
        query = query
            .gte('completion_date', _ymd(from))
            .lte('completion_date', _ymd(to));
      }

      final rows = await query
          .order('completion_date', ascending: false)
          .order('created_at', ascending: true)
          .limit(5000);

      // Group by date, preserving insertion order within each day.
      final grouped = <String, List<_HistoryTask>>{};
      final dates = <String, DateTime>{};

      for (final r in (rows as List)) {
        final raw = r['completion_date']?.toString();
        if (raw == null) continue;
        final parsed = DateTime.tryParse(raw);
        if (parsed == null) continue;
        final d = DateTime(parsed.year, parsed.month, parsed.day);
        final key = _ymd(d);

        dates[key] = d;
        grouped.putIfAbsent(key, () => <_HistoryTask>[]).add(
              _HistoryTask(
                // Historical snapshot, not the current tasks.title.
                title: r['task_title']?.toString() ?? '',
                completed: r['completed'] == true,
              ),
            );
      }

      final days = dates.keys
          .map((k) => _HistoryDay(date: dates[k]!, tasks: grouped[k]!))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date)); // newest first

      // Flatten with a month heading whenever the month changes.
      final items = <Object>[];
      int? lastMonth;
      int? lastYear;
      for (final day in days) {
        if (day.date.month != lastMonth || day.date.year != lastYear) {
          items.add(_MonthHeader(
              '${_kMonthNames[day.date.month - 1].toUpperCase()} ${day.date.year}'));
          lastMonth = day.date.month;
          lastYear = day.date.year;
        }
        items.add(day);
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load your history.";
      });
    }
  }

  Future<void> _applyFilter({int? year, int? month}) async {
    setState(() {
      if (year != null) {
        _filterYear = year;
        if (year == 0) _filterMonth = 0; // month alone is meaningless
      }
      if (month != null) _filterMonth = month;
      _expandedKey = null;
    });
    await _loadHistory();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          _buildHeader(textColor),
          const SizedBox(height: 22),
          _buildFilters(isDark, textColor),
          const SizedBox(height: 20),
          Expanded(child: _buildBody(isDark, textColor)),
        ],
      ),
    );
  }

  Widget _buildHeader(Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('History.',
            style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: textColor)),
        const SizedBox(height: 4),
        Text('Your journey, day by day.',
            style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w300,
                color: textColor.withValues(alpha: 0.55))),
      ],
    );
  }

  Widget _buildFilters(bool isDark, Color textColor) {
    final monthValues = <int>[0, ...List.generate(12, (i) => i + 1)];
    final monthLabels = <String>['All months', ..._kMonthNames];

    final yearValues = <int>[0, ..._years];
    final yearLabels = <String>['All years', ..._years.map((y) => '$y')];

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _PickerChip<int>(
            isDark: isDark,
            textColor: textColor,
            label: _filterMonth == 0
                ? 'All months'
                : _kMonthNames[_filterMonth - 1],
            enabled: _filterYear != 0,
            values: monthValues,
            labels: monthLabels,
            selected: _filterMonth,
            onSelected: (v) => _applyFilter(month: v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _PickerChip<int>(
            isDark: isDark,
            textColor: textColor,
            label: _filterYear == 0 ? 'All years' : '$_filterYear',
            enabled: true,
            values: yearValues,
            labels: yearLabels,
            selected: _filterYear,
            onSelected: (v) => _applyFilter(year: v),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(bool isDark, Color textColor) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 38, color: textColor.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w300)),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _loadHistory,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _kArqelinBlue.withValues(alpha: 0.15),
                  border: Border.all(
                      color: _kArqelinBlue.withValues(alpha: 0.4)),
                ),
                child: Text('Retry',
                    style: GoogleFonts.outfit(
                        color: textColor, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      final filtered = _filterYear != 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_toggle_off_rounded,
                  size: 42, color: _kArqelinBlue.withValues(alpha: 0.6)),
              const SizedBox(height: 20),
              Text(
                filtered ? 'Nothing here.' : 'No history yet.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Text(
                filtered
                    ? 'No tasks were recorded\nin this period.'
                    : 'Complete your first task\nto start building your history.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: textColor.withValues(alpha: 0.5),
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

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 130),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];

          if (item is _MonthHeader) {
            return Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 22, bottom: 12),
              child: Text(
                item.label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            );
          }

          final day = item as _HistoryDay;
          final key = _ymd(day.date);

          return _HistoryDayCard(
            key: ValueKey(key),
            day: day,
            isDark: isDark,
            expanded: _expandedKey == key,
            onTap: () => setState(
                () => _expandedKey = _expandedKey == key ? null : key),
          );
        },
      ),
    );
  }
}

// =============================================================================
// DATE CARD — read-only. Tap toggles expansion; nothing else is interactive.
// =============================================================================
class _HistoryDayCard extends StatelessWidget {
  final _HistoryDay day;
  final bool isDark;
  final bool expanded;
  final VoidCallback onTap;

  const _HistoryDayCard({
    super.key,
    required this.day,
    required this.isDark,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark
                  ? Colors.white.withValues(alpha: expanded ? 0.07 : 0.05)
                  : Colors.black.withValues(alpha: expanded ? 0.04 : 0.02),
              border: Border.all(
                color: expanded
                    ? _kArqelinBlue.withValues(alpha: 0.45)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05)),
              ),
            ),
            child: Column(
              children: [
                // ---- summary row -------------------------------------------
                GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _DateBadge(
                            day: day.date, isDark: isDark, textColor: textColor),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _kWeekdayNames[day.date.weekday - 1],
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${day.date.day} ${_kMonthNames[day.date.month - 1]} ${day.date.year}',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w300,
                                  color: textColor.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${day.completed} / ${day.total}',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Text(
                              'Completed',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w300,
                                color: textColor.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: expanded ? 0.25 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 22,
                            color: textColor.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---- expanded body -----------------------------------------
                AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? _buildDetail(textColor)
                      : const SizedBox(width: double.infinity, height: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(Color textColor) {
    final done = day.done;
    final pending = day.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.percent}% completed',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: _kArqelinBlue.withValues(alpha: isDark ? 0.9 : 1.0),
                ),
              ),
              if (done.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionLabel('COMPLETED TASKS', textColor),
                const SizedBox(height: 12),
                for (final t in done) _taskRow(t, textColor),
              ],
              if (pending.isNotEmpty) ...[
                SizedBox(height: done.isEmpty ? 18 : 16),
                _sectionLabel('INCOMPLETE TASKS', textColor),
                const SizedBox(height: 12),
                for (final t in pending) _taskRow(t, textColor),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, Color textColor) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: textColor.withValues(alpha: 0.35),
        ),
      );

  Widget _taskRow(_HistoryTask task, Color textColor) {
    final done = task.completed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _kArqelinBlue : Colors.transparent,
              border: Border.all(
                color: done
                    ? _kArqelinBlue
                    : textColor.withValues(alpha: 0.28),
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
              task.title,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w300,
                color: done
                    ? textColor.withValues(alpha: 0.45)
                    : textColor.withValues(alpha: 0.85),
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
// COMPACT DATE BADGE
// =============================================================================
class _DateBadge extends StatelessWidget {
  final DateTime day;
  final bool isDark;
  final Color textColor;

  const _DateBadge({
    required this.day,
    required this.isDark,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _kArqelinBlue.withValues(alpha: isDark ? 0.18 : 0.10),
        border: Border.all(color: _kArqelinBlue.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}',
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              height: 1.0,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _kMonthShort[day.month - 1],
            style: GoogleFonts.outfit(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              height: 1.0,
              color: textColor.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FILTER CHIP — same look as the Progress screen's month/year pickers
// =============================================================================
class _PickerChip<T> extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final String label;
  final bool enabled;
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  const _PickerChip({
    required this.isDark,
    required this.textColor,
    required this.label,
    required this.enabled,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                color: textColor.withValues(alpha: enabled ? 1.0 : 0.35),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: textColor.withValues(alpha: enabled ? 0.5 : 0.2)),
        ],
      ),
    );

    if (!enabled) return content;

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
                color: values[i] == selected ? _kArqelinBlue : textColor,
                fontWeight: values[i] == selected
                    ? FontWeight.w600
                    : FontWeight.w300,
              ),
            ),
          ),
      ],
      child: content,
    );
  }
}