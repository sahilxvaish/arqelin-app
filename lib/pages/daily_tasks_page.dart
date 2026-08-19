import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DailyTasksPage extends StatefulWidget {
  const DailyTasksPage({super.key});

  @override
  State<DailyTasksPage> createState() => _DailyTasksPageState();
}

class _DailyTasksPageState extends State<DailyTasksPage> {
  final supabase = Supabase.instance.client;

  /// The device's local calendar date (IST) these tasks belong to.
  /// Matches the `task_date` column and Postgres arqelin_local_today().
  String get _todayStr {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  // ---------------------------------------------------------------------------
  // SINGLE SOURCE OF TRUTH
  // The UI renders from _tasks and nothing else. Every successful backend write
  // mutates THIS list inside setState(). No realtime stream, no derived copies.
  // ---------------------------------------------------------------------------
  final List<Map<String, dynamic>> _tasks = [];

  bool _loading = true;
  String? _error;

  /// Task ids with an in-flight write, so a second tap is ignored.
  final Set<Object> _busyIds = <Object>{};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  int _indexOfId(Object? id) => _tasks.indexWhere((t) => t['id'] == id);

  void _snack(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.redAccent : Colors.green,
      duration: const Duration(seconds: 2),
    ));
  }

  /// Reads today's tasks for this user. `task_date` is added by the
  /// 001_progress_history.sql migration and defaults to the IST date.
  Future<List<Map<String, dynamic>>> _selectTasks(String userId) async {
    final rows = await supabase
        .from('tasks')
        .select()
        .eq('user_id', userId)
        .eq('task_date', _todayStr)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------

  Future<void> _loadTasks() async {
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
      final rows = await _selectTasks(user.id);
      if (!mounted) return;
      setState(() {
        _tasks
          ..clear()
          ..addAll(rows);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load tasks.\nCheck your connection.';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // CREATE — insert, take the RETURNED row, append it locally.
  // The DB trigger writes the matching history row in the same transaction.
  // ---------------------------------------------------------------------------

  Future<void> _createTask(String title) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw AuthException('Session expired. Please sign in again.');
    }

    final inserted = await supabase
        .from('tasks')
        .insert({
          'user_id': user.id,
          'title': title,
          'is_completed': false,
          'task_date': _todayStr,
        })
        .select()
        .single();

    if (!mounted) return;
    setState(() => _tasks.add(Map<String, dynamic>.from(inserted)));
  }

  // ---------------------------------------------------------------------------
  // UPDATE (title) — match by primary key, replace the row in local state.
  // ---------------------------------------------------------------------------

  Future<void> _updateTitle(Object taskId, String title) async {
    final updated = await supabase
        .from('tasks')
        .update({'title': title})
        .eq('id', taskId)
        .select()
        .single();

    if (!mounted) return;
    setState(() {
      final i = _indexOfId(taskId);
      if (i != -1) _tasks[i] = Map<String, dynamic>.from(updated);
    });
  }

  // ---------------------------------------------------------------------------
  // UPDATE (completion) — optimistic flip, rolled back if the write fails.
  // ---------------------------------------------------------------------------

  Future<void> _toggleTask(Map<String, dynamic> task) async {
    final Object? id = task['id'];
    if (id == null || _busyIds.contains(id)) return;

    final i = _indexOfId(id);
    if (i == -1) return;

    final bool current = _tasks[i]['is_completed'] == true;

    setState(() {
      _busyIds.add(id);
      _tasks[i] = {..._tasks[i], 'is_completed': !current};
    });

    try {
      final updated = await supabase
          .from('tasks')
          .update({'is_completed': !current})
          .eq('id', id)
          .select()
          .single();

      if (!mounted) return;
      setState(() {
        final j = _indexOfId(id);
        if (j != -1) _tasks[j] = Map<String, dynamic>.from(updated);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          final j = _indexOfId(id);
          if (j != -1) _tasks[j] = {..._tasks[j], 'is_completed': current};
        });
      }
      _snack('Could not update task.');
    } finally {
      _busyIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // DELETE — delete by primary key, confirm a row came back, remove locally.
  // The BEFORE DELETE trigger clears today's history row only; older history
  // rows survive with their title snapshot intact.
  // ---------------------------------------------------------------------------

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final Object? id = task['id'];
    if (id == null || _busyIds.contains(id)) return;

    setState(() => _busyIds.add(id));

    try {
      final deleted =
          await supabase.from('tasks').delete().eq('id', id).select();

      if (!mounted) return;

      if (deleted.isEmpty) {
        _snack('Task not found. Refreshing…');
        await _loadTasks();
        return;
      }

      setState(() => _tasks.removeWhere((t) => t['id'] == id));
    } catch (_) {
      _snack('Could not delete task.');
    } finally {
      _busyIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // ADD / EDIT TASK DIALOG
  // The controller lives inside _TaskDialog, which owns and disposes it in its
  // own dispose(). No .whenComplete() disposal — that was the Cancel crash.
  // ---------------------------------------------------------------------------

  void _showTaskDialog({Map<String, dynamic>? taskToEdit}) {
    final bool isEdit = taskToEdit != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _TaskDialog(
          isEdit: isEdit,
          isDark: isDark,
          initialTitle: isEdit ? (taskToEdit['title']?.toString() ?? '') : '',
          onSave: (String title) async {
            if (isEdit) {
              await _updateTitle(taskToEdit['id'] as Object, title);
            } else {
              await _createTask(title);
            }
          },
          onError: (String message) => _snack(message),
        );
      },
    );
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
      child: _buildBody(isDark, textColor),
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
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: textColor, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loadTasks,
              child: Text('Retry',
                  style: GoogleFonts.outfit(
                      color: textColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    final completedTasks =
        _tasks.where((t) => t['is_completed'] == true).length;
    final double progress = _tasks.isEmpty ? 0 : completedTasks / _tasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),

        // --- HEADER & ANIMATED PROGRESS RING ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Daily',
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
            SizedBox(
              width: 70,
              height: 70,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: value,
                        strokeWidth: 6,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? Colors.white : Colors.black87),
                      ),
                      Center(
                        child: Text(
                          '${(value * 100).toInt()}%',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: textColor,
                              fontSize: 16),
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          ],
        ),

        const SizedBox(height: 30),
        Text(
          'TASKS FOR TODAY',
          style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: isDark ? Colors.white54 : Colors.black54),
        ),
        const SizedBox(height: 16),

        // --- LIVE TASK LIST (renders from _tasks) ---
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadTasks,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              itemCount: _tasks.length + 1,
              padding: const EdgeInsets.only(bottom: 120),
              itemBuilder: (context, index) {
                if (index == _tasks.length) {
                  return GestureDetector(
                    onTap: () => _showTaskDialog(),
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.03)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline,
                              color: textColor.withValues(alpha: 0.6)),
                          const SizedBox(width: 8),
                          Text('Add New Task',
                              style: GoogleFonts.outfit(
                                  color: textColor.withValues(alpha: 0.6),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  );
                }

                final task = _tasks[index];
                return _SwipeableTaskCard(
                  // Keyed by primary key so swipe state follows the right row
                  // when the list changes.
                  key: ValueKey(task['id']),
                  task: task,
                  isDark: isDark,
                  onToggle: () => _toggleTask(task),
                  onEdit: () => _showTaskDialog(taskToEdit: task),
                  onDelete: () => _deleteTask(task),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TASK DIALOG
// Owns its TextEditingController and disposes it in State.dispose(), which
// Flutter calls only after the dialog is fully unmounted (after the exit
// transition). This is the single, safe disposal path.
// =============================================================================
class _TaskDialog extends StatefulWidget {
  final bool isEdit;
  final bool isDark;
  final String initialTitle;
  final Future<void> Function(String title) onSave;
  final void Function(String message) onError;

  const _TaskDialog({
    required this.isEdit,
    required this.isDark,
    required this.initialTitle,
    required this.onSave,
    required this.onError,
  });

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    // Runs only once the dialog widget is truly gone from the tree.
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Releases focus before popping so no live EditableText outlives this State.
  void _close() {
    if (!mounted) return;
    _focusNode.unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _saving) return;

    setState(() => _saving = true);

    try {
      await widget.onSave(title);
      if (!mounted) return;
      _close();
    } on AuthException catch (e) {
      if (mounted) _close();
      widget.onError(e.message);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _saving = false);
      widget.onError(e.message);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      widget.onError('Could not save. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF151521).withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isEdit ? 'Edit Task' : 'New Task',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                enabled: !_saving,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'What needs to be done?',
                  hintStyle:
                      TextStyle(color: textColor.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    // Cancel: no DB call, no state change, just closes.
                    onPressed: _saving ? null : _close,
                    child: Text('Cancel',
                        style: GoogleFonts.outfit(
                            color: textColor.withValues(alpha: 0.6))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(widget.isEdit ? 'Save' : 'Add',
                            style: GoogleFonts.outfit(color: Colors.white)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- SWIPEABLE GLASS CARD ---
class _SwipeableTaskCard extends StatefulWidget {
  final Map<String, dynamic> task;
  final bool isDark;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SwipeableTaskCard({
    super.key,
    required this.task,
    required this.isDark,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_SwipeableTaskCard> createState() => _SwipeableTaskCardState();
}

class _SwipeableTaskCardState extends State<_SwipeableTaskCard> {
  double _dragExtent = 0;
  final double _maxDrag = 140;

  @override
  Widget build(BuildContext context) {
    final isDone = widget.task['is_completed'] ?? false;
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.03),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() => _dragExtent = 0);
                      widget.onEdit();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.1),
                      ),
                      child: Icon(Icons.edit, color: textColor, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      setState(() => _dragExtent = 0);
                      widget.onDelete();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _dragExtent += details.primaryDelta!;
                if (_dragExtent > 0) _dragExtent = 0;
                if (_dragExtent < -_maxDrag - 20) _dragExtent = -_maxDrag - 20;
              });
            },
            onHorizontalDragEnd: (details) {
              setState(() {
                if (_dragExtent < -(_maxDrag / 2)) {
                  _dragExtent = -_maxDrag;
                } else {
                  _dragExtent = 0;
                }
              });
            },
            child: AnimatedContainer(
              duration: Duration(
                  milliseconds:
                      _dragExtent == 0 || _dragExtent == -_maxDrag ? 300 : 0),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_dragExtent, 0, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: widget.onToggle,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDone
                                  ? (widget.isDark
                                      ? Colors.white
                                      : Colors.black87)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isDone
                                    ? (widget.isDark
                                        ? Colors.white
                                        : Colors.black87)
                                    : textColor.withValues(alpha: 0.4),
                                width: 2,
                              ),
                            ),
                            child: isDone
                                ? Icon(Icons.check,
                                    size: 16,
                                    color: widget.isDark
                                        ? Colors.black
                                        : Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                              color: isDone
                                  ? textColor.withValues(alpha: 0.4)
                                  : textColor,
                              decoration:
                                  isDone ? TextDecoration.lineThrough : null,
                            ),
                            child: Text(widget.task['title']?.toString() ?? ''),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}